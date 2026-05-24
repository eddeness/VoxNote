import Foundation
import SwiftData

@Model
class RecordingMetadata {
    var id: UUID
    var filename: String          // Maps to actual .wav file in Documents/Recordings/
    var displayName: String       // User-editable name
    var createdAt: Date
    var detectedLanguage: String?

    // Results — stored as JSON strings
    var transcriptJSON: String?
    var summaryText: String?
    var translationJSON: String?  // Encoded as [languageCode: translatedText]

    // Folder relationship — nil means root
    var folder: RecordingFolder?

    init(filename: String, displayName: String) {
        self.id = UUID()
        self.filename = filename
        self.displayName = displayName
        self.createdAt = Date()
    }

    // MARK: - Transcript helpers
    var transcriptSegments: [TranscriptSegment] {
        get {
            guard let json = transcriptJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([CodableSegment].self, from: data)
            else { return [] }
            return decoded.map(\.segment)
        }
        set {
            let codable = newValue.map(CodableSegment.init)
            transcriptJSON = (try? JSONEncoder().encode(codable))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    // MARK: - Translation helpers

    var translations: [String: String] {
        get {
            guard let json = translationJSON,
                  let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            translationJSON = (try? JSONEncoder().encode(newValue))
                .flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    func translation(for languageCode: String) -> String? {
        translations[languageCode]
    }

    func setTranslation(_ text: String, for languageCode: String) {
        var current = translations
        current[languageCode] = text
        translations = current
    }
}

// MARK: - Codable wrapper for TranscriptSegment

struct CodableSegment: Codable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let text: String
    let detectedLanguage: String?

    init(_ segment: TranscriptSegment) {
        self.startTime = segment.startTime
        self.endTime = segment.endTime
        self.text = segment.text
        self.detectedLanguage = segment.detectedLanguage
    }

    var segment: TranscriptSegment {
        TranscriptSegment(
            startTime: startTime,
            endTime: endTime,
            text: text,
            detectedLanguage: detectedLanguage
        )
    }
}
