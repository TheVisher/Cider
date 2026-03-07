import Foundation
import os

// MARK: - Codable push structs (only fields Convex accepts)

/// Maps a local Bookmark to only the fields the Convex sync.ts push endpoint accepts.
private struct SyncPushBookmark: Encodable {
    let ciderSyncId: String
    let title: String
    let urlString: String
    let notes: String?
    let tags: [String]
    let thumbnailRemoteUrl: String?
    let aiSummary: String?
    let dominantColors: [String]?
    let createdAt: Double
    let updatedAt: Double
    let deleted: Bool
    let deletedAt: Double?
    let folderSyncId: String?

    init(from bookmark: Bookmark) {
        ciderSyncId = bookmark.id.uuidString.lowercased()
        title = bookmark.title
        urlString = bookmark.urlString
        notes = bookmark.notes.isEmpty ? nil : bookmark.notes
        tags = bookmark.tags
        thumbnailRemoteUrl = bookmark.thumbnailRemoteURLString
        aiSummary = bookmark.aiSummary
        dominantColors = bookmark.dominantColors
        createdAt = bookmark.createdAt.timeIntervalSince1970 * 1000
        updatedAt = bookmark.updatedAt.timeIntervalSince1970 * 1000
        deleted = false
        deletedAt = nil
        folderSyncId = bookmark.folderID?.uuidString.lowercased()
    }

    /// Tombstone for a deleted bookmark.
    init(deletedSyncId: String, nowMs: Double) {
        ciderSyncId = deletedSyncId
        title = ""
        urlString = ""
        notes = nil
        tags = []
        thumbnailRemoteUrl = nil
        aiSummary = nil
        dominantColors = nil
        createdAt = nowMs
        updatedAt = nowMs
        deleted = true
        deletedAt = nowMs
        folderSyncId = nil
    }
}

/// Maps a local Folder to only the fields the Convex sync.ts push endpoint accepts.
private struct SyncPushFolder: Encodable {
    let ciderSyncId: String
    let name: String
    let icon: String?
    let parentSyncId: String?
    let createdAt: Double
    let updatedAt: Double
    let deleted: Bool
    let deletedAt: Double?

    init(from folder: Folder) {
        ciderSyncId = folder.id.uuidString.lowercased()
        name = folder.name
        icon = folder.icon
        parentSyncId = folder.parentID?.uuidString.lowercased()
        createdAt = folder.createdAt.timeIntervalSince1970 * 1000
        updatedAt = folder.updatedAt.timeIntervalSince1970 * 1000
        deleted = false
        deletedAt = nil
    }

    /// Tombstone for a deleted folder.
    init(deletedSyncId: String, nowMs: Double) {
        ciderSyncId = deletedSyncId
        name = ""
        icon = nil
        parentSyncId = nil
        createdAt = nowMs
        updatedAt = nowMs
        deleted = true
        deletedAt = nowMs
    }
}

private struct SyncPushBody: Encodable {
    let bookmarks: [SyncPushBookmark]
    let folders: [SyncPushFolder]?
}

