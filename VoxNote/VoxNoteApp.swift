import SwiftUI
import SwiftData

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct VoxNoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
