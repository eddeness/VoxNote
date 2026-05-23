import Foundation
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

/// Generates SRT / plain-text exports and triggers the OS save dialog.
class ExportService {
    // MARK: - Content generation
    func makeSRT(from segments: [TranscriptSegment]) -> String {
        segments.enumerated().map { index, seg in
            """
            \(index + 1)
            \(seg.srtStartTime) --> \(seg.srtEndTime)
            \(seg.text)
            """
        }.joined(separator: "\n\n")
    }

    func makeTXT(from segments: [TranscriptSegment]) -> String {
        segments.map(\.text).joined(separator: "\n\n")
    }

    // MARK: - Save helpers
    /// Writes content to a temp file and returns its URL.
    /// On macOS the caller should present NSSavePanel; on iOS use ShareSheet / ShareLink.
    func writeTempFile(content: String, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

#if os(macOS)
    /// Shows NSSavePanel and writes the file. Call from the main thread.
    @MainActor
    func saveWithPanel(content: String, suggestedFilename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.allowedContentTypes = suggestedFilename.hasSuffix(".srt")
            ? [.init(filenameExtension: "srt")!]
            : [.plainText]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
#endif
}
