import Foundation
import os

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

    /// Bookmarks deleted locally that need to be pushed as deletions to the web.
    private var pendingDeletions: [String] = [] // lowercased UUID strings

    private let pendingDeletionsKey = "CiderSyncPendingDeletions"

    private init() {
        pendingDeletions = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
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

    // MARK: - Manual trigger

    func syncNow() {
        performSync()
    }

    // MARK: - Core sync

    private func performSync() {
        guard !isSyncing else { return }

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
            } catch {
                lastError = error.localizedDescription
                logger.error("Sync failed: \(error.localizedDescription)")
            }
            isSyncing = false
        }
    }

    // MARK: - Push local bookmarks to web

    private func push(config: CiderConfig) async throws {
        let bookmarks = BookmarksStorage.shared.bookmarks
        guard !bookmarks.isEmpty else { return }

        let payload = bookmarks.map { bookmark -> [String: Any] in
            var dict: [String: Any] = [
                "ciderSyncId": bookmark.id.uuidString.lowercased(),
                "title": bookmark.title,
                "urlString": bookmark.urlString,
                "tags": bookmark.tags,
                "createdAt": bookmark.createdAt.timeIntervalSince1970 * 1000,
                "updatedAt": bookmark.updatedAt.timeIntervalSince1970 * 1000,
                "deleted": false,
            ]
            if !bookmark.notes.isEmpty {
                dict["notes"] = bookmark.notes
            }
            if let url = bookmark.thumbnailRemoteURLString {
                dict["thumbnailRemoteUrl"] = url
            }
            if let summary = bookmark.aiSummary {
                dict["aiSummary"] = summary
            }
            if let colors = bookmark.dominantColors {
                dict["dominantColors"] = colors
            }
            return dict
        }

        let body = try JSONSerialization.data(withJSONObject: ["bookmarks": payload])
        let _ = try await syncRequest(config: config, path: "/api/sync/push", body: body)
    }

    // MARK: - Push deletions to web

    private func pushDeletions(config: CiderConfig) async throws {
        guard !pendingDeletions.isEmpty else { return }

        let now = Date().timeIntervalSince1970 * 1000
        let payload = pendingDeletions.map { syncId -> [String: Any] in
            [
                "ciderSyncId": syncId,
                "title": "",
                "urlString": "",
                "tags": [String](),
                "createdAt": now,
                "updatedAt": now,
                "deleted": true,
                "deletedAt": now,
            ]
        }

        let body = try JSONSerialization.data(withJSONObject: ["bookmarks": payload])
        let _ = try await syncRequest(config: config, path: "/api/sync/push", body: body)

        // Clear pending deletions after successful push
        pendingDeletions.removeAll()
        UserDefaults.standard.set(pendingDeletions, forKey: pendingDeletionsKey)
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
                        dominantColors: dict["dominantColors"] as? [String]
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
                        updatedAt: remoteUpdatedAt
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

        if httpResponse.statusCode == 401 {
            throw SyncError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw SyncError.serverError(httpResponse.statusCode)
        }

        return data
    }
}

enum SyncError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case serverError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid sync URL"
        case .invalidResponse:
            "Invalid server response"
        case .unauthorized:
            "Sync token is invalid or revoked"
        case .serverError(let code):
            "Server error (\(code))"
        }
    }
}
