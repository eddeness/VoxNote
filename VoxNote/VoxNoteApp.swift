import SwiftUI
import SwiftData

@main
struct VoxNoteApp: App {
    @State private var vm = MainViewModel()
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Scene {
        WindowGroup("VoxNoteAI") {
            MainView(vm: vm)
                .modelContainer(for: [RecordingMetadata.self, RecordingFolder.self])
                .onDisappear {
                    dismissWindow(id: "live")
                }
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif
        WindowGroup("Live Transcribe", id: "live") {
            LiveTranscribeView(vm: vm)
        }
        .defaultSize(width: 520, height: 480)
    }
}
