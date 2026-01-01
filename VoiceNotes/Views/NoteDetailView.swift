// ABOUTME: Displays full transcription and details for a single voice note.
// ABOUTME: Provides playback, copy, share, and delete functionality.

import SwiftUI
import AVFoundation

struct NoteDetailView: View {

    let note: FirestoreNote
    let onDelete: () -> Void

    @EnvironmentObject var authService: AuthService

    @State private var isPlaying = false
    @State private var audioPlayer: AVPlayer?
    @State private var playbackObserver: NSObjectProtocol?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false

    private let uploadService = UploadService()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Metadata header
                VStack(alignment: .leading, spacing: 4) {
                    Text(Self.dateFormatter.string(from: note.createdAt))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(formatDuration(note.durationMs))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Transcription
                if let transcription = note.transcription, !transcription.isEmpty {
                    Text(transcription)
                        .font(.body)
                        .textSelection(.enabled)
                } else {
                    Text("No transcription available")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                }

                Divider()

                // Playback controls
                HStack {
                    Button {
                        togglePlayback()
                    } label: {
                        Label(
                            isPlaying ? "Stop" : "Play Audio",
                            systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill"
                        )
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    // Share button
                    if let transcription = note.transcription, !transcription.isEmpty {
                        ShareLink(item: transcription) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer(minLength: 40)

                // Delete button
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    if isDeleting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Delete Note", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isDeleting)
            }
            .padding()
        }
        .navigationTitle("Note Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let transcription = note.transcription, !transcription.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = transcription
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete the note and its audio recording.")
        }
        .onDisappear {
            cleanupPlayback()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            cleanupPlayback()
            isPlaying = false
        } else {
            playAudio()
        }
    }

    private func playAudio() {
        guard let uid = authService.uid,
              let noteUUID = UUID(uuidString: note.noteId) else { return }

        Task {
            do {
                let url = try await uploadService.downloadURL(for: noteUUID, uid: uid)

                cleanupPlayback()

                let player = AVPlayer(url: url)
                audioPlayer = player
                player.play()
                isPlaying = true

                playbackObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: player.currentItem,
                    queue: .main
                ) { _ in
                    isPlaying = false
                }
            } catch {
                print("Failed to play audio: \(error)")
            }
        }
    }

    private func cleanupPlayback() {
        if let observer = playbackObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackObserver = nil
        }
        audioPlayer?.pause()
        audioPlayer?.replaceCurrentItem(with: nil)
        audioPlayer = nil
    }

    private func deleteNote() {
        guard let uid = authService.uid,
              let noteUUID = UUID(uuidString: note.noteId) else { return }

        isDeleting = true

        Task {
            do {
                try await uploadService.deleteNote(noteId: noteUUID, uid: uid)
                onDelete()
            } catch {
                print("Failed to delete note: \(error)")
                isDeleting = false
            }
        }
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}
