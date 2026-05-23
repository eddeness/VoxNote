import SwiftUI

/// Platform-aware export button for SRT and TXT.
/// macOS: NSSavePanel  |  iOS/iPadOS: ShareSheet via ShareLink
struct ExportButton: View {
    let segments: [TranscriptSegment]
    let exportService: ExportService
    @State private var srtURL: URL?
    @State private var txtURL: URL?

    var body: some View {
        Menu {
            exportAction(label: "Export SRT", systemImage: "captions.bubble", ext: "srt") {
                exportService.makeSRT(from: segments)
            }
            exportAction(label: "Export TXT", systemImage: "doc.text", ext: "txt") {
                exportService.makeTXT(from: segments)
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .disabled(segments.isEmpty)
#if os(iOS)
        // iOS: Use ShareLink driven by temp file URLs
        .background {
            if let url = srtURL {
                ShareLink(item: url) { EmptyView() }
            }
            if let url = txtURL {
                ShareLink(item: url) { EmptyView() }
            }
        }
#endif
    }

    @ViewBuilder
    private func exportAction(
        label: String,
        systemImage: String,
        ext: String,
        content: @escaping () -> String
    ) -> some View {
        Button {
            let text = content()
            let filename = "transcript.\(ext)"
#if os(macOS)
            exportService.saveWithPanel(content: text, suggestedFilename: filename)
#else
            if let url = try? exportService.writeTempFile(content: text, filename: filename) {
                if ext == "srt" { srtURL = url } else { txtURL = url }
            }
#endif
        } label: {
            Label(label, systemImage: systemImage)
        }
    }
}
