# Voice Notes MVP Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an Apple Watch voice note capture tool that records audio, transfers to iPhone, and uploads to Firebase with reliable delivery guarantees.

**Architecture:** Watch records .m4a audio locally, uses WatchConnectivity `transferFile` for background delivery to iPhone. iPhone maintains a durable upload queue, uploads to Firebase Storage, writes metadata to Firestore, and sends ack back to watch. Both sides retain files until confirmation.

**Tech Stack:** SwiftUI, WatchConnectivity, AVFoundation, Firebase Auth/Storage/Firestore, Swift Concurrency

---

## Phase 1: Project Scaffolding

### Task 1.1: Create Xcode Project with Watch Target

**Files:**
- Create: Xcode project "VoiceNotes" with iOS + watchOS targets

**Step 1: Create project structure**

Run:
```bash
cd /Users/harper/Public/src/personal/tcord
# Create Xcode project via command line or Xcode
# We'll use a script to scaffold since we need multi-target setup
```

For this task, manually create in Xcode:
1. File → New → Project
2. Choose "App" under iOS
3. Product Name: `VoiceNotes`
4. Team: Your team
5. Organization Identifier: `com.yourname`
6. Interface: SwiftUI
7. Language: Swift
8. Storage: None (we'll add Firebase manually)
9. Include Tests: Yes

Then add Watch target:
1. File → New → Target
2. Choose "App" under watchOS
3. Product Name: `VoiceNotes Watch App`
4. Embed in: VoiceNotes (iOS app)

**Step 2: Verify project structure**

Run:
```bash
ls -la /Users/harper/Public/src/personal/tcord/VoiceNotes*
```

Expected structure:
```
VoiceNotes/
├── VoiceNotes/           # iOS app
├── VoiceNotes Watch App/ # watchOS app
├── VoiceNotesTests/
└── VoiceNotes.xcodeproj/
```

**Step 3: Add .gitignore**

Create `.gitignore`:
```gitignore
# Xcode
*.xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
build/
*.ipa
*.dSYM.zip
*.dSYM

# Dependencies
Pods/
Carthage/Build/

# Firebase
GoogleService-Info.plist

# Swift Package Manager
.build/
.swiftpm/

# OS
.DS_Store

# Secrets
*.pem
*.p8
```

**Step 4: Initial commit**

Run:
```bash
cd /Users/harper/Public/src/personal/tcord
git init
git add .
git commit -m "chore: initial project scaffold with iOS and watchOS targets"
```

---

### Task 1.2: Add Firebase SDK via Swift Package Manager

**Files:**
- Modify: `VoiceNotes.xcodeproj` (add package dependency)

**Step 1: Add Firebase packages**

In Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/firebase/firebase-ios-sdk`
3. Version: Up to Next Major (11.0.0+)
4. Add to target: VoiceNotes (iOS app only - Watch can't use Firebase directly)

Select these products:
- FirebaseAuth
- FirebaseFirestore
- FirebaseStorage

**Step 2: Verify package resolution**

Build the iOS target to ensure packages resolve:
```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme VoiceNotes -destination 'platform=iOS Simulator,name=iPhone 15' build
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add .
git commit -m "chore: add Firebase SDK dependencies"
```

---

### Task 1.3: Create Firebase Project and Download Config

**Files:**
- Create: `VoiceNotes/GoogleService-Info.plist` (not committed, in .gitignore)
- Create: `VoiceNotes/GoogleService-Info.plist.example` (template for docs)

**Step 1: Create Firebase project**

1. Go to https://console.firebase.google.com
2. Create new project: "VoiceNotes"
3. Enable Google Analytics (optional)
4. Add iOS app with bundle ID matching your project
5. Download `GoogleService-Info.plist`
6. Add to Xcode project (VoiceNotes iOS target only)

**Step 2: Enable Firebase services**

In Firebase Console:
1. Authentication → Sign-in method → Enable "Apple"
2. Firestore Database → Create database → Start in test mode (we'll add rules later)
3. Storage → Get started → Start in test mode

**Step 3: Create example plist for documentation**

Create `GoogleService-Info.plist.example`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>API_KEY</key>
    <string>YOUR_API_KEY</string>
    <key>GCM_SENDER_ID</key>
    <string>YOUR_SENDER_ID</string>
    <key>BUNDLE_ID</key>
    <string>com.yourcompany.VoiceNotes</string>
    <key>PROJECT_ID</key>
    <string>your-project-id</string>
    <key>STORAGE_BUCKET</key>
    <string>your-project-id.appspot.com</string>
    <!-- Add remaining keys from your actual GoogleService-Info.plist -->
</dict>
</plist>
```

**Step 4: Commit**

```bash
git add VoiceNotes/GoogleService-Info.plist.example
git commit -m "docs: add GoogleService-Info.plist example template"
```

---

## Phase 2: Shared Models and Infrastructure

### Task 2.1: Create Shared Note Model

**Files:**
- Create: `VoiceNotes/Shared/Models/VoiceNote.swift`
- Create: `VoiceNotes Watch App/Shared/` (group reference to same files)

**Step 1: Write the model**

Create `VoiceNotes/Shared/Models/VoiceNote.swift`:
```swift
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

/// Metadata for a voice note recording
struct VoiceNoteMetadata: Codable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    var durationMs: Int
    var status: NoteStatus
    var errorMessage: String?

    // Optional device info
    var watchModel: String?
    var watchOSVersion: String?
    var phoneModel: String?
    var iOSVersion: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        durationMs: Int = 0,
        status: NoteStatus = .recording
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationMs = durationMs
        self.status = status
    }

    /// ISO8601 formatted creation date for Firebase
    var createdAtISO: String {
        ISO8601DateFormatter().string(from: createdAt)
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
```

**Step 2: Add file to both targets**

In Xcode, select `VoiceNote.swift` and in File Inspector, check both:
- VoiceNotes (iOS)
- VoiceNotes Watch App

**Step 3: Build both targets to verify**

```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme VoiceNotes -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project VoiceNotes.xcodeproj -scheme "VoiceNotes Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build
```

Expected: Both BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add shared VoiceNote model with status tracking"
```

---

### Task 2.2: Create WatchConnectivity Message Types

**Files:**
- Create: `VoiceNotes/Shared/Connectivity/MessageTypes.swift`

**Step 1: Write message type definitions**

Create `VoiceNotes/Shared/Connectivity/MessageTypes.swift`:
```swift
// ABOUTME: Defines message types for WatchConnectivity communication.
// ABOUTME: Used for ack messages and status updates between watch and phone.

import Foundation

/// Keys used in WatchConnectivity message dictionaries
enum WCMessageKey: String {
    case messageType = "type"
    case noteId = "noteId"
    case status = "status"
    case uploadedAt = "uploadedAt"
    case error = "error"
}

/// Types of messages sent between watch and phone
enum WCMessageType: String, Codable {
    case ack = "ack"                    // Phone → Watch: upload complete
    case statusUpdate = "statusUpdate"  // Phone → Watch: status changed
    case retry = "retry"                // Watch → Phone: retry failed upload
}

/// Helper to encode/decode messages
enum WCMessageCoder {

    /// Encode an ack message to dictionary
    static func encodeAck(_ ack: NoteAck) -> [String: Any] {
        var dict: [String: Any] = [
            WCMessageKey.messageType.rawValue: WCMessageType.ack.rawValue,
            WCMessageKey.noteId.rawValue: ack.noteId.uuidString,
            WCMessageKey.status.rawValue: ack.status.rawValue
        ]
        if let uploadedAt = ack.uploadedAt {
            dict[WCMessageKey.uploadedAt.rawValue] = uploadedAt.timeIntervalSince1970
        }
        return dict
    }

    /// Decode an ack message from dictionary
    static func decodeAck(from dict: [String: Any]) -> NoteAck? {
        guard
            let typeString = dict[WCMessageKey.messageType.rawValue] as? String,
            typeString == WCMessageType.ack.rawValue,
            let noteIdString = dict[WCMessageKey.noteId.rawValue] as? String,
            let noteId = UUID(uuidString: noteIdString),
            let statusString = dict[WCMessageKey.status.rawValue] as? String,
            let status = NoteStatus(rawValue: statusString)
        else {
            return nil
        }

        var uploadedAt: Date?
        if let timestamp = dict[WCMessageKey.uploadedAt.rawValue] as? TimeInterval {
            uploadedAt = Date(timeIntervalSince1970: timestamp)
        }

        return NoteAck(noteId: noteId, status: status, uploadedAt: uploadedAt)
    }
}
```

**Step 2: Add to both targets**

**Step 3: Build to verify**

```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme VoiceNotes -destination 'platform=iOS Simulator,name=iPhone 15' build
```

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add WatchConnectivity message types and coding helpers"
```

---

## Phase 3: Watch App - Audio Recording

### Task 3.1: Create Audio Recorder Service

**Files:**
- Create: `VoiceNotes Watch App/Services/AudioRecorder.swift`
- Create: `VoiceNotes Watch App/VoiceNotesWatchAppTests/AudioRecorderTests.swift`

**Step 1: Write the failing test**

Create test file:
```swift
// ABOUTME: Tests for the AudioRecorder service on watchOS.
// ABOUTME: Verifies recording lifecycle, file creation, and duration tracking.

import XCTest
@testable import VoiceNotes_Watch_App

final class AudioRecorderTests: XCTestCase {

    var recorder: AudioRecorder!
    var testDirectory: URL!

    override func setUp() {
        super.setUp()
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        recorder = AudioRecorder(recordingsDirectory: testDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testDirectory)
        super.tearDown()
    }

    func testInitialStateIsIdle() {
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
    }

    func testStartRecordingChangesState() async throws {
        try await recorder.startRecording()

        XCTAssertTrue(recorder.isRecording)
        XCTAssertNotNil(recorder.currentRecordingURL)
    }

    func testStopRecordingReturnsMetadata() async throws {
        try await recorder.startRecording()

        // Record for a brief moment
        try await Task.sleep(for: .milliseconds(100))

        let metadata = try await recorder.stopRecording()

        XCTAssertFalse(recorder.isRecording)
        XCTAssertGreaterThan(metadata.durationMs, 0)
        XCTAssertEqual(metadata.status, .queued)
    }

    func testRecordingCreatesFile() async throws {
        try await recorder.startRecording()
        try await Task.sleep(for: .milliseconds(100))
        let metadata = try await recorder.stopRecording()

        let expectedURL = testDirectory.appendingPathComponent("\(metadata.id.uuidString).m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project VoiceNotes.xcodeproj -scheme "VoiceNotes Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'
```

Expected: FAIL - AudioRecorder type not found

**Step 3: Write minimal implementation**

Create `VoiceNotes Watch App/Services/AudioRecorder.swift`:
```swift
// ABOUTME: Manages audio recording on Apple Watch using AVFoundation.
// ABOUTME: Records to .m4a format optimized for voice (AAC, mono, low bitrate).

import AVFoundation
import Foundation

/// Errors that can occur during audio recording
enum AudioRecorderError: Error, LocalizedError {
    case permissionDenied
    case recordingInProgress
    case notRecording
    case setupFailed(Error)
    case recordingFailed(Error)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission denied"
        case .recordingInProgress:
            return "Recording already in progress"
        case .notRecording:
            return "No recording in progress"
        case .setupFailed(let error):
            return "Audio setup failed: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        }
    }
}

/// Service for recording audio on Apple Watch
@MainActor
final class AudioRecorder: ObservableObject {

    @Published private(set) var isRecording = false
    @Published private(set) var currentRecordingURL: URL?
    @Published private(set) var recordingDuration: TimeInterval = 0

    private let recordingsDirectory: URL
    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var currentNoteId: UUID?
    private var durationTimer: Timer?

    /// Audio settings optimized for voice recording
    private let audioSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 22050,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        AVEncoderBitRateKey: 32000
    ]

    init(recordingsDirectory: URL? = nil) {
        if let dir = recordingsDirectory {
            self.recordingsDirectory = dir
        } else {
            self.recordingsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recordings")
        }

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: self.recordingsDirectory, withIntermediateDirectories: true)
    }

    /// Request microphone permission
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Start recording a new voice note
    func startRecording() async throws {
        guard !isRecording else {
            throw AudioRecorderError.recordingInProgress
        }

        // Check permission
        let hasPermission = await requestPermission()
        guard hasPermission else {
            throw AudioRecorderError.permissionDenied
        }

        // Setup audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            throw AudioRecorderError.setupFailed(error)
        }

        // Generate new note ID and file URL
        let noteId = UUID()
        let fileURL = recordingsDirectory.appendingPathComponent("\(noteId.uuidString).m4a")

        // Create and start recorder
        do {
            let recorder = try AVAudioRecorder(url: fileURL, settings: audioSettings)
            recorder.prepareToRecord()

            guard recorder.record() else {
                throw AudioRecorderError.recordingFailed(NSError(domain: "AudioRecorder", code: -1))
            }

            self.audioRecorder = recorder
            self.currentNoteId = noteId
            self.currentRecordingURL = fileURL
            self.recordingStartTime = Date()
            self.isRecording = true
            self.recordingDuration = 0

            // Start duration timer
            startDurationTimer()

        } catch {
            throw AudioRecorderError.setupFailed(error)
        }
    }

    /// Stop recording and return metadata
    func stopRecording() async throws -> VoiceNoteMetadata {
        guard isRecording, let recorder = audioRecorder, let noteId = currentNoteId else {
            throw AudioRecorderError.notRecording
        }

        // Stop recording
        recorder.stop()
        stopDurationTimer()

        // Calculate duration
        let startTime = recordingStartTime ?? Date()
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        // Create metadata
        var metadata = VoiceNoteMetadata(
            id: noteId,
            createdAt: startTime,
            durationMs: durationMs,
            status: .queued
        )

        // Add device info
        #if os(watchOS)
        metadata.watchModel = getWatchModel()
        metadata.watchOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        #endif

        // Reset state
        self.audioRecorder = nil
        self.currentNoteId = nil
        self.recordingStartTime = nil
        self.isRecording = false
        self.recordingDuration = 0

        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)

        return metadata
    }

    /// Cancel current recording and delete file
    func cancelRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        stopDurationTimer()

        if let url = currentRecordingURL {
            try? FileManager.default.removeItem(at: url)
        }

        self.audioRecorder = nil
        self.currentNoteId = nil
        self.currentRecordingURL = nil
        self.recordingStartTime = nil
        self.isRecording = false
        self.recordingDuration = 0

        try? AVAudioSession.sharedInstance().setActive(false)
    }

    /// Get URL for a note's audio file
    func audioFileURL(for noteId: UUID) -> URL {
        recordingsDirectory.appendingPathComponent("\(noteId.uuidString).m4a")
    }

    /// Delete a recording file
    func deleteRecording(noteId: UUID) {
        let url = audioFileURL(for: noteId)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Private

    private func startDurationTimer() {
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.recordingStartTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    private func getWatchModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
```

**Step 4: Run tests to verify they pass**

```bash
xcodebuild test -project VoiceNotes.xcodeproj -scheme "VoiceNotes Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)'
```

Expected: PASS (note: some tests may require permission mocking in simulator)

**Step 5: Commit**

```bash
git add .
git commit -m "feat(watch): add AudioRecorder service with duration tracking"
```

---

### Task 3.2: Add Microphone Permission to Info.plist

**Files:**
- Modify: `VoiceNotes Watch App/Info.plist`

**Step 1: Add permission string**

Add to `Info.plist`:
```xml
<key>NSMicrophoneUsageDescription</key>
<string>VoiceNotes needs microphone access to record voice memos.</string>
```

**Step 2: Commit**

```bash
git add .
git commit -m "chore(watch): add microphone usage description"
```

---

## Phase 4: Watch App - WatchConnectivity

### Task 4.1: Create WatchConnectivity Session Manager (Watch Side)

**Files:**
- Create: `VoiceNotes Watch App/Services/WatchSessionManager.swift`

**Step 1: Write the implementation**

Create `VoiceNotes Watch App/Services/WatchSessionManager.swift`:
```swift
// ABOUTME: Manages WatchConnectivity session on the watchOS side.
// ABOUTME: Handles file transfers to iPhone and receives ack messages.

import Foundation
import WatchConnectivity

/// Delegate protocol for receiving acks and status updates
protocol WatchSessionDelegate: AnyObject {
    func didReceiveAck(_ ack: NoteAck)
    func sessionReachabilityDidChange(_ reachable: Bool)
}

/// Manages WatchConnectivity on the watch side
final class WatchSessionManager: NSObject, ObservableObject {

    static let shared = WatchSessionManager()

    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false
    @Published private(set) var pendingTransfers: [UUID: WCSessionFileTransfer] = [:]

    weak var delegate: WatchSessionDelegate?

    private var session: WCSession?

    private override init() {
        super.init()
    }

    /// Activate the WatchConnectivity session
    func activate() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Transfer a recorded audio file to the iPhone
    func transferFile(at url: URL, metadata: VoiceNoteMetadata) -> Bool {
        guard let session = session, session.activationState == .activated else {
            print("Session not activated")
            return false
        }

        // Encode metadata as dictionary for WC
        let metadataDict: [String: Any] = [
            "noteId": metadata.id.uuidString,
            "createdAt": metadata.createdAtISO,
            "durationMs": metadata.durationMs,
            "watchModel": metadata.watchModel ?? "",
            "watchOSVersion": metadata.watchOSVersion ?? ""
        ]

        let transfer = session.transferFile(url, metadata: metadataDict)
        pendingTransfers[metadata.id] = transfer

        return true
    }

    /// Get count of pending transfers
    var pendingTransferCount: Int {
        session?.outstandingFileTransfers.count ?? 0
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Session activation failed: \(error)")
            return
        }

        Task { @MainActor in
            self.isReachable = session.isReachable
            #if os(watchOS)
            self.isPaired = session.isCompanionAppInstalled
            #endif
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            self.delegate?.sessionReachabilityDidChange(session.isReachable)
        }
    }

    // Receive messages from iPhone (acks)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if let ack = WCMessageCoder.decodeAck(from: message) {
            // Remove from pending
            Task { @MainActor in
                self.pendingTransfers.removeValue(forKey: ack.noteId)
                self.delegate?.didReceiveAck(ack)
            }
        }
    }

    // File transfer completed
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error = error {
            print("File transfer failed: \(error)")
            // Note: transfer will be retried by the system
        } else {
            print("File transfer completed successfully")
        }
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme "VoiceNotes Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat(watch): add WatchConnectivity session manager"
```

---

### Task 4.2: Create Notes Queue Manager (Watch Side)

**Files:**
- Create: `VoiceNotes Watch App/Services/NotesQueueManager.swift`

**Step 1: Write the implementation**

Create `VoiceNotes Watch App/Services/NotesQueueManager.swift`:
```swift
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
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(watch): add NotesQueueManager for local note persistence"
```

---

## Phase 5: Watch App - UI

### Task 5.1: Create Recording View

**Files:**
- Modify: `VoiceNotes Watch App/ContentView.swift`

**Step 1: Write the UI**

Replace `ContentView.swift`:
```swift
// ABOUTME: Main view for the watchOS Voice Notes app.
// ABOUTME: Provides a single-button interface for recording voice memos.

import SwiftUI

struct ContentView: View {

    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var queueManager: NotesQueueManager
    @State private var showError = false
    @State private var errorMessage = ""

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
            WatchSessionManager.shared.delegate = queueManager as? WatchSessionDelegate
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
                    let metadata = try await audioRecorder.stopRecording()
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
        // Could retry queued notes when reachable
        if reachable {
            Task { @MainActor in
                self.retryFailed()
            }
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Build and test**

```bash
xcodebuild -project VoiceNotes.xcodeproj -scheme "VoiceNotes Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build
```

**Step 3: Commit**

```bash
git add .
git commit -m "feat(watch): add recording UI with queue status display"
```

---

## Phase 6: iPhone App - WatchConnectivity Receiver

### Task 6.1: Create WatchConnectivity Session Manager (iPhone Side)

**Files:**
- Create: `VoiceNotes/Services/PhoneSessionManager.swift`

**Step 1: Write the implementation**

Create `VoiceNotes/Services/PhoneSessionManager.swift`:
```swift
// ABOUTME: Manages WatchConnectivity session on the iOS side.
// ABOUTME: Receives audio files from watch and coordinates upload pipeline.

import Foundation
import WatchConnectivity

/// Delegate protocol for receiving files from watch
protocol PhoneSessionDelegate: AnyObject {
    func didReceiveFile(at url: URL, metadata: VoiceNoteMetadata)
}

/// Manages WatchConnectivity on the iPhone side
final class PhoneSessionManager: NSObject, ObservableObject {

    static let shared = PhoneSessionManager()

    @Published private(set) var isReachable = false
    @Published private(set) var isPaired = false

    weak var delegate: PhoneSessionDelegate?

    private var session: WCSession?
    private let inboxDirectory: URL

    private override init() {
        // Create directory to store received files
        inboxDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchInbox")
        try? FileManager.default.createDirectory(at: inboxDirectory, withIntermediateDirectories: true)

        super.init()
    }

    /// Activate the WatchConnectivity session
    func activate() {
        guard WCSession.isSupported() else {
            print("WatchConnectivity not supported on this device")
            return
        }

        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    /// Send ack back to watch
    func sendAck(_ ack: NoteAck) {
        guard let session = session, session.isReachable else {
            print("Watch not reachable, ack will be sent when available")
            return
        }

        let message = WCMessageCoder.encodeAck(ack)
        session.sendMessage(message, replyHandler: nil) { error in
            print("Failed to send ack: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("Session activation failed: \(error)")
            return
        }

        Task { @MainActor in
            self.isReachable = session.isReachable
            self.isPaired = session.isPaired
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // iOS only - handle session becoming inactive
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // iOS only - reactivate session
        session.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }

    // Receive files from watch
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Extract metadata from transfer
        guard let metadataDict = file.metadata,
              let noteIdString = metadataDict["noteId"] as? String,
              let noteId = UUID(uuidString: noteIdString),
              let createdAtString = metadataDict["createdAt"] as? String,
              let durationMs = metadataDict["durationMs"] as? Int else {
            print("Invalid metadata in received file")
            return
        }

        // Parse created date
        let formatter = ISO8601DateFormatter()
        let createdAt = formatter.date(from: createdAtString) ?? Date()

        // Create metadata object
        var metadata = VoiceNoteMetadata(
            id: noteId,
            createdAt: createdAt,
            durationMs: durationMs,
            status: .received
        )
        metadata.watchModel = metadataDict["watchModel"] as? String
        metadata.watchOSVersion = metadataDict["watchOSVersion"] as? String
        metadata.phoneModel = getPhoneModel()
        metadata.iOSVersion = ProcessInfo.processInfo.operatingSystemVersionString

        // Move file from WC inbox to our managed directory
        let destinationURL = inboxDirectory.appendingPathComponent("\(noteId.uuidString).m4a")

        do {
            // Remove existing file if any
            try? FileManager.default.removeItem(at: destinationURL)
            // Move new file
            try FileManager.default.moveItem(at: file.fileURL, to: destinationURL)

            // Notify delegate
            delegate?.didReceiveFile(at: destinationURL, metadata: metadata)
        } catch {
            print("Failed to move received file: \(error)")
        }
    }

    private func getPhoneModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): add PhoneSessionManager to receive files from watch"
```

---

## Phase 7: iPhone App - Firebase Integration

### Task 7.1: Configure Firebase in App Delegate

**Files:**
- Modify: `VoiceNotes/VoiceNotesApp.swift`

**Step 1: Write the configuration**

Modify `VoiceNotesApp.swift`:
```swift
// ABOUTME: Main entry point for the iOS Voice Notes app.
// ABOUTME: Configures Firebase and activates WatchConnectivity session.

import SwiftUI
import FirebaseCore

@main
struct VoiceNotesApp: App {

    init() {
        // Configure Firebase
        FirebaseApp.configure()

        // Activate WatchConnectivity
        PhoneSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): configure Firebase and WatchConnectivity on app launch"
```

---

### Task 7.2: Create Auth Service

**Files:**
- Create: `VoiceNotes/Services/AuthService.swift`

**Step 1: Write the implementation**

Create `VoiceNotes/Services/AuthService.swift`:
```swift
// ABOUTME: Manages Firebase Authentication for the iOS app.
// ABOUTME: Supports Sign in with Apple and anonymous auth for MVP.

import Foundation
import FirebaseAuth
import AuthenticationServices
import CryptoKit

/// Manages user authentication with Firebase
@MainActor
final class AuthService: NSObject, ObservableObject {

    @Published private(set) var currentUser: User?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var isLoading = false
    @Published var error: Error?

    private var currentNonce: String?
    private var authStateHandler: AuthStateDidChangeListenerHandle?

    override init() {
        super.init()

        // Listen for auth state changes
        authStateHandler = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }

    deinit {
        if let handler = authStateHandler {
            Auth.auth().removeStateDidChangeListener(handler)
        }
    }

    /// Current user's UID
    var uid: String? {
        currentUser?.uid
    }

    /// Sign in with Apple
    func signInWithApple() async throws {
        isLoading = true
        defer { isLoading = false }

        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.email, .fullName]
        request.nonce = sha256(nonce)

        // Perform the authorization
        let result = try await performAppleSignIn(request: request)

        guard let appleIDCredential = result.credential as? ASAuthorizationAppleIDCredential,
              let identityToken = appleIDCredential.identityToken,
              let tokenString = String(data: identityToken, encoding: .utf8) else {
            throw AuthError.invalidCredential
        }

        // Create Firebase credential
        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: tokenString,
            rawNonce: nonce
        )

        // Sign in to Firebase
        let authResult = try await Auth.auth().signIn(with: credential)

        // Update display name if available
        if let fullName = appleIDCredential.fullName {
            let displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")

            if !displayName.isEmpty {
                let changeRequest = authResult.user.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try? await changeRequest.commitChanges()
            }
        }
    }

    /// Sign in anonymously (for testing/MVP)
    func signInAnonymously() async throws {
        isLoading = true
        defer { isLoading = false }

        try await Auth.auth().signInAnonymously()
    }

    /// Sign out
    func signOut() throws {
        try Auth.auth().signOut()
    }

    // MARK: - Private helpers

    private func performAppleSignIn(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            let controller = ASAuthorizationController(authorizationRequests: [request])
            let delegate = AppleSignInDelegate(continuation: continuation)
            controller.delegate = delegate

            // Keep delegate alive
            objc_setAssociatedObject(controller, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)

            controller.performRequests()
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
        }

        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(randomBytes.map { charset[Int($0) % charset.count] })
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

/// Errors during authentication
enum AuthError: LocalizedError {
    case invalidCredential
    case noCurrentUser

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "Invalid authentication credential"
        case .noCurrentUser:
            return "No user is signed in"
        }
    }
}

/// Helper delegate for Apple Sign In
private class AppleSignInDelegate: NSObject, ASAuthorizationControllerDelegate {
    private let continuation: CheckedContinuation<ASAuthorization, Error>

    init(continuation: CheckedContinuation<ASAuthorization, Error>) {
        self.continuation = continuation
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation.resume(returning: authorization)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation.resume(throwing: error)
    }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): add AuthService with Sign in with Apple support"
```

---

### Task 7.3: Create Upload Service

**Files:**
- Create: `VoiceNotes/Services/UploadService.swift`

**Step 1: Write the implementation**

Create `VoiceNotes/Services/UploadService.swift`:
```swift
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

        // Wait for completion
        _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<StorageMetadata, Error>) in
            uploadTask.observe(.success) { snapshot in
                continuation.resume(returning: snapshot.metadata!)
            }
            uploadTask.observe(.failure) { snapshot in
                continuation.resume(throwing: snapshot.error ?? UploadError.uploadFailed)
            }
        }

        // 2. Create Firestore document
        let docRef = firestore
            .collection("users").document(uid)
            .collection("notes").document(metadata.id.uuidString)

        let firestoreData: [String: Any] = [
            "noteId": metadata.id.uuidString,
            "createdAt": Timestamp(date: metadata.createdAt),
            "receivedAt": Timestamp(date: Date()),
            "uploadedAt": Timestamp(date: Date()),
            "durationMs": metadata.durationMs,
            "storagePath": storagePath,
            "contentType": "audio/mp4",
            "status": NoteStatus.uploaded.rawValue,
            "device": [
                "watchModel": metadata.watchModel ?? "",
                "phoneModel": metadata.phoneModel ?? "",
                "watchOS": metadata.watchOSVersion ?? "",
                "iOS": metadata.iOSVersion ?? ""
            ]
        ]

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
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): add UploadService for Firebase Storage and Firestore"
```

---

### Task 7.4: Create Upload Queue Manager

**Files:**
- Create: `VoiceNotes/Services/UploadQueueManager.swift`

**Step 1: Write the implementation**

Create `VoiceNotes/Services/UploadQueueManager.swift`:
```swift
// ABOUTME: Manages the durable upload queue on iOS.
// ABOUTME: Persists pending uploads across app restarts with retry logic.

