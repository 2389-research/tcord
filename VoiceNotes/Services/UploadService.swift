// ABOUTME: Handles uploading audio files to Firebase Storage.
// ABOUTME: Creates metadata documents in Firestore after successful upload.

import Foundation
import FirebaseStorage
import FirebaseFirestore

/// Handles uploads to Firebase Storage and Firestore
final class UploadService {

    private let storage = Storage.storage()
    private let firestore = Firestore.firestore()

    /// Upload audio file to Firebase Storage and create Firestore document
    func upload(
        fileURL: URL,
        metadata: VoiceNoteMetadata,
        uid: String,
        progressHandler: ((Double) -> Void)? = nil
    ) async throws -> VoiceNoteMetadata {

        var updatedMetadata = metadata

        // 1. Upload to Storage
        let storagePath = "users/\(uid)/notes/\(metadata.id.uuidString)/audio.m4a"
        let storageRef = storage.reference().child(storagePath)

        let storageMetadata = StorageMetadata()
        storageMetadata.contentType = "audio/mp4"
        storageMetadata.customMetadata = [
            "noteId": metadata.id.uuidString,
            "createdAt": metadata.createdAtISO,
            "durationMs": String(metadata.durationMs)
        ]

        // Upload with progress tracking
        let uploadTask = storageRef.putFile(from: fileURL, metadata: storageMetadata)

        // Track progress
        if let handler = progressHandler {
            uploadTask.observe(.progress) { snapshot in
                let progress = Double(snapshot.progress?.completedUnitCount ?? 0) /
                               Double(snapshot.progress?.totalUnitCount ?? 1)
                handler(progress)
            }
        }

        // Wait for completion with safe continuation handling
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            var hasResumed = false

            uploadTask.observe(.success) { snapshot in
                guard !hasResumed else { return }
                hasResumed = true
                if let metadata = snapshot.metadata {
                    continuation.resume(returning: metadata)
                } else {
                    continuation.resume(throwing: UploadError.uploadFailed)
                }
            }
            uploadTask.observe(.failure) { snapshot in
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(throwing: snapshot.error ?? UploadError.uploadFailed)
            }
        }

        // 2. Create Firestore document
        let docRef = firestore
            .collection("users").document(uid)
            .collection("notes").document(metadata.id.uuidString)

        var firestoreData: [String: Any] = [
            "noteId": metadata.id.uuidString,
            "createdAt": Timestamp(date: metadata.createdAt),
            "receivedAt": Timestamp(date: Date()),
            "uploadedAt": Timestamp(date: Date()),
            "durationMs": metadata.durationMs,
            "storagePath": storagePath,
            "contentType": "audio/mp4",
            "status": NoteStatus.uploaded.rawValue,
            "transcriptionStatus": metadata.transcriptionStatus.rawValue,
            "device": [
                "watchModel": metadata.watchModel ?? "",
                "phoneModel": metadata.phoneModel ?? "",
                "watchOS": metadata.watchOSVersion ?? "",
                "iOS": metadata.iOSVersion ?? ""
            ]
        ]

        // Include transcription if available
        if let transcription = metadata.transcription {
            firestoreData["transcription"] = transcription
        }
        if let language = metadata.transcriptionLanguage {
            firestoreData["transcriptionLanguage"] = language
        }

        try await docRef.setData(firestoreData)

        // 3. Update metadata
        updatedMetadata.status = .uploaded

        return updatedMetadata
    }

    /// Get download URL for a note's audio
    func downloadURL(for noteId: UUID, uid: String) async throws -> URL {
        let storagePath = "users/\(uid)/notes/\(noteId.uuidString)/audio.m4a"
        let storageRef = storage.reference().child(storagePath)
        return try await storageRef.downloadURL()
    }

    /// Delete a note from Firestore and Storage
    func deleteNote(noteId: UUID, uid: String) async throws {
        // Delete Firestore document first
        let docRef = firestore
            .collection("users").document(uid)
            .collection("notes").document(noteId.uuidString)
        try await docRef.delete()

        // Delete Storage file
        let storagePath = "users/\(uid)/notes/\(noteId.uuidString)/audio.m4a"
        let storageRef = storage.reference().child(storagePath)
        try await storageRef.delete()
    }
}

/// Errors during upload
enum UploadError: LocalizedError {
    case uploadFailed
    case noUser

    var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "Failed to upload file"
        case .noUser:
            return "No authenticated user"
        }
    }
}
