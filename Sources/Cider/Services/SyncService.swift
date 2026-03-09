import Combine
import ConvexMobile
import Foundation
import os

// MARK: - Convex pull response types

private struct SyncAuthResponse: Decodable {
    let userId: String
}

private struct SyncChangeSignal: Decodable {
    let lastChange: Double
}

private struct SyncPullResponse: Decodable {
    let bookmarks: [SyncPulledBookmark]
    let folders: [SyncPulledFolder]
    let notes: [SyncPulledNote]
    let serverTime: Double
}

private struct SyncPulledBookmark: Decodable {
    let ciderSyncId: String?
    let title: String
    let urlString: String
    let notes: String?
    let tags: [String]?
    let thumbnailRemoteUrl: String?
    let aiSummary: String?
    let dominantColors: [String]?
    let createdAt: Double
    let updatedAt: Double
    let deleted: Bool?
    let deletedAt: Double?
    let folderSyncId: String?
}

private struct SyncPulledFolder: Decodable {
    let ciderSyncId: String?
    let name: String
    let icon: String?
    let parentSyncId: String?
    let createdAt: Double
    let updatedAt: Double
    let deleted: Bool?
    let deletedAt: Double?
}

private struct SyncPulledNote: Decodable {
    let ciderSyncId: String?
    let title: String
    let content: String?
    let tags: [String]?
    let isPinned: Bool?
    let folderSyncId: String?
    let createdAt: Double
    let updatedAt: Double
    let deleted: Bool?
    let deletedAt: Double?
}

private struct SyncPushResponse: Decodable {
    let serverTime: Double
}

// MARK: - SyncService

