import Foundation
import SwiftUI
import Observation
import Translation
import SwiftData
import WhisperKit

enum AppState: Equatable {
    case ready
    case recording
    case error(String)
}

enum TranscribeState: Equatable {
    case transcribing(String)
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
class TranslationState {
    var config: TranslationSession.Configuration?
}

@Observable
@MainActor
class MainViewModel {
    // MARK: - App state
    var appState: AppState = .ready
    var recordings: [Recording] = []
    var allMetadata: [RecordingMetadata] = []
    var statusMessage = "Ready"
    var elapsedSeconds: Int = 0

    // MARK: - Per-recording states
    var transcribeStates: [UUID: TranscribeState] = [:]
    var summaryStates: [UUID: LLMTaskState] = [:]

    // Translation
    var translationStateObjects: [UUID: TranslationState] = [:]
    var translationStates: [UUID: LLMTaskState] = [:]
    var pendingTranslationTexts: [UUID: [TranscriptSegment]] = [:]

    // MARK: - Folder navigation
    var currentFolder: RecordingFolder?
    var folders: [RecordingFolder] = []

    // MARK: - Services
    let player = AudioPlayerService()
    private let audio = AudioCaptureService()
    private let transcription = TranscriptionService()
    let llm = LocalLLMService()

    var modelContext: ModelContext?

    // MARK: - Whisper model state
    var isWhisperLoaded = false
    var whisperStatus = "Model not loaded"
    var showMicrophonePermissionAlert = false

    private var recordingTimer: Timer?
    var whisperPipe: WhisperKit? { transcription.loadedPipe }
    var showMaxDurationAlert = false

    func onAppear() {
        loadRecordings()
        loadFolders()
    }

    // MARK: - Folder

    var visibleFolders: [RecordingFolder] {
        folders.filter { $0.parent?.id == currentFolder?.id }
    }

    var visibleRecordingItems: [RecordingItem] {
        let folderID = currentFolder?.id
        return recordings.compactMap { rec in
            let metadata = allMetadata.first { $0.filename == rec.filename }
            guard metadata?.folder?.id == folderID else {
                if metadata == nil && folderID == nil {
                    return RecordingItem(
                        recording: rec,
                        displayName: rec.formattedDate,
                        folder: nil
                    )
                }
                return nil
            }
            return RecordingItem(
                recording: rec,
                displayName: metadata?.displayName ?? rec.formattedDate,
                folder: metadata?.folder
            )
        }
    }

    var folderPathName: String {
        currentFolder?.name ?? "Home"
    }

    var isAtRoot: Bool {
        currentFolder == nil
    }

    func loadFolders() {
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<RecordingFolder>(
            sortBy: [SortDescriptor(\.createdAt)]
        )
        folders = (try? context.fetch(descriptor)) ?? []
    }

    func createFolder(name: String) -> Bool {
        guard let context = modelContext else { return false }
        guard NameValidator.isValid(name) else { return false }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let folder = RecordingFolder(name: trimmed)
        folder.parent = currentFolder
        context.insert(folder)
        try? context.save()
        loadFolders()
        return true
    }

    func deleteFolder(_ folder: RecordingFolder) {
        guard let context = modelContext else { return }
        context.delete(folder)
        try? context.save()
        loadFolders()
    }

    func renameFolder(_ folder: RecordingFolder, to newName: String) -> Bool {
        guard NameValidator.isValid(newName) else { return false }
        folder.name = newName.trimmingCharacters(in: .whitespaces)
        try? modelContext?.save()
        loadFolders()
        return true
    }

    func enterFolder(_ folder: RecordingFolder) {
        player.stop()
        currentFolder = folder
    }

    func goBack() {
        player.stop()
        currentFolder = currentFolder?.parent
    }

    // MARK: - Whisper model

