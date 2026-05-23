import SwiftUI

struct MainView: View {

    @State private var vm = MainViewModel()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            recordingsList
            Divider()
            controlBar
        }
#if os(macOS)
        .frame(minWidth: 600, minHeight: 440)
#endif
        .onAppear { vm.onAppear() }
    }

    // MARK: - Toolbar
    private var toolbar: some View {
        HStack {
            Text("Recordings")
                .font(.headline)

            Spacer()

            // Whisper model status
            if !vm.isWhisperLoaded {
                Button {
                    Task { await vm.loadWhisperModel() }
                } label: {
                    Label(vm.whisperStatus, systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Recordings list
    private var recordingsList: some View {
        Group {
            if vm.recordings.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.recordings) { rec in
                            RecordingRowView(
                                recording: rec,
                                player: vm.player,
                                vm: vm
                            ) {
                                vm.delete(rec)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "mic.slash")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No recordings yet")
                .foregroundStyle(.secondary)
            Text("Tap the mic button to start")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Control bar
    private var controlBar: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                if vm.isRecording {
                    Text(vm.formattedElapsed)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.red)
                        .contentTransition(.numericText())
                        .animation(.default, value: vm.elapsedSeconds)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RecordButton(
                isRecording: vm.isRecording,
                isDisabled: vm.isProcessing
            ) {
                vm.toggleRecording()
            }

            Spacer()
                .frame(maxWidth: .infinity)
        }
        .background(.bar)
        .padding(.horizontal, 24)
        .frame(height: 100)
    }
}

#Preview {
    MainView()
}
