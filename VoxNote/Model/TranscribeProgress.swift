import Foundation

/// Structured progress for model loading + transcription.
///
/// UI keys off `phase`/`percent` (e.g. whether to show a Cancel button or a
/// determinate progress bar) instead of sniffing the display text — which is
/// localized and therefore not safe to pattern-match on.
struct TranscribeProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case preparing
        case downloading
        case loadingModel
        case transcribing
    }

    var phase: Phase
    var percent: Int?   // 0...100 when known

    /// Localized text for display only.
    var message: String {
        switch phase {
        case .preparing:
            return String(localized: "Preparing model…")
        case .downloading:
            if let percent {
                return String(format: String(localized: "Downloading model… %d%%"), percent)
            }
            return String(localized: "Downloading model…")
        case .loadingModel:
            return String(localized: "Loading model…")
        case .transcribing:
            return String(format: String(localized: "Transcribing… %d%%"), percent ?? 0)
        }
    }

    /// Cancel is only meaningful while the file is still downloading (and not
    /// almost done) — once model loading / CoreML compilation starts, the work
    /// already in progress can't reliably be stopped.
    var isCancellable: Bool {
        switch phase {
        case .downloading:
            return (percent ?? 0) < 90
        case .transcribing:
            return true
        case .preparing, .loadingModel:
            return false
        }
    }
}
