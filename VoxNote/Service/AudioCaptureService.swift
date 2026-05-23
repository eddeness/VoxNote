import AVFoundation
import Observation

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
        let format = inputNode.outputFormat(forBus: 0)

        let filename = "rec_\(Int(Date().timeIntervalSince1970)).wav"
        let url = Self.recordingsDirectory.appendingPathComponent(filename)
        recordingURL = url
        audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            try? self?.audioFile?.write(from: buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stopRecording() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        deactivateAudioSession()
        return recordingURL
    }
    
    
    private func requestPermission() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted {
            throw RecordingError.permissionDenied
        }
    }

    
    enum RecordingError: LocalizedError {
        case permissionDenied
        var errorDescription: String? {
            "You do not have microphone access. Please allow it in System Settings > Privacy > Microphone."
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
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        return seconds.isNaN ? 0 : seconds
    }

    private func configureAudioSession() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
#endif
    }

    private func deactivateAudioSession() {
#if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
#endif
    }
}
