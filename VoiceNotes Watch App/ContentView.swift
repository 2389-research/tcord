// ABOUTME: Root view for the VoiceNotes watchOS app.
// ABOUTME: Displays the main user interface for recording voice notes on Apple Watch.

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
