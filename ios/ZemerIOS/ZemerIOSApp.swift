import SwiftUI

@main
struct ZemerIOSApp: App {
    @StateObject private var player = AudioPlayer()
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .environmentObject(library)
                .tint(.primary)
        }
    }
}
