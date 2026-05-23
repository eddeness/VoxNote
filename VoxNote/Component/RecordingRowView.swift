import SwiftUI
import Translation

struct RecordingRowView: View {

    let recording: Recording
    var player: AudioPlayerService
    var vm: MainViewModel
    let onDelete: () -> Void

    @State private var selectedSummaryLanguage = LocalLLMService.summaryLanguages[0]
    @State private var selectedTranslationLanguage = TranslationLanguage.supported[1]
    @State private var showDeleteConfirm = false

    private var isThisPlaying: Bool { player.playingID == recording.id && player.isPlaying }
    private var isThisLoaded: Bool { player.playingID == recording.id }
    private var transcribeState: TranscribeState? { vm.transcribeStates[recording.id] }
    private var summaryState: LLMTaskState? { vm.summaryStates[recording.id] }
    private var translationState: LLMTaskState? { vm.translationStates[recording.id] }
    private var translationConfig: TranslationSession.Configuration? { vm.translationConfigs[recording.id] }
    private var hasTranscript: Bool {
        if case .done = transcribeState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top row
            HStack(spacing: 12) {
                Button {
                    player.play(recording: recording)
                } label: {
                    Image(systemName: isThisPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(isThisPlaying ? .red : .accentColor)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recording.formattedDate)
                        .font(.subheadline.weight(.medium))
                    Text(isThisLoaded
                         ? player.formattedCurrentTime + " / " + recording.formattedDuration
                         : recording.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Spacer()
                transcribeButton

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete this recording?", isPresented: $showDeleteConfirm) {
                    Button("Delete", role: .destructive) { onDelete() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This action cannot be undone.")
                }
            }

            // Scrubber
            if isThisLoaded {
                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 0.01)
                )
                .tint(.accentColor)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Transcript
            if let state = transcribeState {
                Divider()
                transcriptSection(state)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Summary + Translation actions
            if hasTranscript {
                Divider()
                llmActionsSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .animation(.spring(duration: 0.25), value: isThisLoaded)
        .animation(.spring(duration: 0.3), value: hasTranscript)
        .animation(.spring(duration: 0.3), value: summaryState != nil)
        .animation(.spring(duration: 0.3), value: translationState != nil)
        .translationTask(translationConfig) { session in
            do {
                try await vm.performTranslation(for: recording.id, using: session)
            } catch {
                await MainActor.run {
                    vm.translationStates[recording.id] = .error("Translation unavailable. Please allow language download and try again.")
                    vm.translationConfigs.removeValue(forKey: recording.id)
                }
            }
        }
    }

    // MARK: - Transcribe button

    @ViewBuilder
    private var transcribeButton: some View {
        switch transcribeState {
        case .none:
            actionChip(label: "Transcribe", icon: "text.bubble", color: .accentColor) {
                Task { await vm.transcribe(recording) }
            }
        case .transcribing:
            loadingChip("Transcribing…")
        case .done:
            actionChip(label: "Clear", icon: "xmark.circle", color: .secondary) {
                vm.clearTranscript(for: recording)
            }
        case .error:
            actionChip(label: "Retry", icon: "arrow.clockwise", color: .orange) {
                Task { await vm.transcribe(recording) }
            }
        }
    }

    // MARK: - Transcript section

    @ViewBuilder
    private func transcriptSection(_ state: TranscribeState) -> some View {
        switch state {
        case .transcribing:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("Transcribing…").font(.caption).foregroundStyle(.secondary)
            }
        case .done(let segments):
            ScrollView {
                   VStack(alignment: .leading, spacing: 6) {
                       ForEach(segments) { seg in
                           VStack(alignment: .leading, spacing: 2) {
                               Text("\(seg.srtStartTime) → \(seg.srtEndTime)")
                                   .font(.caption.monospacedDigit())
                                   .foregroundStyle(.secondary)
                               Text(seg.text)
                                   .font(.body)
                           }
                       }
                   }
                   .textSelection(.enabled)
                   .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 600)
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red)
        }
    }

    // MARK: - LLM actions

    private var llmActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Summary
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Summary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedSummaryLanguage) {
                        ForEach(LocalLLMService.summaryLanguages) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption)

                    Spacer()

                    switch summaryState {
                    case .none:
                        actionChip(label: "Summarize", icon: "sparkles", color: .purple) {
                            Task { await vm.summarize(recording, language: selectedSummaryLanguage) }
                        }
                    case .running:
                        loadingChip("Summarizing…")
                    case .done:
                        actionChip(label: "Clear", icon: "xmark.circle", color: .secondary) {
                            vm.clearSummary(for: recording)
                        }
                    case .notDownloaded, .error:
                        actionChip(label: "Retry", icon: "arrow.clockwise", color: .orange) {
                            Task { await vm.summarize(recording, language: selectedSummaryLanguage) }
                        }
                    }
                }
                if let state = summaryState { llmResultView(state) }
            }

            Divider()

            // Translation
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Translation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedTranslationLanguage) {
                        ForEach(TranslationLanguage.supported) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.caption)

                    Spacer()

                    switch translationState {
                    case .none:
                        actionChip(label: "Translate", icon: "globe", color: .teal) {
                            let detectedLang = vm.detectedLanguage(for: recording)
                            vm.triggerTranslation(recording, from: detectedLang, to: selectedTranslationLanguage)
                        }
                    case .running:
                        loadingChip("Translating…")
                    case .done:
                        actionChip(label: "Clear", icon: "xmark.circle", color: .secondary) {
                            vm.clearTranslation(for: recording)
                        }
                    case .notDownloaded, .error:
                        actionChip(label: "Retry", icon: "arrow.clockwise", color: .orange) {
                            let detectedLang = vm.detectedLanguage(for: recording)
                            vm.triggerTranslation(recording, from: detectedLang, to: selectedTranslationLanguage)
                        }
                    }
                }
                if let state = translationState { translationResultView(state) }
            }
        }
    }

    // MARK: - Reusable views

    @ViewBuilder
    private func llmResultView(_ state: LLMTaskState) -> some View {
        switch state {
        case .running(let text):
            VStack(alignment: .leading, spacing: 4) {
                if text.isEmpty {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Starting…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text(text).font(.body).textSelection(.enabled)
                    ProgressView().scaleEffect(0.6).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .done(let text):
            Text(text).font(.body).textSelection(.enabled)
        case .notDownloaded:
            EmptyView()
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private func translationResultView(_ state: LLMTaskState) -> some View {
        switch state {
        case .running(let text):
            llmResultView(.running(text))
        case .done(let text):
            llmResultView(.done(text))
        case .notDownloaded:
            Button {
                let detectedLang = vm.detectedLanguage(for: recording)
                vm.triggerTranslation(recording, from: detectedLang, to: selectedTranslationLanguage)
            } label: {
                Label("Download Language Pack", systemImage: "arrow.down.circle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.teal.opacity(0.12), in: Capsule())
                    .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red)
        }
    }

    private func actionChip(label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
    }

    private func loadingChip(_ label: String) -> some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.65)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
