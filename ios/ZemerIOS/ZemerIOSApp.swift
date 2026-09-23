import SwiftUI

@main
struct ZemerIOSApp: App {
    @StateObject private var player = AudioPlayer()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .tint(.primary)
        }
    }
}
