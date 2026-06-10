import SwiftUI
import SwiftData

struct MainView: View {
    @Bindable var vm: MainViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showNewFolderSheet = false

    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView(vm: vm) {
                    hasCompletedOnboarding = true
                }
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
            vm.onAppear()
        }
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

            Button {
                showNewFolderSheet = true
            } label: {
                Image(systemName: "folder.badge.plus")
                    .font(.headline)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var recordingsList: some View {
        Group {
            if vm.visibleFolders.isEmpty && vm.visibleRecordings.isEmpty {
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

                        ForEach(vm.visibleRecordings) { rec in
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
            Image(systemName: vm.isAtRoot ? "mic.slash" : "folder")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text(vm.isAtRoot ? "No recordings yet" : "Empty folder")
                .foregroundStyle(.secondary)
            Text(vm.isAtRoot ? "Tap the mic button to start" : "Add recordings or subfolders")
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
                        openWindow(id: "live")
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
