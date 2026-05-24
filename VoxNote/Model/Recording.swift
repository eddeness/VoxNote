import Foundation

struct Recording: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let createdAt: Date
    let duration: TimeInterval

    var filename: String { url.lastPathComponent }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: createdAt)
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
