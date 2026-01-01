// ABOUTME: Manages the local queue of voice notes on Apple Watch.
// ABOUTME: Persists metadata and tracks note status through upload lifecycle.

import Foundation

/// Manages the queue of notes pending transfer/upload
@MainActor
final class NotesQueueManager: ObservableObject {

    @Published private(set) var notes: [VoiceNoteMetadata] = []

    private let storageURL: URL
    private let audioRecorder: AudioRecorder
    private let sessionManager: WatchSessionManager

    init(
        audioRecorder: AudioRecorder,
        sessionManager: WatchSessionManager = .shared,
        storageDirectory: URL? = nil
    ) {
        self.audioRecorder = audioRecorder
        self.sessionManager = sessionManager

        if let dir = storageDirectory {
            self.storageURL = dir.appendingPathComponent("notes_queue.json")
        } else {
            self.storageURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("notes_queue.json")
        }

        loadNotes()
    }

    /// Add a new note to the queue and initiate transfer
    func enqueue(_ metadata: VoiceNoteMetadata) {
        var note = metadata
        note.status = .queued
        notes.append(note)
        saveNotes()

        // Attempt transfer
        transferNote(note)
    }

    /// Handle ack from iPhone - remove note and delete local file
    func handleAck(_ ack: NoteAck) {
        if ack.status == .uploaded {
            // Find and remove the note
            if let index = notes.firstIndex(where: { $0.id == ack.noteId }) {
                let note = notes[index]
                notes.remove(at: index)

                // Delete local audio file
                audioRecorder.deleteRecording(noteId: note.id)

                saveNotes()
            }
        } else if ack.status == .failed {
            // Update status to failed
            if let index = notes.firstIndex(where: { $0.id == ack.noteId }) {
                notes[index].status = .failed
                saveNotes()
            }
        }
    }

    /// Retry failed notes
    func retryFailed() {
        for index in notes.indices where notes[index].status == .failed {
            notes[index].status = .queued
            transferNote(notes[index])
        }
        saveNotes()
    }

    /// Retry all pending notes (queued and failed) - called when connectivity restored
    func retryPending() {
        for index in notes.indices where notes[index].status == .queued || notes[index].status == .failed {
            if notes[index].status == .failed {
                notes[index].status = .queued
            }
            transferNote(notes[index])
        }
        saveNotes()
    }

    /// Get counts by status
    var queuedCount: Int {
        notes.filter { $0.status == .queued || $0.status == .transferring }.count
    }

    var failedCount: Int {
        notes.filter { $0.status == .failed }.count
    }

    // MARK: - Private

    private func transferNote(_ note: VoiceNoteMetadata) {
        let audioURL = audioRecorder.audioFileURL(for: note.id)

        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            print("Audio file not found for note \(note.id)")
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].status = .failed
                notes[index].errorMessage = "Audio file not found"
                saveNotes()
            }
            return
        }

        if sessionManager.transferFile(at: audioURL, metadata: note) {
            // Update status to transferring
            if let index = notes.firstIndex(where: { $0.id == note.id }) {
                notes[index].status = .transferring
                saveNotes()
            }
        }
    }

    private func loadNotes() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            notes = try JSONDecoder().decode([VoiceNoteMetadata].self, from: data)
        } catch {
            print("Failed to load notes queue: \(error)")
        }
    }

    private func saveNotes() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save notes queue: \(error)")
        }
    }
}
