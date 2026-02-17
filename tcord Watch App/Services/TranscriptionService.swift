// ABOUTME: Handles on-device speech-to-text transcription on Apple Watch.
// ABOUTME: Uses Apple Speech framework to transcribe audio files immediately after recording.

import Foundation

#if canImport(Speech)
import Speech
#endif

/// Errors that can occur during transcription
enum TranscriptionError: Error, LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case transcriptionFailed(Error)
    case noResult

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized"
        case .recognizerUnavailable:
            return "Speech recognizer unavailable for this language"
        case .transcriptionFailed(let error):
            return "Transcription failed: \(error.localizedDescription)"
        case .noResult:
            return "No transcription result"
        }
    }
}

/// Result of a successful transcription
struct TranscriptionResult {
    let text: String
    let language: String
}

/// Service for transcribing audio files using Apple Speech framework
final class TranscriptionService {

#if canImport(Speech)
    private var recognizer: SFSpeechRecognizer?

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale.current)
    }

    /// Request authorization for speech recognition
    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Transcribe audio file to text
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        // Check authorization
        let authStatus = SFSpeechRecognizer.authorizationStatus()
        guard authStatus == .authorized else {
            if authStatus == .notDetermined {
                let granted = await requestAuthorization()
                guard granted else {
                    throw TranscriptionError.notAuthorized
                }
            } else {
                throw TranscriptionError.notAuthorized
            }
        }

        // Check recognizer availability
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true

        // Perform recognition
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError.transcriptionFailed(error))
                    return
                }

                guard let result = result, result.isFinal else {
                    return
                }

                let transcription = result.bestTranscription.formattedString
                let language = recognizer.locale.identifier

                continuation.resume(returning: TranscriptionResult(
                    text: transcription,
                    language: language
                ))
            }
        }
    }
#else
    init() {}

    /// Speech framework unavailable - transcription will be handled by the iPhone
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        throw TranscriptionError.recognizerUnavailable
    }
#endif
}
