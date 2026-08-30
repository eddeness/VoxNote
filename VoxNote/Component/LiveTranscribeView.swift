import SwiftUI
import Translation

/// Holds per-line translation state. Using a reference type (like the main
/// app's TranslationState) means each line's .translationTask is bound to
/// its own object identity, so SwiftUI never confuses one line's config
/// change with another's — each line translates independently instead of
/// sharing one global config that has to be nil'd/reset between lines.
@Observable
private class LiveLineTranslation {
    var config: TranslationSession.Configuration?
}

private struct LiveLine: Identifiable {
    let id = UUID()
    let original: String
    var translated: String?
    let translationState = LiveLineTranslation()
}

struct LiveTranscribeView: View {
    @Bindable var vm: MainViewModel

    // iOS dismisses via this; macOS ignores it (window close).
    var onClose: (() -> Void)? = nil

    @State private var confirmedItems: [LiveLine] = []
    @State private var currentLineText: String = ""
    @State private var errorMessage: String?

    @State private var showTranscribeLanguagePicker = false
    @State private var showTranslateLanguagePicker = false
    @State private var transcribeLanguageCode = "en"
    @State private var translationEnabled = false
    @State private var selectedTranslationLanguage = TranslationLanguage.supported[1]

    private let liveService = LiveTranscriptionService()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            // Transcript area
            ScrollView {
                if confirmedItems.isEmpty && currentLineText.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(vm.isRecording ? "Listening…" : "Start recording to begin")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(confirmedItems) { item in
                            LiveLineRow(
                                item: item,
                                translationEnabled: translationEnabled,
                                targetLanguage: selectedTranslationLanguage,
                                onTranslated: { text in
                                    updateTranslation(for: item.id, text: text)
                                }
                            )
                        }

                        if !currentLineText.isEmpty {
                            Text(currentLineText)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }

            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
        }
#if os(macOS)
        .frame(minWidth: 480, minHeight: 400)
#endif
        .onChange(of: vm.isRecording) {
            if vm.isRecording {
                start()
            } else {
                stop()
            }
        }
        .onAppear {
            if vm.isRecording { start() }
        }
        .onDisappear {
            stop()
        }
        .sheet(isPresented: $showTranscribeLanguagePicker) {
            LanguagePickerSheet(
                selectedCode: $transcribeLanguageCode,
                onDismiss: {
                    showTranscribeLanguagePicker = false
                    // Restart live transcription with the new language.
                    if vm.isRecording {
                        stop()
                        start()
                    }
                }
            )
        }
        .sheet(isPresented: $showTranslateLanguagePicker) {
            TranslateLanguagePickerSheet(
                selectedLanguage: $selectedTranslationLanguage,
                translationEnabled: $translationEnabled,
                onDismiss: { showTranslateLanguagePicker = false }
            )
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.isRecording ? .red : .secondary)
                    .frame(width: 8, height: 8)
                Text(vm.isRecording ? "Live" : "Stopped")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Transcribe language chip
            Button {
                showTranscribeLanguagePicker = true
            } label: {
                Text(TranscribeLanguage.from(code: transcribeLanguageCode).label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.tertiary, in: Capsule())
            }
            .buttonStyle(.plain)

            // Translate language chip
            Button {
                showTranslateLanguagePicker = true
            } label: {
                Label(
                    translationEnabled ? selectedTranslationLanguage.label : "Translate",
                    systemImage: "globe"
                )
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(translationEnabled ? Color.teal.opacity(0.15) : Color(.tertiarySystemFill).opacity(0.3), in: Capsule())
                .foregroundStyle(translationEnabled ? .teal : .primary)
            }
            .buttonStyle(.plain)

            ShareLink(item: shareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(confirmedItems.isEmpty && currentLineText.isEmpty)

#if os(iOS)
            Button {
                onClose?()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
#endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var shareText: String {
        var lines = confirmedItems.map { item -> String in
            if translationEnabled, let translated = item.translated {
                return "\(item.original)\n\(translated)"
            }
            return item.original
        }
        if !currentLineText.isEmpty { lines.append(currentLineText) }
        return lines.joined(separator: "\n\n")
    }

    private func updateTranslation(for id: UUID, text: String) {
        if let index = confirmedItems.firstIndex(where: { $0.id == id }) {
            confirmedItems[index].translated = text
        }
    }

    private func start() {
        errorMessage = nil
        Task {
            if !vm.isWhisperLoaded {
                await vm.loadWhisperModel()
            }
            guard let pipe = vm.whisperPipe else {
                errorMessage = "Failed to load model."
                return
            }
            liveService.loadModel(pipe)

            do {
                try liveService.start(
                    language: transcribeLanguageCode,
                    onText: { fullText in
                        Task { @MainActor in
                            // Last line in the joined text is the in-progress one;
                            // everything else is already reflected in confirmedItems.
                            let parts = fullText.split(separator: "\n", omittingEmptySubsequences: false)
                            currentLineText = parts.last.map(String.init) ?? ""
                        }
                    },
                    onNewConfirmedLine: { line in
                        Task { @MainActor in
                            let newLine = LiveLine(original: line)
                            confirmedItems.append(newLine)
                            if translationEnabled {
                                newLine.translationState.config = TranslationSession.Configuration(
                                    source: nil,
                                    target: selectedTranslationLanguage.locale
                                )
                            }
                        }
                    },
                    onError: { error in
                        Task { @MainActor in errorMessage = error.localizedDescription }
                    }
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stop() {
        liveService.stop()
    }
}

// MARK: - Per-line row with its own independent .translationTask

private struct LiveLineRow: View {
    let item: LiveLine
    let translationEnabled: Bool
    let targetLanguage: TranslationLanguage
    let onTranslated: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.original)
                .font(.body)
            if translationEnabled {
                if let translated = item.translated {
                    Text(translated)
                        .font(.body)
                        .foregroundStyle(.teal)
                } else {
                    HStack(spacing: 4) {
                        ProgressView().scaleEffect(0.6)
                        Text("Translating…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .translationTask(item.translationState.config) { session in
            do {
                let response = try await session.translate(item.original)
                await MainActor.run {
                    onTranslated(response.targetText)
                }
            } catch {
                // Leave as "Translating…" on failure rather than showing
                // a broken line; the user can retry by toggling translation.
            }
        }
    }
}

// MARK: - Translate language picker (adds an enable/disable toggle)

private struct TranslateLanguagePickerSheet: View {
    @Binding var selectedLanguage: TranslationLanguage
    @Binding var translationEnabled: Bool
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Live Translation")
                    .font(.headline)
                Spacer()
                Button("Done") { onDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)

            Divider()

            Toggle("Translate live transcript", isOn: $translationEnabled)
                .padding(16)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(TranslationLanguage.supported) { lang in
                        languageRow(lang)
                        Divider()
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.visible)
            .disabled(!translationEnabled)
            .opacity(translationEnabled ? 1 : 0.4)
        }
#if os(macOS)
        .frame(width: 360, height: 480)
#else
        .presentationDetents([.medium, .large])
#endif
    }

    private func languageRow(_ lang: TranslationLanguage) -> some View {
        Button {
            selectedLanguage = lang
        } label: {
            HStack {
                Text(lang.label)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedLanguage.id == lang.id {
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
