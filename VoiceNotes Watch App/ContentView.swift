// ABOUTME: Main view for the watchOS Voice Notes app.
// ABOUTME: Provides a single-button interface for recording voice memos.

import SwiftUI

struct ContentView: View {

    @StateObject private var audioRecorder: AudioRecorder
    @StateObject private var queueManager: NotesQueueManager

    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isTranscribing = false

    private let transcriptionService = TranscriptionService()

    init() {
        let recorder = AudioRecorder()
        _audioRecorder = StateObject(wrappedValue: recorder)
        _queueManager = StateObject(wrappedValue: NotesQueueManager(audioRecorder: recorder))
    }

    var body: some View {
        VStack(spacing: 16) {
            // Status indicator
            statusView

            // Main record button
            recordButton

            // Queue status
            queueStatusView
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            WatchSessionManager.shared.activate()
            WatchSessionManager.shared.delegate = queueManager
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if audioRecorder.isRecording {
            VStack {
                Text("Recording")
                    .font(.headline)
                    .foregroundColor(.red)
                Text(formatDuration(audioRecorder.recordingDuration))
                    .font(.title2)
                    .monospacedDigit()
            }
        } else if isTranscribing {
            VStack {
                ProgressView()
                Text("Transcribing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else {
            Text("Tap to Record")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private var recordButton: some View {
        Button(action: toggleRecording) {
            Circle()
                .fill(audioRecorder.isRecording ? Color.red : Color.blue)
                .frame(width: 80, height: 80)
                .overlay {
                    if audioRecorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white)
                            .frame(width: 30, height: 30)
                    } else {
                        Circle()
                            .fill(.white)
                            .frame(width: 30, height: 30)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var queueStatusView: some View {
        if queueManager.queuedCount > 0 {
            Text("\(queueManager.queuedCount) pending")
                .font(.caption)
                .foregroundColor(.secondary)
        }

        if queueManager.failedCount > 0 {
            Button("Retry \(queueManager.failedCount) failed") {
                queueManager.retryFailed()
            }
            .font(.caption)
            .foregroundColor(.orange)
        }
    }

    private func toggleRecording() {
        Task {
            if audioRecorder.isRecording {
                do {
                    var metadata = try await audioRecorder.stopRecording()
                    let audioURL = audioRecorder.audioFileURL(for: metadata.id)

                    // Transcribe the recording
                    isTranscribing = true
                    defer { isTranscribing = false }

                    do {
                        let result = try await transcriptionService.transcribe(audioURL: audioURL)
                        metadata.transcription = result.text
                        metadata.transcriptionStatus = .completed
                        metadata.transcriptionLanguage = result.language
                    } catch {
                        // Transcription failed - still enqueue, phone can retry
                        metadata.transcriptionStatus = .failed
                        print("Transcription failed: \(error)")
                    }

                    queueManager.enqueue(metadata)
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            } else {
                do {
                    try await audioRecorder.startRecording()
                } catch {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// Conform NotesQueueManager to WatchSessionDelegate
extension NotesQueueManager: WatchSessionDelegate {
    nonisolated func didReceiveAck(_ ack: NoteAck) {
        Task { @MainActor in
            self.handleAck(ack)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ reachable: Bool) {
        // Retry all pending notes when reachable
        if reachable {
            Task { @MainActor in
                self.retryPending()
            }
        }
    }
}

#Preview {
    ContentView()
}
