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

    /// Audio settings optimized for voice recording on watchOS
    /// Uses AAC codec at 22kHz sample rate, mono channel, medium quality
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
            self.recordingsDirectory = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Recordings")
        }

        // Ensure directory exists
        try? FileManager.default.createDirectory(
            at: self.recordingsDirectory,
            withIntermediateDirectories: true
        )
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
                throw AudioRecorderError.recordingFailed(
                    NSError(domain: "AudioRecorder", code: -1, userInfo: nil)
                )
            }

            self.audioRecorder = recorder
            self.currentNoteId = noteId
            self.currentRecordingURL = fileURL
            self.recordingStartTime = Date()
            self.isRecording = true
            self.recordingDuration = 0

            // Start duration timer
            startDurationTimer()

        } catch let error as AudioRecorderError {
            throw error
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
        metadata.watchModel = getDeviceModel()
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

    private func getDeviceModel() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        return String(cString: machine)
    }
}
