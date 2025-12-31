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

    /// Get the file URL for a note in the inbox
    func fileURL(for noteId: UUID) -> URL {
        inboxDirectory.appendingPathComponent("\(noteId.uuidString).m4a")
    }

    /// Delete a file from the inbox after successful upload
    func deleteFile(for noteId: UUID) {
        let url = fileURL(for: noteId)
        try? FileManager.default.removeItem(at: url)
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
