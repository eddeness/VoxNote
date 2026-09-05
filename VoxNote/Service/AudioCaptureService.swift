@preconcurrency import AVFoundation
import Observation

enum RecordingError: LocalizedError {
    case permissionDenied
    var errorDescription: String? { "Microphone access is required to record audio." }
    var recoverySuggestion: String? {
#if os(macOS)
        "Please enable microphone access in System Settings → Privacy & Security → Microphone."
#else
        "Please enable microphone access in Settings → VoxNoteAI → Microphone."
#endif
    }
}

/// Handles microphone recording via AVAudioEngine.
/// Saves recordings permanently to the app's Documents/Recordings directory.
/// Platform differences (AVAudioSession) are isolated here.
@Observable
@MainActor
class AudioCaptureService {

    // State
    private(set) var recordingURL: URL?

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?

    // Max recording duration: 3 hours
    private let maxRecordingDuration: TimeInterval = 3 * 60 * 60

    // Called when max duration is reached — ViewModel listens to this
    var onMaxDurationReached: (() -> Void)?

    // MARK: - Recordings directory
    static var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Public API
    func startRecording() async throws {
        try await requestPermission()
        try configureAudioSession()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let recordFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )!

        let filename = "rec_\(Int(Date().timeIntervalSince1970)).wav"
        let url = Self.recordingsDirectory.appendingPathComponent(filename)
        recordingURL = url
        let file = try AVAudioFile(forWriting: url, settings: recordFormat.settings)
        audioFile = file

        let converter = AVAudioConverter(from: inputFormat, to: recordFormat)!

        recordingStartTime = Date()

        // The tap block runs on a realtime audio thread, NOT the main actor, so it
        // must never touch @MainActor-isolated state on `self` synchronously —
        // Swift 6's runtime isolation checks would run dispatch_assert_queue(main)
        // on the audio thread and crash (_dispatch_assert_queue_fail). Capture
        // everything the block needs as locals, and hop to the main actor only for
        // the rare max-duration stop.
        let startTime = Date()
        let maxDuration = maxRecordingDuration
        let onMaxReached: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                _ = self.stopRecording()
                self.onMaxDurationReached?()
            }
        }

        // @Sendable makes this closure non-isolated. Without it, the project's
        // SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor infers the tap block as
        // @MainActor, and CoreAudio invoking it on the realtime audio thread trips
        // Swift's executor check (dispatch_assert_queue(main)) → crash.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { @Sendable buffer, _ in
            // Check max duration
            if Date().timeIntervalSince(startTime) >= maxDuration {
                onMaxReached()
                return
            }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * recordFormat.sampleRate / inputFormat.sampleRate
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: recordFormat,
                frameCapacity: frameCapacity
            ) else { return }

            converter.convert(to: convertedBuffer, error: nil) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            try? file.write(from: convertedBuffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        recordingStartTime = nil
        deactivateAudioSession()
        return recordingURL
    }

    private func requestPermission() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted { throw RecordingError.permissionDenied }
        case .denied, .restricted:
            throw RecordingError.permissionDenied
        @unknown default:
            throw RecordingError.permissionDenied
        }
    }

    // MARK: - Saved recordings

    static func loadSavedRecordings() -> [Recording] {
        let dir = recordingsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { $0.pathExtension == "wav" }
            .compactMap { url -> Recording? in
                let attrs = try? url.resourceValues(forKeys: [.creationDateKey])
                let created = attrs?.creationDate ?? Date()
                let duration = Self.audioDuration(of: url)
                let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) ?? UUID()
                return Recording(id: id, url: url, createdAt: created, duration: duration)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func delete(_ recording: Recording) throws {
        try FileManager.default.removeItem(at: recording.url)
    }

    // MARK: - Private helpers

    private static func audioDuration(of url: URL) -> TimeInterval {
        // Recordings are always local WAV files we wrote ourselves, so reading
        // the frame count is exact and — unlike AVAsset.duration — synchronous
        // and not deprecated on the current deployment target.
        guard let file = try? AVAudioFile(forReading: url) else { return 0 }
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return 0 }
        return Double(file.length) / sampleRate
    }

    private func configureAudioSession() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .record,
            mode: .default,
            options: []
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }

    private func deactivateAudioSession() {
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}
