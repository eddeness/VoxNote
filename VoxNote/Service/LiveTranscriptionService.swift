import AVFoundation
import WhisperKit
import Foundation

/// Real-time transcription using mic input + WhisperKit on rolling buffer.
/// Pushes incremental text via onText callback.
@MainActor
class LiveTranscriptionService {

    private let engine = AVAudioEngine()
    private var pipe: WhisperKit?
    private var audioBuffer: [Float] = []
    private let processingQueue = DispatchQueue(label: "live.transcribe.queue")

    private var isRunning = false
    private var processingTask: Task<Void, Never>?
    private let sampleRate: Double = 16000
    private let chunkDuration: Double = 3.5 // process every 3.5 seconds

    private(set) var fullTranscript: String = ""

    // MARK: - Setup

    func loadModel(_ pipe: WhisperKit) {
        self.pipe = pipe
    }

    // MARK: - Public API

    func start(
        onText: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) throws {
        guard let pipe else { throw TranscriptionError.notLoaded }
        _ = pipe // silence warning

        guard !isRunning else { return }
        isRunning = true
        fullTranscript = ""
        audioBuffer = []

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        )!

        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
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
                self.audioBuffer.append(contentsOf: samples)
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
                await self.processChunk(onText: onText, onError: onError)
            }
        }
    }

    func stop() {
        isRunning = false
        processingTask?.cancel()
        processingTask = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioBuffer = []
    }

    // MARK: - Internal

    private func processChunk(
        onText: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void
    ) async {
        guard let pipe else { return }
        guard audioBuffer.count > Int(sampleRate * 1.0) else { return } // need at least 1 second

        let samples = audioBuffer
        audioBuffer = [] // clear after consume

        do {
            let options = DecodingOptions(wordTimestamps: false)
            let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)

            for result in results {
                let text = result.text
                    .replacingOccurrences(of: #"<\|[^|]+\|>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)

                if !text.isEmpty {
                    fullTranscript += (fullTranscript.isEmpty ? "" : " ") + text
                    onText(fullTranscript)
                }
            }
        } catch {
            onError(error)
        }
    }
}
