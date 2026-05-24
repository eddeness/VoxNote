import WhisperKit
import AVFoundation
import Foundation

/// Wraps WhisperKit for audio-file transcription.
/// Only one transcription task runs at a time — starting a new one cancels the previous.
class TranscriptionService {

    private var pipe: WhisperKit?
    private var currentTask: Task<[TranscriptSegment], Error>?

    // MARK: - Setup

    func load(onProgress: @escaping (String) -> Void) async throws {
        let model = selectModel()
        onProgress("Loading model…")

        pipe = try await WhisperKit(
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

        onProgress("Model ready")
    }

    // MARK: - Transcription

    func transcribe(
        audioURL: URL,
        onProgress: @escaping (String) -> Void
    ) async throws -> [TranscriptSegment] {
        // Cancel any existing transcription
        currentTask?.cancel()

        let task = Task {
            try await self.run(audioURL: audioURL, onProgress: onProgress)
        }
        currentTask = task

        defer { currentTask = nil }
        return try await task.value
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Internal

    private func run(
        audioURL: URL,
        onProgress: @escaping (String) -> Void
    ) async throws -> [TranscriptSegment] {
        guard let pipe else { throw TranscriptionError.notLoaded }

        onProgress("Transcribing… 0%")

        let asset = AVURLAsset(url: audioURL)
        let totalDuration = CMTimeGetSeconds(asset.duration)
        let options = DecodingOptions(wordTimestamps: true)

        // Local flag — Task.isCancelled doesn't propagate into sync WhisperKit callback
        var cancelled = false

        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        ) { progress in
            // Sync check of Task cancellation via local flag
            if Task.isCancelled { cancelled = true }
            if cancelled { return false }

            if totalDuration > 0 {
                let estimatedSeconds = Double(progress.windowId) * 30.0
                let pct = min(Int((estimatedSeconds / totalDuration) * 100), 99)
                Task { @MainActor in onProgress("Transcribing… \(pct)%") }
            }
            return true
        }

        if cancelled { throw CancellationError() }
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
        return ramGB >= 6
            ? "openai_whisper-medium"
            : "openai_whisper-base"
#endif
    }
}

enum TranscriptionError: LocalizedError {
    case notLoaded
    var errorDescription: String? { "WhisperKit model is not loaded yet." }
}