import Foundation

/// Item in the upload queue
struct UploadQueueItem: Codable, Identifiable {
    let id: UUID
    var metadata: VoiceNoteMetadata
    let localFileURL: URL
    var retryCount: Int = 0
    var lastError: String?
    let addedAt: Date

    init(metadata: VoiceNoteMetadata, localFileURL: URL) {
        self.id = metadata.id
        self.metadata = metadata
        self.localFileURL = localFileURL
        self.addedAt = Date()
    }
}

/// Manages the queue of files pending upload to Firebase
@MainActor
final class UploadQueueManager: ObservableObject {

    @Published private(set) var queue: [UploadQueueItem] = []
    @Published private(set) var isProcessing = false
    @Published private(set) var currentUploadProgress: Double = 0

    private let storageURL: URL
    private let uploadService: UploadService
    private let authService: AuthService
    private let sessionManager: PhoneSessionManager

    private let maxRetries = 3
    private var processingTask: Task<Void, Never>?

    init(
        uploadService: UploadService = UploadService(),
        authService: AuthService,
        sessionManager: PhoneSessionManager = .shared,
        storageDirectory: URL? = nil
    ) {
        self.uploadService = uploadService
        self.authService = authService
        self.sessionManager = sessionManager

        if let dir = storageDirectory {
            self.storageURL = dir.appendingPathComponent("upload_queue.json")
        } else {
            self.storageURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("upload_queue.json")
        }

        loadQueue()
    }

