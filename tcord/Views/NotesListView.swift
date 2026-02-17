// ABOUTME: Displays list of voice notes with transcription previews.
// ABOUTME: Shows upload status badges and provides swipe-to-delete.

import SwiftUI
import FirebaseFirestore

struct NotesListView: View {

    @EnvironmentObject var authService: AuthService
    @EnvironmentObject var uploadQueue: UploadQueueManager

    @State private var notes: [FirestoreNote] = []
    @State private var isLoading = true
    @State private var notesListener: ListenerRegistration?
    @State private var noteToDelete: FirestoreNote?
    @State private var showDeleteConfirmation = false

    private let uploadService = UploadService()
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading notes...")
                } else if notes.isEmpty && uploadQueue.queue.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "waveform",
                        description: Text("Record a note on your Apple Watch to get started.")
                    )
                } else {
                    notesList
                }
            }
            .navigationTitle("tcord")
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
                notesListener?.remove()
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $showDeleteConfirmation,
                presenting: noteToDelete
            ) { note in
                Button("Delete", role: .destructive) {
                    deleteNote(note)
                }
                Button("Cancel", role: .cancel) {
                    noteToDelete = nil
                }
            } message: { _ in
                Text("This will permanently delete the note and its audio recording.")
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
                Section("Notes") {
                    ForEach(notes) { note in
                        NavigationLink(destination: NoteDetailView(note: note, onDelete: {
                            // Note will be removed via Firestore listener
                        })) {
                            uploadedRow(note)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                noteToDelete = note
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
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
        VStack(alignment: .leading, spacing: 4) {
            // Date and duration
            HStack {
                Text(formatDate(note.createdAt))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(formatDuration(note.durationMs))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Transcription preview
            if let transcription = note.transcription, !transcription.isEmpty {
                Text(transcription)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundColor(.primary)
            } else {
                Text("No transcription")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .padding(.vertical, 4)
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

    private func deleteNote(_ note: FirestoreNote) {
        guard let uid = authService.uid,
              let noteUUID = UUID(uuidString: note.noteId) else { return }

        Task {
            do {
                try await uploadService.deleteNote(noteId: noteUUID, uid: uid)
                // Note will be removed from list via Firestore listener
            } catch {
                print("Failed to delete note: \(error)")
            }
            noteToDelete = nil
        }
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
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

    // Transcription fields
    let transcription: String?
    let transcriptionStatus: String?
    let transcriptionLanguage: String?
}
