// ABOUTME: Main entry point for the iOS Voice Notes app.
// ABOUTME: Configures Firebase and activates WatchConnectivity session.

import SwiftUI
import FirebaseCore

@main
struct VoiceNotesApp: App {

    init() {
        // Configure Firebase
        FirebaseApp.configure()

        // Activate WatchConnectivity
        PhoneSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
