// ABOUTME: Root view for the VoiceNotes iOS app.
// ABOUTME: Displays the main user interface for managing voice notes.

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "waveform.circle.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("VoiceNotes")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
