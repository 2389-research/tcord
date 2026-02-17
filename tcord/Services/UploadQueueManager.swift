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
    private let maxBackoffSeconds: Double = 30
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

                        // Exponential backoff with cap
                        let delay = min(pow(2.0, Double(queue[currentIndex].retryCount)), maxBackoffSeconds)
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
