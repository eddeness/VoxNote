import SwiftUI

struct LiveTranscribeView: View {
    @Bindable var vm: MainViewModel

    @State private var liveText: String = ""
    @State private var errorMessage: String?
    private let liveService = LiveTranscriptionService()

    var body: some View {
        VStack(spacing: 0) {
            // Header
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
                ShareLink(item: liveText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(liveText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Transcript area
            ScrollView {
                if liveText.isEmpty {
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
                    Text(liveText)
                        .font(.body)
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
        .frame(minWidth: 480, minHeight: 400)
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

            let lang = vm.transcribeLanguageCode == "auto" ? nil : vm.transcribeLanguageCode

            do {
                try liveService.start(
                    language: lang,
                    onText: { text in
                        Task { @MainActor in liveText = text }
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
