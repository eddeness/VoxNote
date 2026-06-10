import SwiftUI
import SwiftData

@main
struct VoxNoteApp: App {
    @State private var vm = MainViewModel()

    var body: some Scene {
        WindowGroup("VoxNoteAI") {
            MainView(vm: vm)
                .modelContainer(for: [RecordingMetadata.self, RecordingFolder.self])
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
