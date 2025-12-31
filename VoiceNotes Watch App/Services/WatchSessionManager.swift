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

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
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
    func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        if let error = error {
            print("File transfer failed: \(error)")
            // Note: transfer will be retried by the system
        } else {
            print("File transfer completed successfully")
        }
    }
}
