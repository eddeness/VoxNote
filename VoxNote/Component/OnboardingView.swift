import SwiftUI

struct OnboardingView: View {

    var vm: MainViewModel
    let onComplete: () -> Void

    @State private var status: Status = .intro
    @State private var downloadTask: Task<Void, Never>?
    
    enum Status {
        case intro
        case downloading(String)
        case done
        case failed(String)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            // Icon
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // Title
            VStack(spacing: 8) {
                Text("Welcome to VoxNoteAI")
                    .font(.largeTitle.weight(.semibold))
                Text("Record, transcribe, summarize, and translate — all on your device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Status / Action area
            VStack(spacing: 16) {
                switch status {
                case .intro:
                    VStack(spacing: 8) {
                        InfoRow(icon: "checkmark.shield", text: "Fully on-device, no data sent to servers")
                        InfoRow(icon: "arrow.down.circle", text: "First-time setup downloads ~3GB AI model")
                        InfoRow(icon: "wifi", text: "Internet required only for initial download")
                    }
                    .padding(.vertical, 8)

                    Button {
                        Task { await downloadModel() }
                    } label: {
                        Text("Download or Load Model & Continue")
                            .font(.headline)
                            .frame(width: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                case .downloading(let msg):
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .frame(height: 80)

                case .done:
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.green)
                        Text("All set!")
                            .font(.headline)
                        Button {
                            onComplete()
                        } label: {
                            Text("Get Started")
                                .frame(width: 200)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                case .failed(let err):
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                        HStack {
                            Button("Retry") {
                                Task { await downloadModel() }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Skip") { onComplete() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(40)
        .frame(minWidth: 560, minHeight: 540)
    }

    private func downloadModel() async {
        downloadTask = Task {
            await vm.loadWhisperModel { msg in
                Task { @MainActor in status = .downloading(msg) }
            }
            if vm.isWhisperLoaded {
                status = .done
            } else if Task.isCancelled {
                status = .intro
            } else {
                status = .failed(vm.whisperStatus)
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
