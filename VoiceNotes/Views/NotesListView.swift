// ABOUTME: Displays list of voice notes with playback and status.
// ABOUTME: Shows upload status badges and provides retry for failed uploads.

import SwiftUI
import FirebaseFirestore
import AVFoundation

struct NotesListView: View {

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var uploadQueue: UploadQueueManager

    @State private var notes: [FirestoreNote] = []
    @State private var isLoading = true
    @State private var selectedNote: FirestoreNote?
    @State private var isPlaying = false
    @State private var audioPlayer: AVPlayer?
    @State private var playbackObserver: NSObjectProtocol?
    @State private var notesListener: ListenerRegistration?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading notes...")
                } else if notes.isEmpty && uploadQueue.queue.isEmpty {
                    ContentUnavailableView(
                        "No Voice Notes",
                        systemImage: "waveform",
                        description: Text("Record a note on your Apple Watch to get started.")
                    )
                } else {
                    notesList
                }
            }
            .navigationTitle("Voice Notes")
            .toolbar {
                if uploadQueue.pendingCount > 0 {
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("\(uploadQueue.pendingCount)")
                                .font(.caption)
                        }
                    }
                }
            }
            .onAppear {
                loadNotes()
            }
            .onDisappear {
                // Clean up listeners
                notesListener?.remove()
                if let observer = playbackObserver {
                    NotificationCenter.default.removeObserver(observer)
                }
                audioPlayer?.pause()
            }
        }
    }

    private var notesList: some View {
        List {
            // Pending uploads section
            if !uploadQueue.queue.isEmpty {
                Section("Pending") {
                    ForEach(uploadQueue.queue) { item in
                        pendingRow(item)
                    }
                }
            }

            // Uploaded notes section
            if !notes.isEmpty {
                Section("Uploaded") {
                    ForEach(notes) { note in
                        uploadedRow(note)
                    }
                }
            }
        }
    }

    private func pendingRow(_ item: UploadQueueItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(formatDate(item.metadata.createdAt))
                    .font(.headline)
                Text(formatDuration(item.metadata.durationMs))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusBadge(for: item.metadata.status)

            if item.metadata.status == .failed {
                Button("Retry") {
                    uploadQueue.retry(id: item.id)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
    }

    private func uploadedRow(_ note: FirestoreNote) -> some View {
        Button {
            playNote(note)
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(formatDate(note.createdAt))
                        .font(.headline)
                    Text(formatDuration(note.durationMs))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if selectedNote?.id == note.id && isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundColor(.blue)
                } else {
                    Image(systemName: "play.circle")
                        .foregroundColor(.secondary)
                }
            }
        }
        .foregroundColor(.primary)
    }

    private func statusBadge(for status: NoteStatus) -> some View {
        Group {
            switch status {
            case .uploading:
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Uploading")
                        .font(.caption)
                }
            case .failed:
                Text("Failed")
                    .font(.caption)
                    .foregroundColor(.red)
            case .received:
                Text("Queued")
                    .font(.caption)
                    .foregroundColor(.orange)
            default:
                EmptyView()
            }
        }
    }

    private func loadNotes() {
        guard let uid = authService.uid else {
            isLoading = false
            return
        }

        notesListener = Firestore.firestore()
            .collection("users").document(uid)
            .collection("notes")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                isLoading = false

                guard let documents = snapshot?.documents else { return }

                notes = documents.compactMap { doc -> FirestoreNote? in
                    try? doc.data(as: FirestoreNote.self)
                }
            }
    }

    private func playNote(_ note: FirestoreNote) {
        guard let uid = authService.uid else { return }

        guard let noteUUID = UUID(uuidString: note.noteId) else {
            print("Invalid note ID format: \(note.noteId)")
            return
        }

        Task {
            do {
                let url = try await UploadService().downloadURL(for: noteUUID, uid: uid)

                // Clean up previous observer
                if let observer = playbackObserver {
                    NotificationCenter.default.removeObserver(observer)
                }

                audioPlayer?.pause()
                audioPlayer = AVPlayer(url: url)
                audioPlayer?.play()

                selectedNote = note
                isPlaying = true

                // Observe when playback ends
                playbackObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: audioPlayer?.currentItem,
                    queue: .main
                ) { _ in
                    isPlaying = false
                }
            } catch {
                print("Failed to play note: \(error)")
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ ms: Int) -> String {
        let seconds = ms / 1000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

/// Firestore note document model
struct FirestoreNote: Codable, Identifiable {
    @DocumentID var id: String?
    let noteId: String
    let createdAt: Date
    let uploadedAt: Date?
    let durationMs: Int
    let storagePath: String
    let status: String
}
