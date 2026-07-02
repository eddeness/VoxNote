import SwiftUI
import SwiftData

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
#endif

@main
struct VoxNoteApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
#endif
    @State private var vm = MainViewModel()

    var body: some Scene {
        WindowGroup("VoxNoteAI") {
            MainView(vm: vm)
                .modelContainer(for: [RecordingMetadata.self, RecordingFolder.self])
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif

#if os(macOS)
        // Live transcription runs in its own window on macOS.
        WindowGroup("Live Transcribe", id: "live") {
            LiveTranscribeView(vm: vm)
        }
        .defaultSize(width: 520, height: 480)
#endif
    }
}
