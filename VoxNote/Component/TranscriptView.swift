import SwiftUI

struct TranscriptView: View {

    let segments: [TranscriptSegment]

    var body: some View {
        if segments.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(segments) { seg in
                            SegmentRow(segment: seg)
                                .id(seg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: segments.count) { _, _ in
                    if let last = segments.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Transcript will appear here")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Segment row

private struct SegmentRow: View {

    let segment: TranscriptSegment
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timecode badge
            Text("\(segment.srtStartTime) → \(segment.srtEndTime)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            // Transcript text
            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            // Copy button
            Button {
                copyText()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(copied ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
    }

    private func copyText() {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(segment.text, forType: .string)
#else
        UIPasteboard.general.string = segment.text
#endif
        withAnimation { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { withAnimation { copied = false } }
        }
    }
}
