import Foundation

struct RecordingItem: Identifiable, Equatable {
    let recording: Recording
    let displayName: String
    let folder: RecordingFolder?

    var id: UUID { recording.id }

    static func == (lhs: RecordingItem, rhs: RecordingItem) -> Bool {
        lhs.recording.id == rhs.recording.id &&
        lhs.displayName == rhs.displayName &&
        lhs.folder?.id == rhs.folder?.id
    }
}
