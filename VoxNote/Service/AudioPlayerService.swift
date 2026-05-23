import AVFoundation
import Observation

/// Manages playback of a single audio file at a time.
@Observable
@MainActor
class AudioPlayerService: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playingID: UUID?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?

    // MARK: - Playback control
    func play(recording: Recording) {
        if playingID == recording.id && isPlaying {
            pause()
            return
        }

        stop()

        do {
            try configureAudioSession()
            let p = try AVAudioPlayer(contentsOf: recording.url)
            p.delegate = self
            p.prepareToPlay()
            p.play()

            player = p
            playingID = recording.id
            duration = p.duration
            isPlaying = true

            startProgressTimer()
        } catch {
            print("Playback error: \(error)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopProgressTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        playingID = nil
        currentTime = 0
        duration = 0
        stopProgressTimer()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = 0
            self.playingID = nil
            self.stopProgressTimer()
        }
    }

    // MARK: - Progress timer
    private func startProgressTimer() {
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = self?.player?.currentTime ?? 0
            }
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Helpers

    var formattedCurrentTime: String { format(currentTime) }
    var formattedDuration: String { format(duration) }

    private func format(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Audio session
    private func configureAudioSession() throws {
#if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
#endif
    }
}