    func loadWhisperModel(onProgress: ((String) -> Void)? = nil) async {
        guard !isWhisperLoaded else { return }
        whisperStatus = "Loading model…"
        do {
            try await transcription.load { [weak self] msg in
                Task { @MainActor [weak self] in
                    self?.whisperStatus = msg
                    onProgress?(msg)
                }
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

        // Auto-stop when max duration is reached
        audio.onMaxDurationReached = { [weak self] in
            guard let self else { return }
            self.recordingTimer?.invalidate()
            self.recordingTimer = nil
            self.appState = .ready
            self.statusMessage = "Saved"
            self.loadRecordings()
            self.showMaxDurationAlert = true

            if let newRec = self.recordings.first,
               let folder = self.currentFolder {
                if let context = self.modelContext {
                    let metadata = self.fetchOrCreateMetadata(for: newRec, context: context)
                    metadata.folder = folder
                    try? context.save()
                }
            }
        }

        Task {
            do {
                try await audio.startRecording()
                appState = .recording
                elapsedSeconds = 0
                statusMessage = "Recording…"
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    Task { @MainActor [weak self] in
                        self?.elapsedSeconds += 1
                    }
                }
            } catch let error as RecordingError {
                if error == .permissionDenied {
                    showMicrophonePermissionAlert = true
                }
                appState = .error(error.localizedDescription)
            } catch {
                appState = .error(error.localizedDescription)
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

        // 새 녹음을 현재 폴더에 자동 배치
        if let newRec = recordings.first, let folder = currentFolder {
            if let context = modelContext {
                let metadata = fetchOrCreateMetadata(for: newRec, context: context)
                metadata.folder = folder
                try? context.save()
            }
        }
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
        translationStateObjects.removeValue(forKey: recording.id)
        pendingTranslationTexts.removeValue(forKey: recording.id)

        if let context = modelContext,
           let metadata = allMetadata.first(where: { $0.filename == recording.filename }) {
            context.delete(metadata)
            try? context.save()
        }

        try? AudioCaptureService.delete(recording)
        loadRecordings()
    }

    func deleteAll() {
        player.stop()
        transcribeStates.removeAll()
        summaryStates.removeAll()
        translationStates.removeAll()
        translationStateObjects.removeAll()
        pendingTranslationTexts.removeAll()
        recordings.forEach { try? AudioCaptureService.delete($0) }
        loadRecordings()
    }

    // MARK: - Recording rename

    func renameRecording(_ recording: Recording, to newName: String) -> Bool {
        guard NameValidator.isValid(newName) else { return false }
        guard let context = modelContext else { return false }
        let metadata = fetchOrCreateMetadata(for: recording, context: context)
        metadata.displayName = newName.trimmingCharacters(in: .whitespaces)
        try? context.save()
        return true
    }

    // MARK: - Transcription
    var isProcessing: Bool {
        !isWhisperLoaded && whisperStatus != "Model not loaded" ||
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

    var isTranscribing: Bool {
        transcribeStates.values.contains {
            if case .transcribing = $0 { return true }
            return false
        }
    }

    func transcribe(_ recording: Recording, language: String) async {
        let id = recording.id
        let lang: String? = language

        if !isWhisperLoaded {
            transcribeStates[id] = .transcribing("Loading Model...")
            await loadWhisperModel { [weak self] msg in
                Task { @MainActor [weak self] in
                    self?.transcribeStates[id] = .transcribing(msg)
                }
            }
        }

        guard isWhisperLoaded else {
            transcribeStates[id] = .error("Failed to load model")
            return
        }

        transcribeStates[id] = .transcribing("Transcribing… 0%")
        do {
            let segments = try await transcription.transcribe(
                audioURL: recording.url,
                language: lang,
                onProgress: { [weak self] msg in
                    Task { @MainActor [weak self] in
                        self?.transcribeStates[id] = .transcribing(msg)
                    }
                }
            )
            if segments.isEmpty {
                transcribeStates[id] = .error("No speech detected")
            } else {
                transcribeStates[id] = .done(segments)
                saveMetadata(for: recording, segments: segments)
            }
        } catch is CancellationError {
            transcribeStates[id] = .error("Cancelled")
        } catch {
            transcribeStates[id] = .error(error.localizedDescription)
        }
    }

    func cancelTranscribe(for recording: Recording) {
        transcription.cancel()
        transcribeStates[recording.id] = .error("Cancelled")
    }

    func clearTranscript(for recording: Recording) {
        transcribeStates.removeValue(forKey: recording.id)
        summaryStates.removeValue(forKey: recording.id)
        translationStates.removeValue(forKey: recording.id)
        translationStateObjects.removeValue(forKey: recording.id)
    }

    func moveRecording(id: UUID, to folder: RecordingFolder?) {
        guard let context = modelContext,
              let recording = recordings.first(where: { $0.id == id })
        else { return }

        let metadata = fetchOrCreateMetadata(for: recording, context: context)
        metadata.folder = folder
        try? context.save()
    }

    // MARK: - Summarization
    func summarize(_ recording: Recording, language: LocalLLMService.SummaryLanguage) async {
        guard case .done(let segments) = transcribeStates[recording.id] else { return }
        let fullText = segments.map(\.text).joined(separator: " ")

        summaryStates[recording.id] = .running("")
        do {
            if !llm.isLoaded {
                let id = recording.id
                let statusTask = Task { [weak self] in
                    while !(self?.llm.isLoaded ?? true) {
                        self?.summaryStates[id] = .running(self?.llm.loadStatus ?? "")
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                try await llm.load()
                statusTask.cancel()
                summaryStates[id] = .running("")
            }

            var output = ""
            try await llm.summarize(text: fullText, language: language) { fullDecoded in
                output = fullDecoded
                Task { @MainActor in self.summaryStates[recording.id] = .running(fullDecoded) }
            }
            summaryStates[recording.id] = .done(output)
            saveSummary(output, for: recording)
        } catch {
            summaryStates[recording.id] = .error(error.localizedDescription)
        }
    }

    func clearSummary(for recording: Recording) {
        summaryStates.removeValue(forKey: recording.id)
    }

    // MARK: - Translation
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
                status = .supported
            }

            switch status {
            case .installed, .supported:
                self.pendingTranslationTexts[id] = segments
                self.translationStates[id] = .running("Translating…")

                let state = self.translationState(for: id)
                state.config = nil
                try? await Task.sleep(for: .milliseconds(100))
                state.config = TranslationSession.Configuration(
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
        translationStateObjects.removeValue(forKey: recording.id)
        pendingTranslationTexts.removeValue(forKey: recording.id)
    }

    // MARK: - SwiftData persistence

    func saveMetadata(for recording: Recording, segments: [TranscriptSegment]) {
        guard let context = modelContext else { return }
        let filename = recording.filename
        let existing = fetchMetadata(filename: filename, context: context)
        let metadata = existing ?? RecordingMetadata(filename: filename, displayName: recording.formattedDate)
        metadata.transcriptSegments = segments
        metadata.detectedLanguage = segments.first?.detectedLanguage
        if existing == nil { context.insert(metadata) }
        try? context.save()
    }

    func saveSummary(_ summary: String, for recording: Recording) {
        guard let context = modelContext else { return }
        let metadata = fetchOrCreateMetadata(for: recording, context: context)
        metadata.summaryText = summary
        try? context.save()
    }

    func saveTranslation(_ text: String, languageCode: String, for recording: Recording) {
        guard let context = modelContext else { return }
        let metadata = fetchOrCreateMetadata(for: recording, context: context)
        metadata.setTranslation(text, for: languageCode)
        try? context.save()
    }

    func loadMetadata(for recording: Recording) -> RecordingMetadata? {
        guard let context = modelContext else { return nil }
        return fetchMetadata(filename: recording.filename, context: context)
    }

    private func fetchMetadata(filename: String, context: ModelContext) -> RecordingMetadata? {
        let descriptor = FetchDescriptor<RecordingMetadata>(
            predicate: #Predicate { $0.filename == filename }
        )
        return try? context.fetch(descriptor).first
    }

    private func fetchOrCreateMetadata(for recording: Recording, context: ModelContext) -> RecordingMetadata {
        if let existing = fetchMetadata(filename: recording.filename, context: context) {
            return existing
        }
        let new = RecordingMetadata(filename: recording.filename, displayName: recording.formattedDate)
        context.insert(new)
        return new
    }

    // MARK: - Helpers

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

    func loadSavedTranscript(for recording: Recording) {
        guard let metadata = loadMetadata(for: recording),
              !metadata.transcriptSegments.isEmpty else { return }
        transcribeStates[recording.id] = .done(metadata.transcriptSegments)
        if let summary = metadata.summaryText {
            summaryStates[recording.id] = .done(summary)
        }
        if !metadata.translations.isEmpty {
            if let (_, text) = metadata.translations.first {
                translationStates[recording.id] = .done(text)
            }
        }
    }

    func hasSavedTranscript(for recording: Recording) -> Bool {
        guard let metadata = loadMetadata(for: recording) else { return false }
        return !metadata.transcriptSegments.isEmpty
    }

    func translationState(for id: UUID) -> TranslationState {
        if let existing = translationStateObjects[id] { return existing }
        let new = TranslationState()
        translationStateObjects[id] = new
        return new
    }

    func resetAll() {
        player.stop()
        transcribeStates.removeAll()
        summaryStates.removeAll()
        translationStates.removeAll()
        translationStateObjects.removeAll()
        pendingTranslationTexts.removeAll()
        currentFolder = nil
        folders = []
        allMetadata = []
        recordings = []
        appState = .ready
        elapsedSeconds = 0
        recordingTimer?.invalidate()
        recordingTimer = nil
    }
}