    /// Add a new item to the upload queue
    func enqueue(metadata: VoiceNoteMetadata, localFileURL: URL) {
        let item = UploadQueueItem(metadata: metadata, localFileURL: localFileURL)
        queue.append(item)
        saveQueue()

        // Start processing if not already
        startProcessing()
    }

    /// Start processing the queue
    func startProcessing() {
        guard !isProcessing else { return }

        processingTask = Task {
            await processQueue()
        }
    }

    /// Retry a specific failed item
    func retry(id: UUID) {
        if let index = queue.firstIndex(where: { $0.id == id }) {
            queue[index].metadata.status = .received
            queue[index].retryCount = 0
            saveQueue()
            startProcessing()
        }
    }

    /// Remove an item from the queue
    func remove(id: UUID) {
        queue.removeAll { $0.id == id }
        saveQueue()
    }

    /// Get counts
    var pendingCount: Int {
        queue.filter { $0.metadata.status == .received || $0.metadata.status == .uploading }.count
    }

    var failedCount: Int {
        queue.filter { $0.metadata.status == .failed }.count
    }

    // MARK: - Private

    private func processQueue() async {
        isProcessing = true
        defer { isProcessing = false }

        while let index = queue.firstIndex(where: { $0.metadata.status == .received }) {
            // Check for auth
            guard let uid = authService.uid else {
                // Wait for auth and try again later
                try? await Task.sleep(for: .seconds(5))
                continue
            }

            // Mark as uploading
            queue[index].metadata.status = .uploading
            saveQueue()

            let item = queue[index]
            currentUploadProgress = 0

            do {
                // Verify file exists
                guard FileManager.default.fileExists(atPath: item.localFileURL.path) else {
                    throw UploadError.uploadFailed
                }

                // Upload
                let updatedMetadata = try await uploadService.upload(
                    fileURL: item.localFileURL,
                    metadata: item.metadata,
                    uid: uid
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.currentUploadProgress = progress
                    }
                }

                // Success - send ack to watch
                let ack = NoteAck(noteId: item.id, status: .uploaded, uploadedAt: Date())
                sessionManager.sendAck(ack)

                // Remove from queue
                queue.removeAll { $0.id == item.id }

                // Delete local file
                try? FileManager.default.removeItem(at: item.localFileURL)

                saveQueue()

            } catch {
                // Handle failure
                if let currentIndex = queue.firstIndex(where: { $0.id == item.id }) {
                    queue[currentIndex].retryCount += 1
                    queue[currentIndex].lastError = error.localizedDescription

                    if queue[currentIndex].retryCount >= maxRetries {
                        queue[currentIndex].metadata.status = .failed

                        // Send failure ack to watch
                        let ack = NoteAck(noteId: item.id, status: .failed)
                        sessionManager.sendAck(ack)
                    } else {
                        // Will retry
                        queue[currentIndex].metadata.status = .received

                        // Exponential backoff
                        let delay = pow(2.0, Double(queue[currentIndex].retryCount))
                        try? await Task.sleep(for: .seconds(delay))
                    }

                    saveQueue()
                }
            }

            currentUploadProgress = 0
        }
    }

    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            queue = try JSONDecoder().decode([UploadQueueItem].self, from: data)
        } catch {
            print("Failed to load upload queue: \(error)")
        }
    }

    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: storageURL)
        } catch {
            print("Failed to save upload queue: \(error)")
        }
    }
}

