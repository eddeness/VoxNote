import WhisperKit
import AVFoundation
import Foundation

/// Wraps WhisperKit for audio-file transcription.
/// Only one transcription task runs at a time — starting a new one cancels the previous.
@MainActor
class TranscriptionService {

    private var pipe: WhisperKit?
    private var currentTask: Task<[TranscriptSegment], Error>?
    private var setupTask: Task<Void, Error>?

    var loadedPipe: WhisperKit? { pipe }

    // MARK: - Setup
    func load(onProgress: @escaping (String) -> Void) async throws {
        setupTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            let model = self.selectModel()

            onProgress("Preparing model…")

            _ = try await WhisperKit.download(
                variant: model,
                progressCallback: { progress in
                    if Task.isCancelled { return }

                    let pct = Int(progress.fractionCompleted * 100)
                    if pct < 100 {
                        Task { @MainActor in onProgress("Downloading model… \(pct)%") }
                    }
                }
            )

            try Task.checkCancellation()

            onProgress("Loading model…")

            self.pipe = try await WhisperKit(
                WhisperKitConfig(
                    model: model,
                    downloadBase: nil,
                    modelRepo: "argmaxinc/whisperkit-coreml",
                    verbose: false,
                    logLevel: .none,
                    prewarm: false,
                    load: true,
                    download: true
                )
            )

            try Task.checkCancellation()
            onProgress("Model ready")
        }

        setupTask = task

        defer {
            if setupTask == task {
                setupTask = nil
            }
        }

        try await task.value
    }

    // MARK: - Transcription
    func transcribe(
        audioURL: URL,
        language: String? = nil,
        onProgress: @escaping (String) -> Void
    ) async throws -> [TranscriptSegment] {
        // Cancel any existing transcription
        currentTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.run(audioURL: audioURL, language: language, onProgress: onProgress)
        }
        currentTask = task

        defer {
            if currentTask == task {
                currentTask = nil
            }
        }

        return try await task.value
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil

        setupTask?.cancel()
        setupTask = nil
    }

    deinit {
        currentTask?.cancel()
        setupTask?.cancel()
    }

    // MARK: - Internal
    private func run(
        audioURL: URL,
        language: String? = nil,
        onProgress: @escaping (String) -> Void
    ) async throws -> [TranscriptSegment] {
        guard let pipe else { throw TranscriptionError.notLoaded }

        onProgress("Transcribing… 0%")

        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration)
        let totalDuration = CMTimeGetSeconds(duration)

        // task: .transcribe keeps the original language instead of translating to English.
        // language: nil lets WhisperKit auto-detect.
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            wordTimestamps: true
        )

        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        ) { progress in
            if Task.isCancelled { return false }

            if totalDuration > 0 {
                let estimatedSeconds = Double(progress.windowId) * 30.0
                let pct = min(Int((estimatedSeconds / totalDuration) * 100), 99)
                Task { @MainActor in onProgress("Transcribing… \(pct)%") }
            }
            return true
        }

        try Task.checkCancellation()

        let detectedLanguage = results.first?.language
        var segments: [TranscriptSegment] = []
        var timeOffset: TimeInterval = 0

        for result in results {
            let chunkSegments = result.segments.compactMap { seg -> TranscriptSegment? in
                let cleaned = seg.text
                    .replacingOccurrences(of: #"<\|[^|]+\|>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                guard !cleaned.isEmpty else { return nil }
                return TranscriptSegment(
                    startTime: TimeInterval(seg.start) + timeOffset,
                    endTime: TimeInterval(seg.end) + timeOffset,
                    text: cleaned,
                    detectedLanguage: detectedLanguage
                )
            }
            segments.append(contentsOf: chunkSegments)
            if let lastEnd = result.segments.last.map({ TimeInterval($0.end) }) {
                timeOffset += lastEnd
            }
        }

        return segments
    }

    // MARK: - Model selection
    private func selectModel() -> String {
        let ramGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
#if os(macOS)
        return ramGB >= 16
            ? "openai_whisper-large-v3"
            : "openai_whisper-medium"
#else
        if ramGB >= 8 {
            return "openai_whisper-medium"
        } else if ramGB >= 6 {
            return "openai_whisper-small"
        } else {
            return "openai_whisper-base"
        }
#endif
    }
}

enum TranscriptionError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "WhisperKit model is not loaded yet." }
}
