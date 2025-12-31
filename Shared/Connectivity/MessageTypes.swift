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
