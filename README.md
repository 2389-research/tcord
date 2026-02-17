# VoiceNotes

Record voice memos on your Apple Watch, get instant transcriptions, and sync everything to the cloud.

## What It Does

VoiceNotes is an Apple Watch + iPhone app for capturing quick voice notes. You tap a button on your wrist, speak, and the Watch transcribes your audio on-device using Apple Speech. The recording and transcription transfer to your iPhone via WatchConnectivity, where a durable upload queue syncs everything to Firebase. Both devices retain files until confirmed uploaded, so nothing gets lost.

## Architecture

```
┌─────────────────┐     WatchConnectivity      ┌─────────────────┐
│   Apple Watch    │ ──────────────────────────▸ │     iPhone      │
│                  │                             │                 │
│ Record (AVFound) │     transferFile(.m4a)      │ Receive file    │
│ Transcribe (Speech)                            │ Queue upload    │
│ Queue locally    │ ◂────────── ack ─────────── │ Upload Firebase │
│ Delete on ack    │                             │ Delete on ack   │
└─────────────────┘                             └────────┬────────┘
                                                         │
                                                         ▼
                                                ┌─────────────────┐
                                                │    Firebase      │
                                                │                  │
                                                │ Auth (Apple)     │
                                                │ Storage (.m4a)   │
                                                │ Firestore (meta) │
                                                └─────────────────┘
```

### Key Design Decisions

- **On-device transcription**: Runs on the Watch immediately after recording stops. Works offline, provides instant feedback.
- **Reliability-first**: Both Watch and iPhone maintain persistent local queues. Files are only deleted after confirmed upload. Upload retries use exponential backoff (capped at 30s).
- **User isolation**: Firebase security rules ensure each user can only access their own data (`users/{uid}/notes/{noteId}`).

## Tech Stack

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9 |
| UI | SwiftUI |
| iOS target | 17.0+ |
| watchOS target | 10.0+ |
| Audio | AVFoundation (AAC, 22kHz, mono) |
| Transcription | Apple Speech (`SFSpeechRecognizer`) |
| Device sync | WatchConnectivity (`transferFile`) |
| Auth | Firebase Auth (Sign in with Apple) |
| Storage | Firebase Storage |
| Database | Firebase Firestore |
| Project gen | XcodeGen |
| Packages | Swift Package Manager |

## Project Structure

```
tcord/
├── Shared/                        # Code shared between iOS and watchOS
│   ├── Models/VoiceNote.swift     # VoiceNoteMetadata, NoteStatus, NoteAck
│   └── Connectivity/             # WatchConnectivity message types
├── VoiceNotes/                    # iOS app
│   ├── Services/
│   │   ├── AuthService.swift      # Sign in with Apple + Firebase Auth
│   │   ├── PhoneSessionManager.swift  # Receives files from Watch
│   │   ├── UploadQueueManager.swift   # Durable upload queue with retry
│   │   └── UploadService.swift        # Firebase Storage + Firestore
│   └── Views/
│       ├── ContentView.swift      # Auth routing
│       ├── AuthView.swift         # Sign in with Apple UI
│       ├── NotesListView.swift    # Notes list with swipe-to-delete
│       └── NoteDetailView.swift   # Full transcription, playback, share
├── VoiceNotes Watch App/          # watchOS app
│   ├── Services/
│   │   ├── AudioRecorder.swift        # AVFoundation recording
│   │   ├── TranscriptionService.swift # On-device speech-to-text
│   │   ├── WatchSessionManager.swift  # WatchConnectivity sender
│   │   └── NotesQueueManager.swift    # Local note queue persistence
│   └── ContentView.swift          # Single-button record UI
├── firebase/                      # Security rules
│   ├── firestore.rules
│   └── storage.rules
├── docs/plans/                    # Design docs
├── project.yml                    # XcodeGen config
└── .mcp.json                      # XcodeBuildMCP config
```

## Setup

### Prerequisites

- Xcode 15.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Firebase project with Auth, Firestore, and Storage enabled
- An Apple Developer account (for Sign in with Apple)

### Steps

1. Clone the repo:
   ```bash
   git clone <repo-url> && cd tcord
   ```

2. Copy the Firebase config template and fill in your values:
   ```bash
   cp VoiceNotes/GoogleService-Info.plist.example VoiceNotes/GoogleService-Info.plist
   ```
   Replace the placeholder values with your actual Firebase project config from the [Firebase Console](https://console.firebase.google.com).

3. Generate the Xcode project:
   ```bash
   xcodegen generate
   ```

4. Open the generated project:
   ```bash
   open VoiceNotes.xcodeproj
   ```

5. In Xcode, resolve Swift Package Manager dependencies (should happen automatically).

6. Configure signing for both the iOS and watchOS targets with your team/bundle ID.

7. Deploy Firebase security rules:
   ```bash
   firebase deploy --only firestore:rules,storage
   ```

8. Build and run on a paired iPhone + Apple Watch.

### Firebase Console Setup

Enable these services in your Firebase project:

- **Authentication**: Enable "Apple" as a sign-in provider
- **Firestore Database**: Create a database (the security rules in `firebase/` handle access control)
- **Storage**: Enable Cloud Storage

## Usage

1. Open VoiceNotes on your iPhone and sign in with Apple
2. On your Apple Watch, tap the blue record button
3. Speak your note, then tap the red stop button
4. The Watch transcribes your audio and transfers it to iPhone
5. iPhone uploads the audio and transcription to Firebase
6. View your notes in the iPhone app - tap for full transcription, playback, or sharing

## Development

Generate the Xcode project after changing `project.yml`:
```bash
xcodegen generate
```

Run watchOS tests:
```bash
xcodebuild test \
  -project VoiceNotes.xcodeproj \
  -scheme "VoiceNotes Watch App" \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'
```

Run iOS tests:
```bash
xcodebuild test \
  -project VoiceNotes.xcodeproj \
  -scheme VoiceNotes \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## License

Private project. All rights reserved.
