import Foundation
import SwiftUI
import Observation
import Translation

enum AppState: Equatable {
    case ready
    case recording
    case error(String)
}

enum TranscribeState: Equatable {
    case transcribing
    case done([TranscriptSegment])
    case error(String)
}

enum LLMTaskState: Equatable {
    case running(String)
    case done(String)
    case notDownloaded
    case error(String)
}

@Observable
@MainActor
class MainViewModel {

    // MARK: - App state
    var appState: AppState = .ready
    var recordings: [Recording] = []
    var statusMessage = "Ready"
    var elapsedSeconds: Int = 0

    // MARK: - Per-recording states
    var transcribeStates: [UUID: TranscribeState] = [:]
    var summaryStates: [UUID: LLMTaskState] = [:]

    // Translation: configuration trigger per recording (SwiftUI .translationTask 용)
    var translationConfigs: [UUID: TranslationSession.Configuration] = [:]
    var translationStates: [UUID: LLMTaskState] = [:]
    var pendingTranslationTexts: [UUID: [TranscriptSegment]] = [:]

    // MARK: - Services
    let player = AudioPlayerService()
    private let audio = AudioCaptureService()
    private let transcription = TranscriptionService()
    let llm = LocalLLMService()

    // MARK: - Whisper model state
    var isWhisperLoaded = false
    var whisperStatus = "Model not loaded"
    
    
    var isProcessing: Bool {
        transcribeStates.values.contains {
            if case .transcribing = $0 { return true }
            return false
        } ||
        summaryStates.values.contains {
            if case .running = $0 { return true }
            return false
        } ||
        translationStates.values.contains {
            if case .running = $0 { return true }
            return false
        }
    }
    
    private var recordingTimer: Timer?

    // MARK: - Lifecycle

    func onAppear() {
        loadRecordings()
    }

    // MARK: - Whisper model

    func loadWhisperModel() async {
        guard !isWhisperLoaded else { return }
        whisperStatus = "Loading model…"
        do {
            try await transcription.load { [weak self] msg in
                Task { @MainActor in self?.whisperStatus = msg }
            }
            isWhisperLoaded = true
            whisperStatus = "Model ready"
        } catch {
            whisperStatus = "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Recording

    var isRecording: Bool { appState == .recording }

    func toggleRecording() {
        switch appState {
        case .recording: stopRecording()
        case .ready, .error: startRecording()
        }
    }

    private func startRecording() {
        player.stop()
        Task {
            do {
                try await audio.startRecording()
                appState = .recording
                elapsedSeconds = 0
                statusMessage = "Recording…"
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.elapsedSeconds += 1
                    }
                }
            } catch {
                appState = .error(error.localizedDescription)
                statusMessage = error.localizedDescription
            }
        }
    }

    private func stopRecording() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        _ = audio.stopRecording()
        appState = .ready
        statusMessage = "Saved"
        loadRecordings()
    }

    // MARK: - Recordings list

    func loadRecordings() {
        recordings = AudioCaptureService.loadSavedRecordings()
    }

    func delete(_ recording: Recording) {
        if player.playingID == recording.id { player.stop() }
        transcribeStates.removeValue(forKey: recording.id)
        summaryStates.removeValue(forKey: recording.id)
        translationStates.removeValue(forKey: recording.id)
        translationConfigs.removeValue(forKey: recording.id)
        pendingTranslationTexts.removeValue(forKey: recording.id)
        try? AudioCaptureService.delete(recording)
        loadRecordings()
    }

    func deleteAll() {
        player.stop()
        transcribeStates.removeAll()
        summaryStates.removeAll()
        translationStates.removeAll()
        translationConfigs.removeAll()
        pendingTranslationTexts.removeAll()
        recordings.forEach { try? AudioCaptureService.delete($0) }
        loadRecordings()
    }

    // MARK: - Transcription

    func transcribe(_ recording: Recording) async {
        if !isWhisperLoaded { await loadWhisperModel() }
        guard isWhisperLoaded else { return }

        transcribeStates[recording.id] = .transcribing
        do {
            let segments = try await transcription.transcribe(
                audioURL: recording.url,
                onProgress: { _ in }
            )
            transcribeStates[recording.id] = segments.isEmpty
                ? .error("No speech detected")
                : .done(segments)
        } catch {
            transcribeStates[recording.id] = .error(error.localizedDescription)
        }
    }

    func clearTranscript(for recording: Recording) {
        transcribeStates.removeValue(forKey: recording.id)
        summaryStates.removeValue(forKey: recording.id)
        translationStates.removeValue(forKey: recording.id)
        translationConfigs.removeValue(forKey: recording.id)
    }

    // MARK: - Summarization (MLX LLM)

    func summarize(_ recording: Recording, language: LocalLLMService.SummaryLanguage) async {
        guard case .done(let segments) = transcribeStates[recording.id] else { return }
        let fullText = segments.map(\.text).joined(separator: " ")

        summaryStates[recording.id] = .running("")
        do {
            if !llm.isLoaded { try await llm.load() }
            var output = ""
            try await llm.summarize(text: fullText, language: language) { fullDecoded in
                output = fullDecoded
                Task { @MainActor in self.summaryStates[recording.id] = .running(fullDecoded) }
            }
            summaryStates[recording.id] = .done(output)
        } catch {
            summaryStates[recording.id] = .error(error.localizedDescription)
        }
    }

    func clearSummary(for recording: Recording) {
        summaryStates.removeValue(forKey: recording.id)
    }

    // MARK: - Translation (Apple Translation API via .translationTask)

    /// .translationTask modifier가 감지하도록 configuration 세팅
    func triggerTranslation(_ recording: Recording, from sourceLang: String?, to language: TranslationLanguage) {
        guard case .done(let segments) = transcribeStates[recording.id] else { return }

        let id = recording.id
        let source = sourceLang.flatMap { Locale.Language(identifier: $0) }

        Task {
            let availability = LanguageAvailability()
            let status: LanguageAvailability.Status

            if let source {
                status = await availability.status(from: source, to: language.locale)
            } else {
                // Source unknown — assume supported, let translationTask handle it
                status = .supported
            }

            switch status {
            case .installed, .supported:
                self.pendingTranslationTexts[id] = segments
                self.translationStates[id] = .running("Translating…")
                self.translationConfigs[id] = TranslationSession.Configuration(
                    source: source,
                    target: language.locale
                )
            case .unsupported:
                self.translationStates[id] = .error("This language pair is not supported.")
            @unknown default:
                self.translationStates[id] = .error("Unknown language availability.")
            }
        }
    }
    /// .translationTask 클로저에서 호출 — 실제 번역 수행
    func performTranslation(for recordingID: UUID, using session: TranslationSession) async throws {
        guard let segments = pendingTranslationTexts[recordingID], !segments.isEmpty else { return }

        let requests = segments.map {
            TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id.uuidString)
        }
        let responses = try await session.translations(from: requests)
        let result = responses.map(\.targetText).joined(separator: "\n\n")
        translationStates[recordingID] = .done(result)

        pendingTranslationTexts.removeValue(forKey: recordingID)
    }

    func clearTranslation(for recording: Recording) {
        translationStates.removeValue(forKey: recording.id)
        translationConfigs.removeValue(forKey: recording.id)
        pendingTranslationTexts.removeValue(forKey: recording.id)
    }

    // MARK: - Helpers

    /// Returns the detected language from the first transcribed segment.
    func detectedLanguage(for recording: Recording) -> String? {
        if case .done(let segments) = transcribeStates[recording.id] {
            return segments.first?.detectedLanguage
        }
        return nil
    }

    var formattedElapsed: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }
}