/// Handles bidirectional sync between local Cider data and Cider Web (Convex).
/// Uses the Convex Swift SDK for real-time WebSocket subscriptions + actions.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    private let logger = Logger(subsystem: "com.cider.app", category: "Sync")

    /// Convex client for WebSocket-based sync.
    private var convexClient: ConvexClient?

    /// Combine subscription for the reactive change signal.
    private var changeSignalCancellable: AnyCancellable?

    /// The last known server change timestamp (ms since epoch).
    /// When the signal reports a newer value, we trigger a pull.
    private var lastKnownChange: Double = 0

    /// Consecutive failure count for backoff.
    private var consecutiveFailures = 0

    /// Periodic timer to check for dirty notes (notes can't use event-driven
    /// push because their save paths have async side effects that create loops).
    private var dirtyNoteCheckTimer: Timer?

    /// Debounce task for pulls — when someone is actively editing on web/mobile,
    /// the changeSignal fires on every keystroke. We wait for it to stabilize.
    private var pullDebounceTask: Task<Void, Never>?

    // MARK: - Deletion tracking

    /// Bookmarks deleted locally that need to be pushed as deletions to the web.
    private var pendingDeletions: [String] = []
    /// Folders deleted locally that need to be pushed as deletions to the web.
    private var pendingFolderDeletions: [String] = []
    /// Notes deleted locally that need to be pushed as deletions to the web.
    private var pendingNoteDeletions: [String] = []

    private let pendingDeletionsKey = "CiderSyncPendingDeletions"
    private let pendingFolderDeletionsKey = "CiderSyncPendingFolderDeletions"
    private let pendingNoteDeletionsKey = "CiderSyncPendingNoteDeletions"

    private init() {
        pendingDeletions = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        pendingFolderDeletions = UserDefaults.standard.stringArray(forKey: pendingFolderDeletionsKey) ?? []
        pendingNoteDeletions = UserDefaults.standard.stringArray(forKey: pendingNoteDeletionsKey) ?? []
    }

    // MARK: - Lifecycle

    func startIfEnabled() {
        let config = CiderConfig.load()
        migrateSyncTokenToKeychainIfNeeded()
        let token = Self.loadSyncToken()
        guard config.syncEnabled, !token.isEmpty, !config.syncURL.isEmpty else {
            stop()
            return
        }

        // Derive Convex deployment URL from the site URL
        let deploymentURL = Self.deploymentURL(from: config.syncURL)
        guard !deploymentURL.isEmpty else {
            logger.error("Could not derive Convex deployment URL from \(config.syncURL)")
            stop()
            return
        }

        logger.info("Sync enabled, connecting via Convex SDK")
        lastError = nil
        consecutiveFailures = 0
        lastKnownChange = config.lastSyncTimestamp

        // Create a single ConvexClient for the session
        let client = ConvexClient(deploymentUrl: deploymentURL)
        convexClient = client

        // Authenticate first, then subscribe to changeSignal with userId.
        // This avoids the subscription depending on the syncTokens table.
        // Capture client before Task to avoid main-actor-isolation send warning.
        let authClient = client
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let authResult: SyncAuthResponse = try await authClient.action(
                    "sync:authenticate", with: ["token": token]
                )
                self.subscribeToChanges(client: authClient, userId: authResult.userId, token: token)
                self.performPush(token: token)
            } catch {
                self.logger.error("Authentication failed: \(error.localizedDescription)")
                self.lastError = error.localizedDescription
                self.stop()
            }
        }

        // Periodic dirty-note check. Notes can't use event-driven push
        // (saveIndex/save paths have async side effects — directory watcher,
        // TipTap editor round-trip — that create feedback loops). Instead,
        // check for dirty notes every 30 seconds.
        dirtyNoteCheckTimer?.invalidate()
        dirtyNoteCheckTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pushAfterLocalChange()
            }
        }
    }

    func stop() {
        changeSignalCancellable?.cancel()
        changeSignalCancellable = nil
        dirtyNoteCheckTimer?.invalidate()
        dirtyNoteCheckTimer = nil
        pullDebounceTask?.cancel()
        pullDebounceTask = nil
        convexClient = nil
        logger.info("Sync stopped")
    }

    // MARK: - Subscription

    private func subscribeToChanges(client: ConvexClient, userId: String, token: String) {
        changeSignalCancellable = client.subscribe(
            to: "sync:changeSignal",
            with: ["userId": userId],
            yielding: SyncChangeSignal.self
        )
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { [weak self] completion in
                guard let self else { return }
                if case .failure(let error) = completion {
                    self.logger.error("Change signal subscription failed: \(error.localizedDescription)")
                    self.lastError = error.localizedDescription
                }
            },
            receiveValue: { [weak self] signal in
                guard let self else { return }
                if signal.lastChange > self.lastKnownChange {
                    self.lastKnownChange = signal.lastChange
                    self.debouncePull(token: token)
                }
            }
        )
    }

    // MARK: - Deletion tracking (public API for BookmarksStorage/NotesStorage)

    func trackDeletion(of bookmarkID: UUID) {
        let syncId = bookmarkID.uuidString.lowercased()
        guard !pendingDeletions.contains(syncId) else { return }
        pendingDeletions.append(syncId)
        UserDefaults.standard.set(pendingDeletions, forKey: pendingDeletionsKey)
        pushAfterLocalChange()
    }

    func cancelDeletion(of bookmarkID: UUID) {
        let syncId = bookmarkID.uuidString.lowercased()
        pendingDeletions.removeAll { $0 == syncId }
        UserDefaults.standard.set(pendingDeletions, forKey: pendingDeletionsKey)
    }

    func trackNoteDeletion(of noteID: UUID) {
        let syncId = noteID.uuidString.lowercased()
        guard !pendingNoteDeletions.contains(syncId) else { return }
        pendingNoteDeletions.append(syncId)
        UserDefaults.standard.set(pendingNoteDeletions, forKey: pendingNoteDeletionsKey)
        pushAfterLocalChange()
    }

    func trackFolderDeletion(of folderID: UUID) {
        let syncId = folderID.uuidString.lowercased()
        guard !pendingFolderDeletions.contains(syncId) else { return }
        pendingFolderDeletions.append(syncId)
        UserDefaults.standard.set(pendingFolderDeletions, forKey: pendingFolderDeletionsKey)
        pushAfterLocalChange()
    }

    // MARK: - Manual trigger

    func syncNow() {
        let token = Self.loadSyncToken()
        guard !token.isEmpty else { return }
        consecutiveFailures = 0
        performPush(token: token)
    }

    // MARK: - Push after local change (debounced)

    private var pushDebounceTask: Task<Void, Never>?

    /// Set to true while applying pull results to suppress re-triggering a push.
    private(set) var isApplyingRemoteChanges = false

    /// Called when local data changes to trigger a push after a brief debounce.
    func pushAfterLocalChange() {
        guard !isApplyingRemoteChanges else { return }
        pushDebounceTask?.cancel()
        pushDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let token = Self.loadSyncToken()
            guard !token.isEmpty else { return }
            self.performPush(token: token)
        }
    }

    // MARK: - Push

    private func performPush(token: String) {
        guard !isSyncing, let client = convexClient else { return }
        if consecutiveFailures >= 3 {
            logger.warning("Sync paused after \(self.consecutiveFailures) consecutive failures")
            return
        }

        let storage = BookmarksStorage.shared
        let notesStorage = NotesStorage.shared
        let config = CiderConfig.load()
        let lastPushDate = Date(timeIntervalSince1970: config.lastSuccessfulPushAt)

        // Dirty items
        let dirtyBookmarks = storage.bookmarks.filter { $0.updatedAt > lastPushDate }
        let dirtyFolders = storage.folders.filter { $0.updatedAt > lastPushDate }
        let dirtyNotes = notesStorage.notes.filter { $0.modifiedAt > lastPushDate }

        // Build combined bookmark payload (dirty + deletion tombstones)
        var bookmarkArgs: [[String: ConvexEncodable?]] = dirtyBookmarks.map { Self.bookmarkPayload(from: $0) }
        let now = Date().timeIntervalSince1970 * 1000
        for syncId in pendingDeletions {
            bookmarkArgs.append(Self.deletionTombstone(syncId: syncId, nowMs: now))
        }

        // Build folder payload
        var folderArgs: [[String: ConvexEncodable?]] = dirtyFolders.map { Self.folderPayload(from: $0) }
        for syncId in pendingFolderDeletions {
            folderArgs.append(Self.folderDeletionTombstone(syncId: syncId, nowMs: now))
        }

        // Build note payload
        var noteArgs: [[String: ConvexEncodable?]] = dirtyNotes.map { Self.notePayload(from: $0) }
        for syncId in pendingNoteDeletions {
            noteArgs.append(Self.noteDeletionTombstone(syncId: syncId, nowMs: now))
        }

        guard !bookmarkArgs.isEmpty || !folderArgs.isEmpty || !noteArgs.isEmpty else {
            logger.debug("Push: nothing to push")
            // Still do initial pull after startup
            performPull(token: token)
            return
        }

        logger.info("Push: \(dirtyBookmarks.count)+\(self.pendingDeletions.count) bookmark(s), \(dirtyFolders.count)+\(self.pendingFolderDeletions.count) folder(s), \(dirtyNotes.count)+\(self.pendingNoteDeletions.count) note(s)")

        isSyncing = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var args: [String: ConvexEncodable?] = [
                    "token": token,
                    "bookmarks": bookmarkArgs as [ConvexEncodable?],
                ]
                if !folderArgs.isEmpty {
                    args["folders"] = folderArgs as [ConvexEncodable?]
                }
                if !noteArgs.isEmpty {
                    args["notes"] = noteArgs as [ConvexEncodable?]
                }

                let result: SyncPushResponse = try await client.action("sync:push", with: args)

                // Clear pending deletions after successful push
                self.pendingDeletions.removeAll()
                UserDefaults.standard.set(self.pendingDeletions, forKey: self.pendingDeletionsKey)
                self.pendingFolderDeletions.removeAll()
                UserDefaults.standard.set(self.pendingFolderDeletions, forKey: self.pendingFolderDeletionsKey)
                self.pendingNoteDeletions.removeAll()
                UserDefaults.standard.set(self.pendingNoteDeletions, forKey: self.pendingNoteDeletionsKey)

                // Update lastSuccessfulPushAt
                var freshConfig = CiderConfig.load()
                freshConfig.lastSuccessfulPushAt = Date().timeIntervalSince1970
                freshConfig.save()

                self.consecutiveFailures = 0
                self.lastError = nil
                self.logger.info("Push succeeded (serverTime: \(result.serverTime))")

                // Use max of server time and client time to account for clock
                // skew. The pushed items' updatedAt is based on client time, so
                // if the client clock is ahead, the change signal would report a
                // lastChange higher than serverTime, re-triggering a pull.
                let clientTimeMs = Date().timeIntervalSince1970 * 1000
                let effectiveTime = max(result.serverTime, clientTimeMs)
                self.lastKnownChange = effectiveTime
                var syncConfig = CiderConfig.load()
                syncConfig.lastSyncTimestamp = effectiveTime
                syncConfig.save()

                self.isSyncing = false
            } catch {
                self.consecutiveFailures += 1
                self.lastError = error.localizedDescription
                self.logger.error("Push failed: \(error.localizedDescription)")
                self.isSyncing = false
            }
        }
    }

    // MARK: - Pull

    /// Debounce pull requests — when someone is actively editing on another
    /// client, the changeSignal fires on every save (~1-2s). We coalesce
    /// these into a single pull after the signal stabilizes.
    private func debouncePull(token: String) {
        pullDebounceTask?.cancel()
        pullDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self else { return }
            self.performPull(token: token)
        }
    }

    private func performPull(token: String) {
        guard !isSyncing, let client = convexClient else { return }

        isSyncing = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let config = CiderConfig.load()
                let args: [String: ConvexEncodable?] = [
                    "token": token,
                    "since": config.lastSyncTimestamp,
                ]

                let result: SyncPullResponse = try await client.action("sync:pull", with: args)

                self.isApplyingRemoteChanges = true
                self.applyPullResult(result)
                self.isApplyingRemoteChanges = false

                // Save timestamp for next incremental pull, using max of
                // server and client time to handle clock skew.
                let clientTimeMs = Date().timeIntervalSince1970 * 1000
                let effectiveTime = max(result.serverTime, clientTimeMs)
                var freshConfig = CiderConfig.load()
                freshConfig.lastSyncTimestamp = effectiveTime
                freshConfig.save()

                self.lastKnownChange = effectiveTime
                self.lastSyncedAt = Date()
                self.lastError = nil
                self.consecutiveFailures = 0
                self.logger.info("Pull succeeded: \(result.bookmarks.count) bookmark(s), \(result.folders.count) folder(s), \(result.notes.count) note(s)")
            } catch {
                self.consecutiveFailures += 1
                self.lastError = error.localizedDescription
                self.logger.error("Pull failed: \(error.localizedDescription)")
            }
            self.isSyncing = false
        }
    }

    // MARK: - Apply pull results to local storage

    private func applyPullResult(_ result: SyncPullResponse) {
        let storage = BookmarksStorage.shared

        // --- Folders first (bookmarks/notes may reference them) ---
        for folder in result.folders {
            guard let syncId = folder.ciderSyncId else { continue }

            let syncIdLower = syncId.lowercased()
            let remoteUpdatedAt = Date(timeIntervalSince1970: folder.updatedAt / 1000)
            let isDeleted = folder.deleted ?? false
            let parentSyncId = folder.parentSyncId?.lowercased()

            let parentID: UUID? = if let parentSyncId {
                storage.folders.first(where: { $0.id.uuidString.lowercased() == parentSyncId })?.id
            } else {
                nil
            }

            if let localIndex = storage.folders.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                let local = storage.folders[localIndex]
                if isDeleted {
                    storage.deleteFolderFromSync(local.id)
                } else if remoteUpdatedAt > local.updatedAt {
                    storage.updateFolderFromSync(
                        folderID: local.id, name: folder.name, icon: folder.icon,
                        parentID: parentID, remoteUpdatedAt: remoteUpdatedAt
                    )
                }
            } else if !isDeleted {
                if let uuid = UUID(uuidString: syncId) {
                    storage.addFolderFromSync(
                        id: uuid, name: folder.name, icon: folder.icon,
                        parentID: parentID,
                        createdAt: Date(timeIntervalSince1970: folder.createdAt / 1000),
                        updatedAt: remoteUpdatedAt
                    )
                }
            }
        }

        // --- Bookmarks ---
        for bookmark in result.bookmarks {
            guard let syncId = bookmark.ciderSyncId else { continue }

            let syncIdLower = syncId.lowercased()
            let remoteUpdatedAt = Date(timeIntervalSince1970: bookmark.updatedAt / 1000)
            let isDeleted = bookmark.deleted ?? false

            let folderID: UUID? = if let folderSyncId = bookmark.folderSyncId?.lowercased() {
                storage.folders.first(where: { $0.id.uuidString.lowercased() == folderSyncId })?.id
            } else {
                nil
            }

            if let localIndex = storage.bookmarks.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                let local = storage.bookmarks[localIndex]
                if isDeleted {
                    storage.trashFromSync(local)
                } else if remoteUpdatedAt > local.updatedAt {
                    storage.updateFromSync(
                        bookmarkID: local.id, title: bookmark.title,
                        urlString: bookmark.urlString,
                        notes: bookmark.notes ?? "",
                        tags: bookmark.tags ?? [],
                        thumbnailRemoteURLString: bookmark.thumbnailRemoteUrl,
                        aiSummary: bookmark.aiSummary,
                        dominantColors: bookmark.dominantColors,
                        folderID: folderID,
                        remoteUpdatedAt: remoteUpdatedAt
                    )
                }
            } else if !isDeleted {
                if let uuid = UUID(uuidString: syncId) {
                    storage.addFromSync(
                        id: uuid, title: bookmark.title,
                        urlString: bookmark.urlString,
                        notes: bookmark.notes ?? "",
                        tags: bookmark.tags ?? [],
                        thumbnailRemoteURLString: bookmark.thumbnailRemoteUrl,
                        aiSummary: bookmark.aiSummary,
                        dominantColors: bookmark.dominantColors,
                        createdAt: Date(timeIntervalSince1970: bookmark.createdAt / 1000),
                        updatedAt: remoteUpdatedAt,
                        folderID: folderID
                    )
                }
            }
        }

        // --- Notes ---
        let notesStorage = NotesStorage.shared
        for note in result.notes {
            guard let syncId = note.ciderSyncId else { continue }

            let syncIdLower = syncId.lowercased()
            let remoteUpdatedAt = Date(timeIntervalSince1970: note.updatedAt / 1000)
            let isDeleted = note.deleted ?? false
            let content = note.content ?? ""
            let isPinned = note.isPinned ?? false

            let folderID: UUID? = if let folderSyncId = note.folderSyncId?.lowercased() {
                storage.folders.first(where: { $0.id.uuidString.lowercased() == folderSyncId })?.id
            } else {
                nil
            }

            if let localIndex = notesStorage.notes.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                let local = notesStorage.notes[localIndex]
                if isDeleted {
                    notesStorage.deleteFromSync(local)
                } else if remoteUpdatedAt > local.modifiedAt {
                    // Skip no-op updates — pulling back what we just pushed
                    // would trigger the editor's contentChanged and loop.
                    let localContent = local.content.isEmpty ? notesStorage.loadContent(for: local) : local.content
                    if localContent == content
                        && local.title == note.title
                        && local.folderID == folderID
                        && local.isPinned == isPinned
                    {
                        continue
                    }
                    notesStorage.updateFromSync(
                        noteID: local.id, title: note.title, content: content,
                        folderID: folderID, isPinned: isPinned,
                        remoteUpdatedAt: remoteUpdatedAt
                    )
                }
            } else if !isDeleted {
                if let uuid = UUID(uuidString: syncId) {
                    notesStorage.addFromSync(
                        id: uuid, title: note.title, content: content,
                        folderID: folderID, isPinned: isPinned,
                        createdAt: Date(timeIntervalSince1970: note.createdAt / 1000),
                        updatedAt: remoteUpdatedAt
                    )
                }
            }
        }
    }

    // MARK: - Payload builders

    private static func bookmarkPayload(from bookmark: Bookmark) -> [String: ConvexEncodable?] {
        // Convex v.optional() means "field absent", not "field = null".
        // Only include optional fields when they have a value.
        var payload: [String: ConvexEncodable?] = [
            "ciderSyncId": bookmark.id.uuidString.lowercased(),
            "title": bookmark.title,
            "urlString": bookmark.urlString,
            "tags": bookmark.tags as [ConvexEncodable?],
            "createdAt": bookmark.createdAt.timeIntervalSince1970 * 1000,
            "updatedAt": bookmark.updatedAt.timeIntervalSince1970 * 1000,
            "deleted": false,
        ]
        if !bookmark.notes.isEmpty { payload["notes"] = bookmark.notes }
        if let url = bookmark.thumbnailRemoteURLString { payload["thumbnailRemoteUrl"] = url }
        if let summary = bookmark.aiSummary { payload["aiSummary"] = summary }
        if let colors = bookmark.dominantColors { payload["dominantColors"] = colors as [ConvexEncodable?] }
        if let folderID = bookmark.folderID { payload["folderSyncId"] = folderID.uuidString.lowercased() }
        return payload
    }

    private static func deletionTombstone(syncId: String, nowMs: Double) -> [String: ConvexEncodable?] {
        [
            "ciderSyncId": syncId,
            "title": "",
            "urlString": "",
            "tags": [] as [ConvexEncodable?],
            "createdAt": nowMs,
            "updatedAt": nowMs,
            "deleted": true,
            "deletedAt": nowMs,
        ]
    }

    private static func folderPayload(from folder: Folder) -> [String: ConvexEncodable?] {
        var payload: [String: ConvexEncodable?] = [
            "ciderSyncId": folder.id.uuidString.lowercased(),
            "name": folder.name,
            "createdAt": folder.createdAt.timeIntervalSince1970 * 1000,
            "updatedAt": folder.updatedAt.timeIntervalSince1970 * 1000,
            "deleted": false,
        ]
        if let icon = folder.icon { payload["icon"] = icon }
        if let parentID = folder.parentID { payload["parentSyncId"] = parentID.uuidString.lowercased() }
        return payload
    }

    private static func folderDeletionTombstone(syncId: String, nowMs: Double) -> [String: ConvexEncodable?] {
        [
            "ciderSyncId": syncId,
            "name": "",
            "createdAt": nowMs,
            "updatedAt": nowMs,
            "deleted": true,
            "deletedAt": nowMs,
        ]
    }

    private static func notePayload(from note: Note) -> [String: ConvexEncodable?] {
        var payload: [String: ConvexEncodable?] = [
            "ciderSyncId": note.id.uuidString.lowercased(),
            "title": note.title,
            "content": note.resolvedContent,
            "createdAt": note.createdAt.timeIntervalSince1970 * 1000,
            "updatedAt": note.modifiedAt.timeIntervalSince1970 * 1000,
            "deleted": false,
        ]
        if note.isPinned { payload["isPinned"] = true }
        if let folderID = note.folderID { payload["folderSyncId"] = folderID.uuidString.lowercased() }
        return payload
    }

    private static func noteDeletionTombstone(syncId: String, nowMs: Double) -> [String: ConvexEncodable?] {
        [
            "ciderSyncId": syncId,
            "title": "",
            "content": "",
            "createdAt": nowMs,
            "updatedAt": nowMs,
            "deleted": true,
            "deletedAt": nowMs,
        ]
    }

    // MARK: - URL conversion

    /// Convert .convex.site URL to .convex.cloud deployment URL.
    static func deploymentURL(from siteURL: String) -> String {
        if siteURL.contains(".convex.cloud") {
            return siteURL
        }
        return siteURL.replacingOccurrences(of: ".convex.site", with: ".convex.cloud")
    }

    // MARK: - Keychain

    private static let syncTokenKeychainKey = "syncToken"

    private func migrateSyncTokenToKeychainIfNeeded() {
        var config = CiderConfig.load()
        guard !config.syncToken.isEmpty else { return }
        KeychainHelper.save(key: Self.syncTokenKeychainKey, value: config.syncToken)
        config.syncToken = ""
        config.save()
        logger.info("Migrated sync token from UserDefaults to Keychain")
    }

    static func saveSyncToken(_ token: String) {
        KeychainHelper.save(key: syncTokenKeychainKey, value: token)
    }

    static func loadSyncToken() -> String {
        KeychainHelper.load(key: syncTokenKeychainKey) ?? ""
    }

    static func deleteSyncToken() {
        KeychainHelper.delete(key: syncTokenKeychainKey)
    }
}
