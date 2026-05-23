import WhisperKit
import Foundation

/// Wraps WhisperKit for audio-file transcription.
/// Model selection adapts to available device RAM.
class TranscriptionService {

    private var pipe: WhisperKit?

    // MARK: - Setup
    func load(onProgress: @escaping (String) -> Void) async throws {
        let model = selectModel()
        onProgress("Loading \(model)…")
        pipe = try await WhisperKit(model: model)
        onProgress("Model ready")
    }

    // MARK: - Transcription
    func transcribe(
        audioURL: URL,
        onProgress: @escaping (String) -> Void
    ) async throws -> [TranscriptSegment] {
        guard let pipe else { throw TranscriptionError.notLoaded }

        onProgress("Transcribing…")

        let options = DecodingOptions(wordTimestamps: true)

        let results = try await pipe.transcribe(
            audioPath: audioURL.path,
            decodeOptions: options
        )

        onProgress("Done")

        let detectedLanguage = results.first?.language

        // WhisperKit splits long audio into chunks.
        // Each chunk's segments have timestamps relative to that chunk,
        // so we accumulate the chunk offset to get absolute timestamps.
        var segments: [TranscriptSegment] = []
        var timeOffset: TimeInterval = 0

        for result in results {
            let chunkSegments = result.segments.compactMap { seg -> TranscriptSegment? in
                let cleaned = seg.text
                    .replacingOccurrences(
                        of: #"<\|[^|]+\|>"#,
                        with: "",
                        options: .regularExpression
                    )
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

            // Advance offset by the duration of this chunk
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
        if ramGB >= 6 {
            return "openai_whisper-medium"
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
