import SwiftUI
import SwiftData

struct MainView: View {
    @Bindable var vm: MainViewModel
#if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
#endif
    @Environment(\.modelContext) private var modelContext
    @Query private var allMetadata: [RecordingMetadata]

    @State private var showNewFolderSheet = false
    @State private var showLiveSheet = false
    @State private var availableDiskGB: Double = 0

    var body: some View {
        Group {
            if !vm.isWhisperLoaded {
                OnboardingView(vm: vm) {}
            } else {
                mainContent
            }
        }
    }

    private var mainContent: some View {
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
        .onAppear {
            vm.modelContext = modelContext
            vm.allMetadata = allMetadata
            vm.onAppear()
            checkDiskSpace()
#if os(macOS)
            dismissWindow(id: "live")
#endif
        }
        .onChange(of: allMetadata) { _, newValue in
            vm.allMetadata = newValue
        }
#if os(iOS)
        .onChange(of: vm.isRecording) { _, recording in
            UIApplication.shared.isIdleTimerDisabled = recording
        }
#endif
#if os(macOS)
        .onDisappear {
            vm.resetAll()
        }
#endif
        .alert("Microphone Access Required", isPresented: $vm.showMicrophonePermissionAlert) {
            Button("Open Settings") {
#if os(macOS)
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
                )
#else
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
#endif
            }
            Button("Cancel", role: .cancel) { vm.appState = .ready }
        } message: {
            Text("VoxNoteAI needs microphone access to record audio.")
        }
        .alert("Recording Stopped", isPresented: $vm.showMaxDurationAlert) {
            Button("OK") { vm.showMaxDurationAlert = false }
        } message: {
            Text("Maximum recording duration (3 hours) has been reached. Your recording has been saved.")
        }
        .sheet(isPresented: $showNewFolderSheet) {
            RenameSheet(
                title: "New Folder",
                initialName: "",
                onSave: { name in
                    _ = vm.createFolder(name: name)
                    showNewFolderSheet = false
                },
                onCancel: { showNewFolderSheet = false }
            )
        }
#if os(iOS)
        .fullScreenCover(isPresented: $showLiveSheet) {
            LiveTranscribeView(vm: vm, onClose: { showLiveSheet = false })
        }
#endif
    }

    private func checkDiskSpace() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return }
        if let bytes = values.volumeAvailableCapacityForImportantUsage {
            availableDiskGB = Double(bytes) / 1_000_000_000
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            if !vm.isAtRoot {
                Button {
                    vm.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                }
                .buttonStyle(.plain)
            }

            Text(vm.folderPathName)
                .font(.headline)

            Spacer()

            if !vm.isWhisperLoaded && vm.whisperStatus != "Model not loaded" {
                HStack(spacing: 6) {
                    if vm.whisperStatus.contains("%") {
                        let pct = Double(vm.whisperStatus.filter("0123456789".contains)) ?? 0
                        ProgressView(value: pct, total: 100)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                    } else {
                        ProgressView().scaleEffect(0.7)
                    }
                    Text(vm.whisperStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // New folder
            Button {
                showNewFolderSheet = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.plain)

            // Disk space indicator
            if availableDiskGB > 0 {
                Text(String(format: "%.1f GB", availableDiskGB))
                    .font(.caption)
                    .foregroundStyle(availableDiskGB >= 2 ? .secondary : Color.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var recordingsList: some View {
        Group {
            if vm.visibleFolders.isEmpty && vm.visibleRecordingItems.isEmpty && vm.isAtRoot {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if !vm.isAtRoot {
                            ParentFolderRow(
                                onTap: { vm.goBack() },
                                onDrop: { id in
                                    vm.moveRecording(id: id, to: vm.currentFolder?.parent)
                                }
                            )
                        }

                        ForEach(vm.visibleFolders) { folder in
                            FolderRowView(
                                folder: folder,
                                onTap: { vm.enterFolder(folder) },
                                onDelete: { vm.deleteFolder(folder) },
                                onRename: { name in
                                    _ = vm.renameFolder(folder, to: name)
                                },
                                onDrop: { id in vm.moveRecording(id: id, to: folder) }
                            )
                        }

                        ForEach(vm.visibleRecordingItems) { item in
                            RecordingRowView(
                                item: item,
                                player: vm.player,
                                vm: vm
                            ) {
                                vm.delete(item.recording)
                            }
                        }
                    }
                    .padding()
                    .id(vm.folderPathName)
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

            HStack {
                if vm.isRecording {
                    Button {
#if os(macOS)
                        openWindow(id: "live")
#else
                        showLiveSheet = true
#endif
                    } label: {
                        Label("Live", systemImage: "waveform")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .background(.bar)
        .padding(.horizontal, 24)
        .frame(height: 100)
    }
}
