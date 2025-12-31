// ABOUTME: Root view for the iOS Voice Notes app.
// ABOUTME: Shows auth or notes list based on authentication state.

import SwiftUI

struct ContentView: View {

    @StateObject private var authService: AuthService
    @StateObject private var uploadQueue: UploadQueueManager

    init() {
        let auth = AuthService()
        _authService = StateObject(wrappedValue: auth)
        _uploadQueue = StateObject(wrappedValue: UploadQueueManager(authService: auth))
    }

    var body: some View {
        Group {
            if authService.isAuthenticated {
                NotesListView()
            } else {
                AuthView()
            }
        }
        .environmentObject(authService)
        .environmentObject(uploadQueue)
        .onAppear {
            // Connect upload queue to session manager
            PhoneSessionManager.shared.delegate = uploadQueue
        }
    }
}

#Preview {
    ContentView()
}
