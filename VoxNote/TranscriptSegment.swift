import Foundation

struct TranscriptSegment: Identifiable, Equatable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    var translatedText: String? = nil
    var detectedLanguage: String? = nil  // BCP-47, e.g. "en", "ko"

    var srtStartTime: String { formatSRT(startTime) }
    var srtEndTime: String { formatSRT(endTime) }

    private func formatSRT(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }
}