// MARK: - PhoneSessionDelegate

extension UploadQueueManager: PhoneSessionDelegate {
    nonisolated func didReceiveFile(at url: URL, metadata: VoiceNoteMetadata) {
        Task { @MainActor in
            self.enqueue(metadata: metadata, localFileURL: url)
        }
    }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): add UploadQueueManager with retry logic and persistence"
```

---

## Phase 8: iPhone App - UI

### Task 8.1: Create Notes List View

**Files:**
- Create: `VoiceNotes/Views/NotesListView.swift`

**Step 1: Write the implementation**

Create `VoiceNotes/Views/NotesListView.swift`:
```swift
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

        Firestore.firestore()
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

        Task {
            do {
                let url = try await UploadService().downloadURL(for: UUID(uuidString: note.noteId)!, uid: uid)

                audioPlayer?.pause()
                audioPlayer = AVPlayer(url: url)
                audioPlayer?.play()

                selectedNote = note
                isPlaying = true

                // Observe when playback ends
                NotificationCenter.default.addObserver(
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
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): add NotesListView with playback and upload status"
```

---

### Task 8.2: Create Auth View

**Files:**
- Create: `VoiceNotes/Views/AuthView.swift`

**Step 1: Write the implementation**

Create `VoiceNotes/Views/AuthView.swift`:
```swift
// ABOUTME: Authentication view for signing in with Apple.
// ABOUTME: Shown when user is not authenticated.

import SwiftUI
import AuthenticationServices

struct AuthView: View {

    @EnvironmentObject var authService: AuthService
    @State private var showError = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon/branding
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)

            Text("Voice Notes")
                .font(.largeTitle)
                .bold()

            Text("Record voice memos on your Apple Watch and access them anywhere.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            Spacer()

            // Sign in buttons
            VStack(spacing: 16) {
                SignInWithAppleButton { request in
                    request.requestedScopes = [.email, .fullName]
                } onCompletion: { result in
                    switch result {
                    case .success:
                        Task {
                            do {
                                try await authService.signInWithApple()
                            } catch {
                                showError = true
                            }
                        }
                    case .failure:
                        showError = true
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal)

                // Anonymous sign in for testing
                #if DEBUG
                Button("Continue as Guest") {
                    Task {
                        try? await authService.signInAnonymously()
                    }
                }
                .foregroundColor(.secondary)
                #endif
            }

            Spacer()
        }
        .alert("Sign In Failed", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text("Please try again.")
        }
    }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): add AuthView with Sign in with Apple"
```

---

### Task 8.3: Update Main ContentView

**Files:**
- Modify: `VoiceNotes/ContentView.swift`

**Step 1: Write the implementation**

Replace `ContentView.swift`:
```swift
// ABOUTME: Root view for the iOS Voice Notes app.
// ABOUTME: Shows auth or notes list based on authentication state.

import SwiftUI

struct ContentView: View {

    @StateObject private var authService = AuthService()
    @StateObject private var uploadQueue: UploadQueueManager

    init() {
        let auth = AuthService()
        _authService = StateObject(wrappedValue: auth)
        _uploadQueue = StateObject(wrappedValue: UploadQueueManager(authService: auth))
    }

    var body: some View {
        Group {
            if authService.isAuthenticated {
                NotesListView()
            } else {
                AuthView()
            }
        }
        .environmentObject(authService)
        .environmentObject(uploadQueue)
        .onAppear {
            // Connect upload queue to session manager
            PhoneSessionManager.shared.delegate = uploadQueue
        }
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(ios): wire up ContentView with auth flow and upload queue"
```

---

## Phase 9: Security Rules

### Task 9.1: Create Firestore Security Rules

**Files:**
- Create: `firebase/firestore.rules`

**Step 1: Write the rules**

Create `firebase/firestore.rules`:
```
// ABOUTME: Firestore security rules for Voice Notes app.
// ABOUTME: Ensures users can only access their own data.

rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // Users can only read/write their own user document
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;

      // Notes subcollection
      match /notes/{noteId} {
        allow read, write: if request.auth != null && request.auth.uid == userId;
      }
    }

    // Deny all other access
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(firebase): add Firestore security rules"
```

---

### Task 9.2: Create Storage Security Rules

**Files:**
- Create: `firebase/storage.rules`

**Step 1: Write the rules**

Create `firebase/storage.rules`:
```
// ABOUTME: Firebase Storage security rules for Voice Notes app.
// ABOUTME: Ensures users can only access their own audio files.

rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    // Users can only read/write files in their own directory
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Deny all other access
    match /{allPaths=**} {
      allow read, write: if false;
    }
  }
}
```

**Step 2: Commit**

```bash
git add .
git commit -m "feat(firebase): add Storage security rules"
```

---

## Phase 10: Final Integration

### Task 10.1: Add App Capabilities

**Files:**
- Modify: Xcode project capabilities

**Step 1: Add required capabilities**

In Xcode, select iOS target → Signing & Capabilities:
1. Add "Sign in with Apple"
2. Add "Background Modes" → Enable "Background fetch" (for upload processing)

For Watch target:
1. Ensure WatchConnectivity is enabled (automatic with watch companion)

**Step 2: Commit**

```bash
git add .
git commit -m "chore: add Sign in with Apple and Background Modes capabilities"
```

---

### Task 10.2: Integration Test on Devices

**Files:**
- No code changes - testing only

**Step 1: Build and run on physical devices**

1. Connect iPhone and Apple Watch
2. Build iOS app to iPhone
3. Build watchOS app to Watch
4. Test recording flow end-to-end

**Step 2: Verify acceptance criteria**

1. [ ] Record 5-60s clip on Watch
2. [ ] Clip transfers to iPhone without opening app
3. [ ] iPhone uploads to Firebase
4. [ ] Watch shows "Sent" after ack
5. [ ] Offline queuing works

---

### Task 10.3: Final Commit and Tag

**Step 1: Final commit**

```bash
git add .
git commit -m "chore: MVP complete - Voice Notes Watch app with Firebase sync"
git tag v0.1.0
```

---

## Summary

This plan implements the Voice Notes MVP with:

- **Watch App**: Recording, local queue, WatchConnectivity transfer
- **iOS App**: Receive files, durable upload queue, Firebase integration, notes list UI
- **Firebase**: Auth, Storage, Firestore with security rules

Total tasks: ~25 bite-sized steps following TDD principles where applicable.

Key reliability guarantees:
- Watch retains files until ack
- iPhone retains files until upload confirmed
- Both queues persist across restarts
- Retry logic with exponential backoff
