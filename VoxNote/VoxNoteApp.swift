//
//  VoxNoteApp.swift
//  VoxNote
//
//  Created by 승박 on 5/9/26.
//

import SwiftUI
import SwiftData

@main
struct VoxNoteApp: App {

    var body: some Scene {
        WindowGroup {
            MainView()
                .modelContainer(for: [RecordingMetadata.self, RecordingFolder.self])
        }
#if os(macOS)
        .windowResizability(.contentSize)
#endif
    }
}
