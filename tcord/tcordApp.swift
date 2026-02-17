// ABOUTME: Main entry point for the iOS tcord app.
// ABOUTME: Configures Firebase and activates WatchConnectivity session.

import SwiftUI
import FirebaseCore

@main
struct tcordApp: App {

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
