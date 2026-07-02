import SwiftUI
import Translation

struct RecordingRowView: View {

    let item: RecordingItem
    var player: AudioPlayerService
    var vm: MainViewModel
    let onDelete: () -> Void

    @State private var selectedSummaryLanguage = LocalLLMService.summaryLanguages[0]
    @State private var selectedTranslationLanguage = TranslationLanguage.supported[1]

    @State private var isTranscriptExpanded = true
    @State private var isSummaryExpanded = true
    @State private var isTranslationExpanded = true
    @State private var showDeleteConfirm = false
    @State private var showRenameSheet = false

    private var recording: Recording { item.recording }

    private var isThisPlaying: Bool { player.playingID == recording.id && player.isPlaying }
    private var isThisLoaded: Bool { player.playingID == recording.id }
    private var transcribeState: TranscribeState? { vm.transcribeStates[recording.id] }
    private var summaryState: LLMTaskState? { vm.summaryStates[recording.id] }
    private var translationState: LLMTaskState? { vm.translationStates[recording.id] }
    private var hasTranscript: Bool {
        if case .done = transcribeState { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    Text(item.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(isThisLoaded
                         ? player.formattedCurrentTime + " / " + recording.formattedDuration
                         : recording.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !recording.formattedFileSize.isEmpty {
                        Text(recording.formattedFileSize)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
                transcribeButton

                if case .transcribing = transcribeState {

                } else {
                    Button {
                        showRenameSheet = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

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
            }

            if isThisLoaded {
                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 0.01)
                )
                .tint(.accentColor)
            }

            if let state = transcribeState {
                Divider()
                HStack(spacing: 8) {
                    Text("Transcript")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if case .done(let segments) = state {
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                isTranscriptExpanded.toggle()
                            }
                        } label: {
                            Image(systemName: isTranscriptExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        ShareLink(
                            item: segments.map { "[\($0.srtStartTime) → \($0.srtEndTime)]\n\($0.text)" }.joined(separator: "\n\n"),
                            subject: Text("Transcript"),
                            message: Text(item.displayName)
                        ) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isTranscriptExpanded {
                    transcriptSection(state)
                }
            }

            if hasTranscript {
                Divider()
                llmActionsSection
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .translationTask(vm.translationState(for: recording.id).config) { session in
            do {
                try await vm.performTranslation(for: recording.id, using: session)
            } catch {
                await MainActor.run {
                    vm.translationStates[recording.id] = .error("Translation unavailable. Please allow language download and try again.")
                    vm.translationState(for: recording.id).config = nil
                }
            }
        }
        .draggable(recording.id.uuidString)
        .sheet(isPresented: $showRenameSheet) {
            RenameSheet(
                title: "Rename Recording",
                initialName: item.displayName,
                onSave: { name in
                    _ = vm.renameRecording(recording, to: name)
                    showRenameSheet = false
                },
                onCancel: { showRenameSheet = false }
            )
        }
    }

    @ViewBuilder
    private var transcribeButton: some View {
        switch transcribeState {
        case .none:
            if vm.hasSavedTranscript(for: recording) {
                actionChip(label: "Load", icon: "arrow.down.circle", color: .green) {
                    vm.loadSavedTranscript(for: recording)
                }
            } else {
                actionChip(label: "Transcribe", icon: "text.bubble", color: .accentColor) {
                    Task { await vm.transcribe(recording) }
                }
                .disabled(vm.isTranscribing)
                .opacity(vm.isTranscribing ? 0.4 : 1)
            }
        case .transcribing(let msg):
            HStack(spacing: 6) {
                loadingChip(msg)
                if !msg.lowercased().hasPrefix("preparing"), !msg.lowercased().hasPrefix("loading") {
                    Button {
                        vm.cancelTranscribe(for: recording)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
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

    @ViewBuilder
    private func transcriptSection(_ state: TranscribeState) -> some View {
        switch state {
        case .transcribing(let msg):
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text(msg).font(.caption).foregroundStyle(.secondary)
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
            .frame(maxHeight: 300)
            .scrollIndicators(.never)
        case .error(let msg):
            Text(msg).font(.caption).foregroundStyle(.red)
        }
    }

    private var llmActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Summary")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if case .done(let text) = summaryState {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { isSummaryExpanded.toggle() }
                        } label: {
                            Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: text) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("", selection: $selectedSummaryLanguage) {
                        ForEach(LocalLLMService.summaryLanguages) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).font(.caption)

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
                if isSummaryExpanded, let state = summaryState { llmResultView(state) }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Translation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if case .done(let text) = translationState {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { isTranslationExpanded.toggle() }
                        } label: {
                            Image(systemName: isTranslationExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: text) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Picker("", selection: $selectedTranslationLanguage) {
                        ForEach(TranslationLanguage.supported) { lang in
                            Text(lang.label).tag(lang)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).font(.caption)

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
                if isTranslationExpanded, let state = translationState { translationResultView(state) }
            }
        }
    }

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
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 300)
            .scrollIndicators(.never)
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
