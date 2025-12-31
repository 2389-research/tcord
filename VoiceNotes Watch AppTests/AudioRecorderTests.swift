// ABOUTME: Tests for the AudioRecorder service on watchOS.
// ABOUTME: Verifies recording lifecycle, file creation, and duration tracking.

import XCTest
@testable import VoiceNotes_Watch_App

final class AudioRecorderTests: XCTestCase {

    var recorder: AudioRecorder!
    var testDirectory: URL!

    @MainActor
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

    @MainActor
    func testInitialStateIsIdle() {
        XCTAssertFalse(recorder.isRecording)
        XCTAssertNil(recorder.currentRecordingURL)
    }

    @MainActor
    func testAudioFileURLGeneration() {
        let noteId = UUID()
        let url = recorder.audioFileURL(for: noteId)
        XCTAssertEqual(url.lastPathComponent, "\(noteId.uuidString).m4a")
        XCTAssertTrue(url.path.contains(testDirectory.path))
    }

    @MainActor
    func testAudioFileURLUsesCorrectDirectory() {
        let noteId = UUID()
        let url = recorder.audioFileURL(for: noteId)
        XCTAssertEqual(url.deletingLastPathComponent(), testDirectory)
    }

    @MainActor
    func testRecordingDurationStartsAtZero() {
        XCTAssertEqual(recorder.recordingDuration, 0)
    }

    @MainActor
    func testCancelRecordingWhenNotRecordingDoesNotThrow() {
        // Should not throw or crash when canceling while not recording
        recorder.cancelRecording()
        XCTAssertFalse(recorder.isRecording)
    }

    @MainActor
    func testDeleteRecordingRemovesFile() throws {
        // Create a test file
        let noteId = UUID()
        let url = recorder.audioFileURL(for: noteId)
        try "test".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        // Delete it
        recorder.deleteRecording(noteId: noteId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    @MainActor
    func testDeleteNonExistentRecordingDoesNotThrow() {
        // Should not throw when deleting non-existent file
        let noteId = UUID()
        recorder.deleteRecording(noteId: noteId)
        // If we get here without throwing, the test passes
    }
}
