# Voice Notes Transcription Feature Design

**Date:** 2026-01-01
**Status:** Approved

## Overview

Transform VoiceNotes from an audio recording app into a voice-to-text app. The audio serves as capture medium; transcription is the core value.

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| When to transcribe | On-device on Watch | Immediate feedback, works offline |
| Audio retention | Keep as backup | User can replay if transcription missed something |
| List display | Preview snippet (50 chars) | Clean, scannable list with tap for full text |
| Delete UX | Swipe-to-delete | Native iOS pattern |

## Data Model Changes

### VoiceNoteMetadata (Shared)

Add fields:
```swift
var transcription: String?
var transcriptionStatus: TranscriptionStatus
var transcriptionLanguage: String?
```

New enum:
```swift
enum TranscriptionStatus: String, Codable, Sendable {
    case pending
    case processing
    case completed
    case failed
}
```

### Firestore Schema

Add to `users/{uid}/notes/{noteId}`:
- `transcription: String`
- `transcriptionStatus: String`
- `transcriptionLanguage: String`

## Watch: Transcription Service

New `TranscriptionService.swift`:
- Uses Apple Speech framework (`SFSpeechRecognizer`)
- Runs immediately after recording stops
- Transcription included in metadata sent to iPhone
- Falls back to `.failed` status if transcription fails

### Flow
1. User stops recording
2. `AudioRecorder.stopRecording()` returns metadata
3. `TranscriptionService.transcribe(audioURL:)` runs
4. Metadata updated with transcription
5. Enqueued for transfer to iPhone

### Permissions Required
- `NSSpeechRecognitionUsageDescription` in Watch Info.plist

## iOS: UI Changes

### NotesListView Updates
- Row shows: timestamp + first 50 chars of transcription
- Status badge if transcription processing/failed
- Swipe-left to delete with confirmation
- Tap navigates to NoteDetailView

### NoteDetailView (New)
- Full transcription text (selectable, copyable)
- Metadata: date, duration
- Play button for original audio
- Delete button
- Share button for transcription text

## iOS: Delete Service

Add to `UploadService`:
```swift
func deleteNote(noteId: UUID, uid: String) async throws {
    // 1. Delete Firestore document
    // 2. Delete Storage file
}
```

## Files to Create/Modify

| File | Action |
|------|--------|
| `Shared/Models/VoiceNote.swift` | Modify - add transcription fields |
| `VoiceNotes Watch App/Services/TranscriptionService.swift` | Create |
| `VoiceNotes Watch App/ContentView.swift` | Modify - call transcription |
| `VoiceNotes Watch App/Info.plist` | Modify - add permission |
| `VoiceNotes/Views/NotesListView.swift` | Modify - swipe delete, preview |
| `VoiceNotes/Views/NoteDetailView.swift` | Create |
| `VoiceNotes/Services/UploadService.swift` | Modify - add deleteNote |

## Security

No changes to Firebase rules required - existing user isolation covers new fields.

## Future Considerations (Out of Scope)

- Server-side transcription for better quality
- Auto-delete audio after N days
- Search transcriptions
- Export transcriptions
