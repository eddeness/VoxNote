import SwiftUI
import SwiftData

@main
struct VoxNoteApp: App {

    var body: some Scene {
        WindowGroup("VoxNoteAI") {
            MainView()
                .modelContainer(for: [RecordingMetadata.self, RecordingFolder.self])
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}
