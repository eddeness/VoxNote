import SwiftUI

struct OnboardingView: View {

    var vm: MainViewModel
    let onComplete: () -> Void

    @State private var status: Status = .intro
    @State private var downloadTask: Task<Void, Never>?
    @State private var availableGB: Double = 0

    enum Status {
        case intro
        case downloading(String)
        case done
        case failed(String)
    }

    private var requiredGB: Double {
#if os(macOS)
        return 4.0
#else
        return 2.0
#endif
    }

    private var modelSizeText: String {
#if os(macOS)
        return "First-time setup downloads ~3GB AI model"
#else
        return "First-time setup downloads ~150MB–1.5GB AI model"
#endif
    }

    private var diskSpaceOK: Bool {
        availableGB <= 0 || availableGB >= requiredGB
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
                        InfoRow(icon: "arrow.down.circle", text: modelSizeText)
                        InfoRow(icon: "wifi", text: "Internet required only for initial download")
                        InfoRow(icon: "iphone", text: "iPhone 12 or later / Apple Silicon Mac recommended")

                        // Disk space row
                        if availableGB > 0 {
                            InfoRow(
                                icon: diskSpaceOK ? "internaldrive" : "exclamationmark.triangle",
                                text: String(format: "Available disk space: %.1f GB", availableGB)
                            )
                            .foregroundStyle(diskSpaceOK ? .secondary : Color.orange)
                        }
                    }
                    .padding(.vertical, 8)

                    // Low disk space warning
                    if availableGB > 0 && !diskSpaceOK {
                        Text("Low disk space. At least \(Int(requiredGB)) GB is recommended.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }

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

                        // Cancel is only meaningful while the file is downloading.
                        // Once model loading (CoreML compilation) starts, cancellation
                        // may not stop the work already in progress, so hide it.
                        if isCancellable(msg) {
                            Button("Cancel") {
                                downloadTask?.cancel()
                                downloadTask = nil
                                status = .intro
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .frame(minHeight: 100)

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
                            // Retry — re-attempts the download. WhisperKit/Hugging Face's
                            // downloader may skip already-completed files, but does not
                            // guarantee byte-level resume of a partial file.
                            Button("Retry Download") {
                                Task { await downloadModel() }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Start Over") {
                                status = .intro
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(40)
#if os(macOS)
        .frame(minWidth: 560, minHeight: 540)
#endif
        .onAppear {
            checkDiskSpace()
        }
        .onDisappear {
            // If the view is dismissed mid-download (e.g. app backgrounded/killed),
            // cancel the task so it doesn't keep running unattended.
            downloadTask?.cancel()
        }
    }

    private func isCancellable(_ msg: String) -> Bool {
        // Only cancellable while actively downloading, and only below 90% —
        // past that point the transfer is close enough to done that cancelling
        // wastes more than it saves, and loading (CoreML compile) is imminent.
        guard msg.lowercased().hasPrefix("downloading") else { return false }
        if let pctRange = msg.range(of: #"\d+"#, options: .regularExpression),
           let pct = Int(msg[pctRange]) {
            return pct < 90
        }
        return true
    }

    private func checkDiskSpace() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]
        )
        if let bytes = values?.volumeAvailableCapacity {
            availableGB = Double(bytes) / 1_000_000_000
        }
    }

    private func downloadModel() async {
        status = .downloading("Starting…")
        downloadTask = Task {
            await vm.loadWhisperModel { msg in
                Task { @MainActor in
                    if !Task.isCancelled {
                        status = .downloading(msg)
                    }
                }
            }
            // Route every status transition through the main actor together,
            // so cancellation / success / failure are decided consistently.
            await MainActor.run {
                if Task.isCancelled {
                    // Cancelled — stay on intro so user can resume later.
                    status = .intro
                } else if vm.isWhisperLoaded {
                    status = .done
                } else {
                    status = .failed(vm.whisperStatus)
                }
            }
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
