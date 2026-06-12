import SwiftUI

struct LanguagePickerSheet: View {
    @Binding var selectedCode: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transcribe Language")
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(TranscribeLanguage.supported) { lang in
                        languageRow(lang)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
        }
#if os(macOS)
        .frame(width: 360, height: 480)
#else
        .presentationDetents([.medium, .large])
#endif
    }

    private func languageRow(_ lang: TranscribeLanguage) -> some View {
        Button {
            selectedCode = lang.code
            onDismiss()
        } label: {
            HStack {
                Text(lang.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedCode == lang.code {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
