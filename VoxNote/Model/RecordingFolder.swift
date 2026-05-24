import Foundation
import SwiftData

@Model
class RecordingFolder {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \RecordingMetadata.folder)
    var recordings: [RecordingMetadata]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.recordings = []
    }
}