/// Handles bidirectional sync between local Cider bookmarks and Cider Web (Convex).
/// Entirely optional — only runs when the user has configured a sync token.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    private var timer: Timer?
    private let logger = Logger(subsystem: "com.cider.app", category: "Sync")

    /// How often to auto-sync (seconds).
    private let syncInterval: TimeInterval = 5

    /// Consecutive failure count for backoff.
    private var consecutiveFailures = 0

    /// Bookmarks deleted locally that need to be pushed as deletions to the web.
    private var pendingDeletions: [String] = [] // lowercased UUID strings

    /// Folders deleted locally that need to be pushed as deletions to the web.
    private var pendingFolderDeletions: [String] = [] // lowercased UUID strings

    private let pendingDeletionsKey = "CiderSyncPendingDeletions"
    private let pendingFolderDeletionsKey = "CiderSyncPendingFolderDeletions"

    private init() {
        pendingDeletions = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        pendingFolderDeletions = UserDefaults.standard.stringArray(forKey: pendingFolderDeletionsKey) ?? []
    }

    // MARK: - Lifecycle

    func startIfEnabled() {
        let config = CiderConfig.load()
        guard config.syncEnabled, !config.syncToken.isEmpty, !config.syncURL.isEmpty else {
            stop()
            return
        }

        logger.info("Sync enabled, starting periodic sync")
        lastError = nil
        consecutiveFailures = 0
        performSync()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performSync()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        logger.info("Sync stopped")
    }

    // MARK: - Deletion tracking

    /// Called by BookmarksStorage when a bookmark is removed while sync is enabled.
    func trackDeletion(of bookmarkID: UUID) {
        let syncId = bookmarkID.uuidString.lowercased()
        guard !pendingDeletions.contains(syncId) else { return }
        pendingDeletions.append(syncId)
        UserDefaults.standard.set(pendingDeletions, forKey: pendingDeletionsKey)
    }

    /// Called when a bookmark is restored from trash — cancel any pending deletion.
    func cancelDeletion(of bookmarkID: UUID) {
        let syncId = bookmarkID.uuidString.lowercased()
        pendingDeletions.removeAll { $0 == syncId }
        UserDefaults.standard.set(pendingDeletions, forKey: pendingDeletionsKey)
    }

    // MARK: - Folder deletion tracking

    /// Called by BookmarksStorage when a folder is deleted while sync is enabled.
    func trackFolderDeletion(of folderID: UUID) {
        let syncId = folderID.uuidString.lowercased()
        guard !pendingFolderDeletions.contains(syncId) else { return }
        pendingFolderDeletions.append(syncId)
        UserDefaults.standard.set(pendingFolderDeletions, forKey: pendingFolderDeletionsKey)
    }

    // MARK: - Manual trigger

    func syncNow() {
        performSync()
    }

    // MARK: - Core sync

    private func performSync() {
        guard !isSyncing else { return }

        // Back off after repeated failures: pause sync after 3+ consecutive errors
        if consecutiveFailures >= 3 {
            logger.warning("Sync paused after \(self.consecutiveFailures) consecutive failures")
            return
        }

        let config = CiderConfig.load()
        guard config.syncEnabled, !config.syncToken.isEmpty, !config.syncURL.isEmpty else { return }

        isSyncing = true
        lastError = nil

        Task {
            do {
                try await push(config: config)
                try await pushDeletions(config: config)
                try await pull(config: config)
                lastSyncedAt = Date()
                lastError = nil
                consecutiveFailures = 0
            } catch let error as SyncError {
                consecutiveFailures += 1
                lastError = error.localizedDescription
                switch error {
                case .unauthorized:
                    logger.error("Sync auth failed — stopping sync. Check your sync token.")
                    stop()
                case .validationError(let body):
                    logger.error("Sync validation error (400): \(body)")
                case .serverError(let code):
                    logger.error("Sync server error (\(code)), failure #\(self.consecutiveFailures)")
                default:
                    logger.error("Sync failed: \(error.localizedDescription)")
                }
            } catch {
                consecutiveFailures += 1
                lastError = error.localizedDescription
                logger.error("Sync failed: \(error.localizedDescription)")
            }
            isSyncing = false
        }
    }

    // MARK: - Push local bookmarks + folders to web (dirty-only)

    private func push(config: CiderConfig) async throws {
        let storage = BookmarksStorage.shared
        let lastPushDate = Date(timeIntervalSince1970: config.lastSuccessfulPushAt)

        // Only push bookmarks modified since last successful push
        let dirtyBookmarks = storage.bookmarks.filter { $0.updatedAt > lastPushDate }
        let dirtyFolders = storage.folders.filter { $0.updatedAt > lastPushDate }

        guard !dirtyBookmarks.isEmpty || !dirtyFolders.isEmpty else {
            logger.debug("Push: 0 dirty bookmarks, 0 dirty folders — skipping")
            return
        }

        logger.info("Push: \(dirtyBookmarks.count) bookmark(s), \(dirtyFolders.count) folder(s)")

        let bookmarkPayload = dirtyBookmarks.map { SyncPushBookmark(from: $0) }
        let folderPayload = dirtyFolders.isEmpty ? nil : dirtyFolders.map { SyncPushFolder(from: $0) }

        let pushBody = SyncPushBody(bookmarks: bookmarkPayload, folders: folderPayload)
        let body = try JSONEncoder().encode(pushBody)
        let _ = try await syncRequest(config: config, path: "/api/sync/push", body: body)

        // Update lastSuccessfulPushAt after successful push
        var updatedConfig = CiderConfig.load()
        updatedConfig.lastSuccessfulPushAt = Date().timeIntervalSince1970
        updatedConfig.save()
    }

    // MARK: - Push deletions to web

    private func pushDeletions(config: CiderConfig) async throws {
        guard !pendingDeletions.isEmpty || !pendingFolderDeletions.isEmpty else { return }

        let now = Date().timeIntervalSince1970 * 1000

        let bookmarkPayload = pendingDeletions.map { SyncPushBookmark(deletedSyncId: $0, nowMs: now) }
        let folderPayload = pendingFolderDeletions.isEmpty
            ? nil
            : pendingFolderDeletions.map { SyncPushFolder(deletedSyncId: $0, nowMs: now) }

        let pushBody = SyncPushBody(bookmarks: bookmarkPayload, folders: folderPayload)
        let body = try JSONEncoder().encode(pushBody)
        let _ = try await syncRequest(config: config, path: "/api/sync/push", body: body)

        // Clear pending deletions after successful push
        pendingDeletions.removeAll()
        UserDefaults.standard.set(pendingDeletions, forKey: pendingDeletionsKey)
        pendingFolderDeletions.removeAll()
        UserDefaults.standard.set(pendingFolderDeletions, forKey: pendingFolderDeletionsKey)
    }

    // MARK: - Pull web bookmarks to local

    private func pull(config: CiderConfig) async throws {
        let since = config.lastSyncTimestamp
        let body = try JSONSerialization.data(withJSONObject: ["since": since])
        let data = try await syncRequest(config: config, path: "/api/sync/pull", body: body)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bookmarkDicts = json["bookmarks"] as? [[String: Any]],
              let serverTime = json["serverTime"] as? Double else {
            return
        }

        let storage = BookmarksStorage.shared

        // --- Pull folders first (bookmarks may reference them) ---
        if let folderDicts = json["folders"] as? [[String: Any]] {
            for dict in folderDicts {
                guard let syncId = dict["ciderSyncId"] as? String,
                      let name = dict["name"] as? String,
                      let updatedAtMs = dict["updatedAt"] as? Double else {
                    continue
                }

                let syncIdLower = syncId.lowercased()
                let remoteUpdatedAt = Date(timeIntervalSince1970: updatedAtMs / 1000)
                let isDeleted = dict["deleted"] as? Bool ?? false
                let icon = dict["icon"] as? String
                let parentSyncId = (dict["parentSyncId"] as? String)?.lowercased()

                // Resolve parentSyncId to local UUID
                let parentID: UUID? = if let parentSyncId {
                    storage.folders.first(where: { $0.id.uuidString.lowercased() == parentSyncId })?.id
                } else {
                    nil
                }

                if let localIndex = storage.folders.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                    let local = storage.folders[localIndex]

                    if isDeleted {
                        storage.deleteFolderFromSync(local.id)
                        continue
                    }

                    if remoteUpdatedAt > local.updatedAt {
                        storage.updateFolderFromSync(
                            folderID: local.id,
                            name: name,
                            icon: icon,
                            parentID: parentID,
                            remoteUpdatedAt: remoteUpdatedAt
                        )
                    }
                } else if !isDeleted {
                    if let uuid = UUID(uuidString: syncId) {
                        let createdAtMs = dict["createdAt"] as? Double ?? updatedAtMs
                        storage.addFolderFromSync(
                            id: uuid,
                            name: name,
                            icon: icon,
                            parentID: parentID,
                            createdAt: Date(timeIntervalSince1970: createdAtMs / 1000),
                            updatedAt: remoteUpdatedAt
                        )
                    }
                }
            }
        }

        // --- Pull bookmarks ---
        for dict in bookmarkDicts {
            guard let syncId = dict["ciderSyncId"] as? String,
                  let title = dict["title"] as? String,
                  let urlString = dict["urlString"] as? String,
                  let updatedAtMs = dict["updatedAt"] as? Double else {
                continue
            }

            let syncIdLower = syncId.lowercased()
            let remoteUpdatedAt = Date(timeIntervalSince1970: updatedAtMs / 1000)
            let isDeleted = dict["deleted"] as? Bool ?? false

            // Resolve folderSyncId to local folder UUID
            let folderID: UUID? = if let folderSyncId = (dict["folderSyncId"] as? String)?.lowercased() {
                storage.folders.first(where: { $0.id.uuidString.lowercased() == folderSyncId })?.id
            } else {
                nil
            }

            // Check if we already have this bookmark locally (case-insensitive UUID match)
            if let localIndex = storage.bookmarks.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                let local = storage.bookmarks[localIndex]

                if isDeleted {
                    // Move to desktop trash so the user can restore if needed
                    storage.trashFromSync(local)
                    continue
                }

                // Last-write-wins: only update if remote is newer
                if remoteUpdatedAt > local.updatedAt {
                    storage.updateFromSync(
                        bookmarkID: local.id,
                        title: title,
                        urlString: urlString,
                        notes: dict["notes"] as? String ?? "",
                        tags: dict["tags"] as? [String] ?? [],
                        thumbnailRemoteURLString: dict["thumbnailRemoteUrl"] as? String,
                        aiSummary: dict["aiSummary"] as? String,
                        dominantColors: dict["dominantColors"] as? [String],
                        folderID: folderID,
                        remoteUpdatedAt: remoteUpdatedAt
                    )
                }
            } else if !isDeleted {
                // New bookmark from web — create locally with the sync UUID as its ID
                if let uuid = UUID(uuidString: syncId) {
                    let createdAtMs = dict["createdAt"] as? Double ?? updatedAtMs
                    storage.addFromSync(
                        id: uuid,
                        title: title,
                        urlString: urlString,
                        notes: dict["notes"] as? String ?? "",
                        tags: dict["tags"] as? [String] ?? [],
                        thumbnailRemoteURLString: dict["thumbnailRemoteUrl"] as? String,
                        aiSummary: dict["aiSummary"] as? String,
                        dominantColors: dict["dominantColors"] as? [String],
                        createdAt: Date(timeIntervalSince1970: createdAtMs / 1000),
                        updatedAt: remoteUpdatedAt,
                        folderID: folderID
                    )
                }
            }
        }

        // Save the server timestamp so next pull is incremental
        var updatedConfig = config
        updatedConfig.lastSyncTimestamp = serverTime
        updatedConfig.save()
    }

    // MARK: - HTTP

    private func syncRequest(config: CiderConfig, path: String, body: Data) async throws -> Data {
        guard let url = URL(string: config.syncURL + path) else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.syncToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw SyncError.unauthorized
        case 400:
            let responseBody = String(data: data, encoding: .utf8) ?? "<unreadable>"
            throw SyncError.validationError(responseBody)
        default:
            throw SyncError.serverError(httpResponse.statusCode)
        }
    }
}

enum SyncError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case validationError(String)
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid sync URL"
        case .invalidResponse:
            "Invalid server response"
        case .unauthorized:
            "Sync token is invalid or revoked"
        case .validationError:
            "Server rejected the request (400)"
        case .serverError(let code):
            "Server error (\(code))"
        }
    }
}
