@preconcurrency import AVFoundation
import WhisperKit
import Foundation

/// Real-time transcription using mic input + WhisperKit on a growing window.
///
/// Audio is captured in short chunks and accumulated into an open window that
/// is re-transcribed every cycle — this gives WhisperKit full context for the
/// text currently being spoken, rather than transcribing isolated fragments.
///
/// The window is "confirmed" into a finished line once it has enough audio
/// AND ends at a sentence boundary (or hits a hard ceiling if the speaker
/// never pauses). Confirmed lines never change again, so they're safe to
/// translate — and because they're full sentences, translation quality is
/// dramatically better than translating mid-clause fragments.
@MainActor
class LiveTranscriptionService {

    private let engine = AVAudioEngine()
    private var pipe: WhisperKit?
    private var incomingBuffer: [Float] = []
    private let processingQueue = DispatchQueue(label: "live.transcribe.queue")

    private var isRunning = false
    private var processingTask: Task<Void, Never>?
    private let sampleRate: Double = 16000
    private let chunkDuration: Double = 3.5 // seconds per chunk

    /// How many chunks to accumulate before attempting to confirm a line.
    /// Larger batches give WhisperKit more context and produce fuller
    /// sentences, which translate far more naturally.
    private let minChunksToConfirm = 5      // ~17.5s before we try to confirm

    /// Hard ceiling — if the speaker never pauses at a sentence boundary we
    /// still confirm here so lines don't grow without bound.
    private let maxChunksBeforeForcedConfirm = 8  // ~28s

    /// Raw audio for each chunk still in the rolling window (oldest first).
    private var windowChunks: [[Float]] = []

    /// Lines already finalized (won't change again), oldest first.
    private(set) var confirmedLines: [String] = []

    /// The current best transcription of the still-open rolling window.
    private var currentLineText: String = ""

    private var language: String?

    // MARK: - Setup

    func loadModel(_ pipe: WhisperKit) {
        self.pipe = pipe
    }

    // MARK: - Public API

    func start(
        language: String? = nil,
        onText: @escaping @Sendable (String) -> Void,
        onNewConfirmedLine: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) throws {
        guard let pipe else { throw TranscriptionError.notLoaded }
        _ = pipe // silence warning

        guard !isRunning else { return }
        isRunning = true
        self.language = language
        confirmedLines = []
        currentLineText = ""
        windowChunks = []
        incomingBuffer = []

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!

        // @Sendable keeps this off the main actor — see AudioCaptureService for
        // why an actor-isolated tap block crashes on the realtime audio thread.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable [weak self] buffer, _ in
            guard let self else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * targetFormat.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCapacity
            ) else { return }

            var error: NSError?
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
            let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(convertedBuffer.frameLength)))

            Task { @MainActor in
                self.incomingBuffer.append(contentsOf: samples)
            }
        }

        engine.prepare()
        try engine.start()

        // Process audio chunks periodically
        processingTask = Task { [weak self] in
            guard let self else { return }
            while self.isRunning {
                try? await Task.sleep(for: .seconds(self.chunkDuration))
                guard self.isRunning else { break }
                await self.processChunk(onText: onText, onNewConfirmedLine: onNewConfirmedLine, onError: onError)
            }
        }
    }

    func stop() {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        incomingBuffer = []
        windowChunks = []
    }

    // MARK: - Internal

    private func processChunk(
        onText: @escaping @Sendable (String) -> Void,
        onNewConfirmedLine: @escaping @Sendable (String) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) async {
        guard let pipe else { return }
        guard incomingBuffer.count > Int(sampleRate * 1.0) else { return } // need at least 1 second

        // Move the newly captured audio into the rolling window as its own chunk.
        let newChunk = incomingBuffer
        incomingBuffer = []
        windowChunks.append(newChunk)

        do {
            let options = DecodingOptions(
                task: .transcribe,
                language: language,
                wordTimestamps: false
            )

            // Always re-transcribe the whole open window — this is both the
            // in-progress display text and the candidate for confirmation.
            let windowAudio = windowChunks.flatMap { $0 }
            guard !windowAudio.isEmpty else { return }

            let results = try await pipe.transcribe(audioArray: windowAudio, decodeOptions: options)
            let windowText = cleanText(results.map(\.text).joined(separator: " "))

            // Decide whether this window is ready to be locked in.
            // Prefer confirming at a sentence boundary so the translated text
            // reads naturally instead of being cut mid-clause.
            let hasEnoughAudio = windowChunks.count >= minChunksToConfirm
            let endsAtSentenceBoundary = endsWithSentencePunctuation(windowText)
            let hitHardCeiling = windowChunks.count >= maxChunksBeforeForcedConfirm

            if !windowText.isEmpty && ((hasEnoughAudio && endsAtSentenceBoundary) || hitHardCeiling) {
                confirmedLines.append(windowText)
                windowChunks.removeAll()
                currentLineText = ""
                // Notify the caller so it can start translating this line —
                // it will never be re-transcribed, so it's safe to translate.
                onNewConfirmedLine(windowText)
            } else {
                currentLineText = windowText
            }

            emitCombinedText(onText: onText)
        } catch {
            onError(error)
        }
    }

    private func endsWithSentencePunctuation(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".!?。！？".contains(last)
    }

    private func cleanText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"<\|[^|]+\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private func emitCombinedText(onText: @escaping (String) -> Void) {
        var lines = confirmedLines
        if !currentLineText.isEmpty {
            lines.append(currentLineText)
        }
        onText(lines.joined(separator: "\n"))
    }
}
