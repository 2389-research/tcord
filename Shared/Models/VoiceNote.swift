// ABOUTME: Defines the VoiceNote model shared between iOS and watchOS apps.
// ABOUTME: Contains metadata for audio recordings including status tracking.

import Foundation

/// Status of a voice note in the pipeline
enum NoteStatus: String, Codable, Sendable {
    case recording      // Currently being recorded (watch only)
    case queued         // Waiting for transfer to phone
    case transferring   // Being transferred to phone
    case received       // Phone received, pending upload
    case uploading      // Upload in progress
    case uploaded       // Successfully uploaded to Firebase
    case failed         // Upload failed (retryable)
}

/// Status of transcription processing
enum TranscriptionStatus: String, Codable, Sendable {
    case pending        // Not yet started
    case processing     // In progress
    case completed      // Successfully transcribed
    case failed         // Transcription failed
}

/// Metadata for a voice note recording
struct VoiceNoteMetadata: Codable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    var durationMs: Int
    var status: NoteStatus
    var errorMessage: String?

    // Transcription
    var transcription: String?
    var transcriptionStatus: TranscriptionStatus
    var transcriptionLanguage: String?

    // Optional device info
    var watchModel: String?
    var watchOSVersion: String?
    var phoneModel: String?
    var iOSVersion: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        durationMs: Int = 0,
        status: NoteStatus = .recording,
        transcriptionStatus: TranscriptionStatus = .pending
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.status = status
        self.transcriptionStatus = transcriptionStatus
    }

    /// ISO8601 formatted creation date for Firebase
    var createdAtISO: String {
        createdAt.formatted(.iso8601)
    }
}

/// Message sent from iPhone to Watch as acknowledgment
struct NoteAck: Codable, Sendable {
    let noteId: UUID
    let status: NoteStatus
    let uploadedAt: Date?

    init(noteId: UUID, status: NoteStatus, uploadedAt: Date? = nil) {
        self.noteId = noteId
        self.status = status
        self.uploadedAt = uploadedAt
    }
}
