import Combine
@preconcurrency import ConvexMobile
import Foundation
import os

// MARK: - Convex pull response types

struct SyncAuthResponse: Decodable {
    let userId: String
}

struct SyncChangeSignal: Decodable {
    let lastChange: Double
}

struct SyncPullResponse: Decodable {
    let bookmarks: [SyncPulledBookmark]
    let folders: [SyncPulledFolder]
    let notes: [SyncPulledNote]
    let serverTime: Double
}

struct SyncPulledBookmark: Decodable {
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
    let purged: Bool?
    let purgedAt: Double?
    let folderSyncId: String?
}

struct SyncPulledFolder: Decodable {
    let ciderSyncId: String?
    let name: String
    let icon: String?
    let parentSyncId: String?
    let createdAt: Double
    let updatedAt: Double
    let deleted: Bool?
    let deletedAt: Double?
    let purged: Bool?
    let purgedAt: Double?
}

struct SyncPulledNote: Decodable {
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
    let purged: Bool?
    let purgedAt: Double?
}

struct SyncPushResponse: Decodable {
    let serverTime: Double
}

struct SyncNotePayloadPreview: Equatable {
    let ciderSyncId: String
    let title: String
    let content: String
    let tags: [String]
    let folderSyncId: String?
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

    /// Whether the initial post-startup pull has been performed.
    private var hasPerformedInitialPull = false

    /// Consecutive failure count for backoff.
    private var consecutiveFailures = 0

    /// Periodic timer to check for dirty notes (notes can't use event-driven
    /// push because their save paths have async side effects that create loops).
    private var dirtyNoteCheckTimer: Timer?

    /// Debounce task for pulls — when someone is actively editing on web/mobile,
    /// the changeSignal fires on every keystroke. We wait for it to stabilize.
    private var pullDebounceTask: Task<Void, Never>?

    /// The auth + initial subscription task, tracked so stop() can cancel it.
    private var authTask: Task<Void, Never>?

    // MARK: - Deletion tracking

    /// Bookmarks deleted locally that need to be pushed as deletions to the web.
    private var pendingDeletions: [String] = []
    /// Folders deleted locally that need to be pushed as deletions to the web.
    private var pendingFolderDeletions: [String] = []
    /// Notes deleted locally that need to be pushed as deletions to the web.
    private var pendingNoteDeletions: [String] = []

    // MARK: - Reconciliation

    private let reconciliationInterval: TimeInterval = 60 * 60
    private var isReconciling = false

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

        // Enforce HTTPS before sending the sync token
        guard config.syncURL.lowercased().hasPrefix("https://") else {
            logger.error("Sync URL must use HTTPS: \(config.syncURL)")
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
        // ConvexClient is owned by this service session, but the SDK action
        // method is nonisolated. Treat the reference as a stable session handle
        // when crossing from MainActor into the SDK call.
        nonisolated(unsafe) let authClient = client
        authTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                nonisolated(unsafe) let actionClient = authClient
                let authResult: SyncAuthResponse = try await actionClient.action(
                    "sync:authenticate", with: ["token": token]
                )
                guard !Task.isCancelled else { return }
                self.subscribeToChanges(client: authClient, userId: authResult.userId, token: token)
                self.performPush(token: token)
            } catch {
                guard !Task.isCancelled else { return }
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
        authTask?.cancel()
        authTask = nil
        changeSignalCancellable?.cancel()
        changeSignalCancellable = nil
        dirtyNoteCheckTimer?.invalidate()
        dirtyNoteCheckTimer = nil
        pullDebounceTask?.cancel()
        pullDebounceTask = nil
        pushDebounceTask?.cancel()
        pushDebounceTask = nil
        convexClient = nil
        isReconciling = false
        hasPerformedInitialPull = false
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

    func cancelNoteDeletion(of noteID: UUID) {
        let syncId = noteID.uuidString.lowercased()
        pendingNoteDeletions.removeAll { $0 == syncId }
        UserDefaults.standard.set(pendingNoteDeletions, forKey: pendingNoteDeletionsKey)
    }

    func trackFolderDeletion(of folderID: UUID) {
        let syncId = folderID.uuidString.lowercased()
        guard !pendingFolderDeletions.contains(syncId) else { return }
        pendingFolderDeletions.append(syncId)
        UserDefaults.standard.set(pendingFolderDeletions, forKey: pendingFolderDeletionsKey)
        pushAfterLocalChange()
    }

    func cancelFolderDeletion(of folderID: UUID) {
        let syncId = folderID.uuidString.lowercased()
        pendingFolderDeletions.removeAll { $0 == syncId }
        UserDefaults.standard.set(pendingFolderDeletions, forKey: pendingFolderDeletionsKey)
    }

    /// Re-read pending deletion queues from UserDefaults and merge them into
    /// the in-memory caches. UserDefaults is the cross-process shared store,
    /// so this picks up tombstones written by a separate CLI process while
    /// the app was running. Merge (not replace) preserves any in-memory
    /// entries that haven't been flushed to UserDefaults yet.
    private func mergePendingDeletionsFromUserDefaults() {
        let udBookmarks = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        let udFolders = UserDefaults.standard.stringArray(forKey: pendingFolderDeletionsKey) ?? []
        let udNotes = UserDefaults.standard.stringArray(forKey: pendingNoteDeletionsKey) ?? []

        var bookmarkSet = Set(pendingDeletions)
        for id in udBookmarks where bookmarkSet.insert(id).inserted {
            pendingDeletions.append(id)
        }
        var folderSet = Set(pendingFolderDeletions)
        for id in udFolders where folderSet.insert(id).inserted {
            pendingFolderDeletions.append(id)
        }
        var noteSet = Set(pendingNoteDeletions)
        for id in udNotes where noteSet.insert(id).inserted {
            pendingNoteDeletions.append(id)
        }
    }

    // MARK: - Manual trigger

    func syncNow() {
        let token = Self.loadSyncToken()
        guard !token.isEmpty else { return }
        consecutiveFailures = 0
        performPush(token: token)
    }

    /// Forces a full reconciliation — compares all local items against the server
    /// and pushes any corrections. Use when folder assignments or data seem out of sync.
    func forceReconcile() {
        let token = Self.loadSyncToken()
        guard !token.isEmpty else { return }
        performReconciliation(token: token)
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

        // Re-read pending deletion queues from UserDefaults. These queues
        // are persisted there so a CLI invocation (a separate process) can
        // enqueue a tombstone while the app is running; without this refresh,
        // the running app would only see its own in-memory cache and the
        // CLI's deletion would never propagate to the server.
        mergePendingDeletionsFromUserDefaults()

        let storage = VaultBookmarkService.shared
        let notesStorage = NotesStorage.shared
        let config = CiderConfig.load()
        let lastPushDate = Date(timeIntervalSince1970: config.lastSuccessfulPushAt)

        // Dirty items
        let dirtyBookmarks = storage.bookmarks.filter { $0.updatedAt > lastPushDate }
        let dirtyFolders = VaultFolderService.shared.legacyFolders.filter { $0.updatedAt > lastPushDate }
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
            // Pull once after startup to catch up; after that, the WebSocket
            // changeSignal handles pulls reactively — no need to poll.
            if !hasPerformedInitialPull {
                hasPerformedInitialPull = true
                performPull(token: token, nothingWasPushed: true)
            } else {
                maybeReconcile(token: token)
            }
            return
        }

        logger.info("Push: \(dirtyBookmarks.count)+\(self.pendingDeletions.count) bookmark(s), \(dirtyFolders.count)+\(self.pendingFolderDeletions.count) folder(s), \(dirtyNotes.count)+\(self.pendingNoteDeletions.count) note(s)")

        isSyncing = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                nonisolated(unsafe) var args: [String: ConvexEncodable?] = [
                    "token": token,
                    "bookmarks": bookmarkArgs as [ConvexEncodable?],
                ]
                if !folderArgs.isEmpty {
                    args["folders"] = folderArgs as [ConvexEncodable?]
                }
                if !noteArgs.isEmpty {
                    args["notes"] = noteArgs as [ConvexEncodable?]
                }

                nonisolated(unsafe) let pushClient = client
                nonisolated(unsafe) let pushArgs: [String: ConvexEncodable?]? = args
                let result: SyncPushResponse = try await pushClient.action("sync:push", with: pushArgs)

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

                // Upload note attachment images in background (fire-and-forget)
                if !dirtyNotes.isEmpty {
                    self.uploadNoteAttachments(dirtyNotes: dirtyNotes, token: token)
                }

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

    private func performPull(token: String, nothingWasPushed: Bool = false) {
        guard !isSyncing, let client = convexClient else { return }

        isSyncing = true
        lastError = nil

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let config = CiderConfig.load()
                nonisolated(unsafe) let args: [String: ConvexEncodable?] = [
                    "token": token,
                    "since": config.lastSyncTimestamp,
                ]

                nonisolated(unsafe) let pullClient = client
                nonisolated(unsafe) let pullArgs: [String: ConvexEncodable?]? = args
                let result: SyncPullResponse = try await pullClient.action("sync:pull", with: pullArgs)

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

                // If nothing was pushed and nothing was pulled, sync is idle — good time to reconcile
                if nothingWasPushed
                    && result.bookmarks.isEmpty
                    && result.folders.isEmpty
                    && result.notes.isEmpty
                {
                    self.maybeReconcile(token: token)
                }
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
        let storage = VaultBookmarkService.shared

        // --- Folders first (bookmarks/notes may reference them) ---
        let folderService = VaultFolderService.shared
        let localFolders = folderService.legacyFolders
        for folder in result.folders {
            guard let syncId = folder.ciderSyncId else { continue }

            let syncIdLower = syncId.lowercased()
            let remoteUpdatedAt = Date(timeIntervalSince1970: folder.updatedAt / 1000)
            let isDeleted = folder.deleted ?? false
            let parentSyncId = folder.parentSyncId?.lowercased()

            let parentID: UUID? = if let parentSyncId {
                localFolders.first(where: { $0.id.uuidString.lowercased() == parentSyncId })?.id
            } else {
                nil
            }

            if let local = localFolders.first(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                if folder.purged == true {
                    folderService.deleteFolderFromSync(local.id)
                } else if isDeleted {
                    folderService.deleteFolderFromSync(local.id)
                } else if remoteUpdatedAt > local.updatedAt {
                    folderService.updateFolderFromSync(
                        folderID: local.id, name: folder.name, icon: folder.icon,
                        parentID: parentID, remoteUpdatedAt: remoteUpdatedAt
                    )
                }
            } else if !isDeleted {
                if let uuid = UUID(uuidString: syncId) {
                    folderService.addFolderFromSync(
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

            let remoteFolderSyncId = bookmark.folderSyncId?.lowercased()
            let resolvedFolderID: UUID? = if let remoteFolderSyncId {
                folderService.legacyFolders.first(where: { $0.id.uuidString.lowercased() == remoteFolderSyncId })?.id
            } else {
                nil
            }

            if let localIndex = storage.bookmarks.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                let local = storage.bookmarks[localIndex]
                if bookmark.purged == true {
                    storage.removeSynced(local)
                } else if isDeleted {
                    storage.trashFromSync(local)
                } else if remoteUpdatedAt > local.updatedAt {
                    // Determine the folder to set:
                    // - Remote has no folder (nil syncId) → clear local folder
                    // - Remote has folder and it resolves → use resolved ID
                    // - Remote has folder but can't resolve → keep local folder (don't wipe)
                    let syncFolderID: UUID?
                    if remoteFolderSyncId == nil {
                        syncFolderID = nil  // remote explicitly has no folder
                    } else if let resolvedFolderID {
                        syncFolderID = resolvedFolderID  // resolved successfully
                    } else {
                        syncFolderID = local.folderID  // can't resolve — preserve local
                    }
                    storage.updateFromSync(
                        bookmarkID: local.id, title: bookmark.title,
                        urlString: bookmark.urlString,
                        notes: bookmark.notes ?? "",
                        tags: bookmark.tags ?? [],
                        thumbnailRemoteURLString: bookmark.thumbnailRemoteUrl,
                        aiSummary: bookmark.aiSummary,
                        dominantColors: bookmark.dominantColors,
                        folderID: syncFolderID,
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
                        folderID: resolvedFolderID
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
            let tags = note.tags ?? []

            let remoteFolderSyncId = note.folderSyncId?.lowercased()
            let resolvedFolderID: UUID? = if let remoteFolderSyncId {
                folderService.legacyFolders.first(where: { $0.id.uuidString.lowercased() == remoteFolderSyncId })?.id
            } else {
                nil
            }

            if let localIndex = notesStorage.notes.firstIndex(where: { $0.id.uuidString.lowercased() == syncIdLower }) {
                let local = notesStorage.notes[localIndex]
                if note.purged == true {
                    notesStorage.removeSynced(local)
                } else if isDeleted {
                    notesStorage.deleteFromSync(local)
                } else if remoteUpdatedAt > local.modifiedAt {
                    let syncFolderID: UUID?
                    if remoteFolderSyncId == nil {
                        syncFolderID = nil
                    } else if let resolvedFolderID {
                        syncFolderID = resolvedFolderID
                    } else {
                        syncFolderID = local.folderID
                    }
                    // Skip no-op updates — pulling back what we just pushed
                    // would trigger the editor's contentChanged and loop.
                    let localContent = local.content.isEmpty ? notesStorage.loadContent(for: local) : local.content
                    if localContent == content
                        && local.title == note.title
                        && local.folderID == syncFolderID
                        && local.isPinned == isPinned
                        && local.tags == tags
                    {
                        continue
                    }
                    notesStorage.updateFromSync(
                        noteID: local.id, title: note.title, content: content,
                        folderID: syncFolderID, isPinned: isPinned, tags: tags,
                        remoteUpdatedAt: remoteUpdatedAt
                    )
                }
            } else if !isDeleted {
                if let uuid = UUID(uuidString: syncId) {
                    notesStorage.addFromSync(
                        id: uuid, title: note.title, content: content,
                        folderID: resolvedFolderID, isPinned: isPinned, tags: tags,
                        createdAt: Date(timeIntervalSince1970: note.createdAt / 1000),
                        updatedAt: remoteUpdatedAt
                    )
                }
            }
        }
    }

    // MARK: - Reconciliation

    private func maybeReconcile(token: String) {
        guard !isReconciling else { return }
        let config = CiderConfig.load()
        let elapsed = Date().timeIntervalSince1970 - config.lastReconciliationAt
        guard elapsed >= reconciliationInterval else {
            logger.debug("Reconcile: skipping, last ran \(Int(elapsed))s ago")
            return
        }
        performReconciliation(token: token)
    }

    private func performReconciliation(token: String) {
        guard let client = convexClient else { return }
        isReconciling = true
        logger.info("Reconcile: starting full inventory check")

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isReconciling = false }

            do {
                // Full pull (since: 0) to get complete server state
                nonisolated(unsafe) let args: [String: ConvexEncodable?] = [
                    "token": token,
                    "since": 0.0,
                ]
                nonisolated(unsafe) let reconcileClient = client
                nonisolated(unsafe) let reconcileArgs: [String: ConvexEncodable?]? = args
                let result: SyncPullResponse = try await reconcileClient.action("sync:pull", with: reconcileArgs)

                // Apply the pull result first — this creates local rows for any
                // server items that aren't present locally (via addFromSync) and
                // updates locals that the server has newer. Without this, the
                // reconciliation loops below would see ghosts and previously
                // pushed deletion tombstones; now they pull the missing items
                // back into local state and leave the server authoritative.
                self.applyPullResult(result)

                // Build local inventories (re-read after applyPullResult added items)
                let localBookmarks = VaultBookmarkService.shared.bookmarks
                let localFolders = VaultFolderService.shared.legacyFolders
                let localNotes = NotesStorage.shared.notes

                let localBookmarkIDs = Set(localBookmarks.map { $0.id.uuidString.lowercased() })
                let localFolderIDs = Set(localFolders.map { $0.id.uuidString.lowercased() })
                let localNoteIDs = Set(localNotes.map { $0.id.uuidString.lowercased() })

                // Build server dictionaries (non-deleted items only)
                var serverBookmarks: [String: SyncPulledBookmark] = [:]
                for b in result.bookmarks {
                    guard let syncId = b.ciderSyncId, !(b.deleted ?? false) else { continue }
                    serverBookmarks[syncId.lowercased()] = b
                }
                var serverFolders: [String: SyncPulledFolder] = [:]
                for f in result.folders {
                    guard let syncId = f.ciderSyncId, !(f.deleted ?? false) else { continue }
                    serverFolders[syncId.lowercased()] = f
                }
                var serverNotes: [String: SyncPulledNote] = [:]
                for n in result.notes {
                    guard let syncId = n.ciderSyncId, !(n.deleted ?? false) else { continue }
                    serverNotes[syncId.lowercased()] = n
                }

                var corrections: [[String: ConvexEncodable?]] = []
                var folderCorrections: [[String: ConvexEncodable?]] = []
                var noteCorrections: [[String: ConvexEncodable?]] = []

                // Server has, Desktop doesn't → log only, never push deletion tombstones.
                //
                // The previous behavior assumed that "missing locally" implied "user
                // deleted it" and pushed a deletion to the server. But silent local
                // deletions happen in practice (e.g. a bug in adoptOrphanedVaultFiles
                // once hard-deleted duplicate .webloc files), and propagating those to
                // the server is unrecoverable. We now trust the server as the source
                // of truth in this direction: items only present on the server are
                // pulled back via applyPullResult's addFromSync path on the next pull.
                //
                // Explicit user deletions are still propagated via pendingDeletions,
                // which is updated by trackDeletion(of:) on the intentional delete path.
                for (syncId, _) in serverBookmarks where !localBookmarkIDs.contains(syncId) {
                    self.logger.warning("Reconcile: bookmark \(syncId) on server, not local — will be re-pulled on next sync (not deleting)")
                }
                for (syncId, _) in serverFolders where !localFolderIDs.contains(syncId) {
                    self.logger.warning("Reconcile: folder \(syncId) on server, not local — will be re-pulled on next sync (not deleting)")
                }
                for (syncId, _) in serverNotes where !localNoteIDs.contains(syncId) {
                    self.logger.warning("Reconcile: note \(syncId) on server, not local — will be re-pulled on next sync (not deleting)")
                }

                // Desktop has, server doesn't → push full item (missed push recovery)
                for bookmark in localBookmarks where serverBookmarks[bookmark.id.uuidString.lowercased()] == nil {
                    self.logger.info("Reconcile: missing bookmark \(bookmark.id) — pushing to server")
                    corrections.append(Self.bookmarkPayload(from: bookmark))
                }
                for folder in localFolders where serverFolders[folder.id.uuidString.lowercased()] == nil {
                    self.logger.info("Reconcile: missing folder \(folder.id) — pushing to server")
                    folderCorrections.append(Self.folderPayload(from: folder))
                }
                for note in localNotes where serverNotes[note.id.uuidString.lowercased()] == nil {
                    self.logger.info("Reconcile: missing note \(note.id) — pushing to server")
                    noteCorrections.append(Self.notePayload(from: note))
                }

                // Both have, Desktop newer → push Desktop's version
                // Compare at millisecond precision to avoid sub-ms floating-point drift
                // (local Date has nanosecond precision, server stores whole milliseconds)
                for bookmark in localBookmarks {
                    let syncId = bookmark.id.uuidString.lowercased()
                    guard let serverItem = serverBookmarks[syncId] else { continue }
                    let localMs = floor(bookmark.updatedAt.timeIntervalSince1970 * 1000)
                    if localMs > serverItem.updatedAt {
                        self.logger.info("Reconcile: bookmark \(syncId) newer locally — pushing update")
                        corrections.append(Self.bookmarkPayload(from: bookmark))
                    }
                }
                for folder in localFolders {
                    let syncId = folder.id.uuidString.lowercased()
                    guard let serverItem = serverFolders[syncId] else { continue }
                    let localMs = floor(folder.updatedAt.timeIntervalSince1970 * 1000)
                    if localMs > serverItem.updatedAt {
                        self.logger.info("Reconcile: folder \(syncId) newer locally — pushing update")
                        folderCorrections.append(Self.folderPayload(from: folder))
                    }
                }
                for note in localNotes {
                    let syncId = note.id.uuidString.lowercased()
                    guard let serverItem = serverNotes[syncId] else { continue }
                    let localMs = floor(note.modifiedAt.timeIntervalSince1970 * 1000)
                    if localMs > serverItem.updatedAt {
                        self.logger.info("Reconcile: note \(syncId) newer locally — pushing update")
                        noteCorrections.append(Self.notePayload(from: note))
                    }
                }

                // Push corrections if any
                if corrections.isEmpty && folderCorrections.isEmpty && noteCorrections.isEmpty {
                    self.logger.info("Reconcile: no drift detected")
                } else {
                    self.logger.info("Reconcile: pushing \(corrections.count) bookmark, \(folderCorrections.count) folder, \(noteCorrections.count) note correction(s)")
                    // Safe: corrections are value-type dicts built on MainActor and
                    // not accessed again after being sent to the nonisolated action.
                    nonisolated(unsafe) let bookmarksCopy = corrections
                    nonisolated(unsafe) let foldersCopy = folderCorrections
                    nonisolated(unsafe) let notesCopy = noteCorrections
                    nonisolated(unsafe) let correctionClient = client
                    try await self.pushReconciliationCorrections(
                        client: correctionClient, token: token,
                        bookmarks: bookmarksCopy, folders: foldersCopy, notes: notesCopy
                    )
                    self.logger.info("Reconcile: corrections pushed successfully")
                }

                self.saveReconciliationTimestamp()
            } catch {
                self.logger.error("Reconcile failed: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated func pushReconciliationCorrections(
        client: ConvexClient,
        token: String,
        bookmarks: [[String: ConvexEncodable?]],
        folders: [[String: ConvexEncodable?]],
        notes: [[String: ConvexEncodable?]]
    ) async throws {
        var args: [String: ConvexEncodable?] = [
            "token": token,
            "bookmarks": bookmarks as [ConvexEncodable?],
        ]
        if !folders.isEmpty {
            args["folders"] = folders as [ConvexEncodable?]
        }
        if !notes.isEmpty {
            args["notes"] = notes as [ConvexEncodable?]
        }
        nonisolated(unsafe) let actionArgs = args
        let _: SyncPushResponse = try await client.action("sync:push", with: actionArgs)
    }

    private nonisolated func performSyncPushAction(
        client: ConvexClient,
        args: sending [String: ConvexEncodable?]
    ) async throws -> SyncPushResponse {
        try await client.action("sync:push", with: args)
    }

    private func saveReconciliationTimestamp() {
        var config = CiderConfig.load()
        config.lastReconciliationAt = Date().timeIntervalSince1970
        config.save()
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
        let preview = notePayloadPreview(from: note)
        var payload: [String: ConvexEncodable?] = [
            "ciderSyncId": preview.ciderSyncId,
            "title": preview.title,
            "content": preview.content,
            "tags": preview.tags as [ConvexEncodable?],
            "createdAt": note.createdAt.timeIntervalSince1970 * 1000,
            "updatedAt": note.modifiedAt.timeIntervalSince1970 * 1000,
            "deleted": false,
        ]
        if note.isPinned { payload["isPinned"] = true }
        if let folderSyncId = preview.folderSyncId { payload["folderSyncId"] = folderSyncId }
        return payload
    }

    static func notePayloadPreviewForTesting(from note: Note) -> SyncNotePayloadPreview {
        notePayloadPreview(from: note)
    }

    private static func notePayloadPreview(from note: Note) -> SyncNotePayloadPreview {
        SyncNotePayloadPreview(
            ciderSyncId: note.id.uuidString.lowercased(),
            title: note.title,
            content: note.resolvedContent,
            tags: note.tags,
            folderSyncId: note.folderID?.uuidString.lowercased()
        )
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

    // MARK: - Note Attachment Upload

    /// Upload note attachment images that are referenced in content but not yet on the server.
    private func uploadNoteAttachments(dirtyNotes: [Note], token: String) {
        let config = CiderConfig.load()
        let siteURL = config.syncURL
        guard !siteURL.isEmpty else { return }

        // Collect all (noteSyncId, filename, fileURL) tuples from dirty notes
        var pending: [(noteSyncId: String, filename: String, fileURL: URL)] = []
        for note in dirtyNotes {
            let content = note.resolvedContent
            let urls = note.attachmentImageURLs(from: content)
            for url in urls {
                // Only upload note-owned local attachments, never arbitrary absolute file references.
                guard url.isFileURL else { continue }
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let filename = url.lastPathComponent
                pending.append((
                    noteSyncId: note.id.uuidString.lowercased(),
                    filename: filename,
                    fileURL: url
                ))
            }
        }

        guard !pending.isEmpty else { return }

        Task.detached { [weak self] in
            guard let self else { return }

            // Step 1: Check which attachments already exist on server
            let checkURL = URL(string: "\(siteURL)/api/sync/note-attachments-check")!
            var checkRequest = URLRequest(url: checkURL)
            checkRequest.httpMethod = "POST"
            checkRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            checkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let items = pending.map { ["noteSyncId": $0.noteSyncId, "filename": $0.filename] }
            checkRequest.httpBody = try? JSONSerialization.data(withJSONObject: ["items": items])

            var needsUpload = pending // default: upload all if check fails
            if let (data, response) = try? await URLSession.shared.data(for: checkRequest),
               let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]] {
                // Filter to only those that don't exist
                needsUpload = []
                for (i, result) in results.enumerated() where i < pending.count {
                    if result["exists"] as? Bool != true {
                        needsUpload.append(pending[i])
                    }
                }
            }

            let totalCount = pending.count
            guard !needsUpload.isEmpty else {
                await MainActor.run {
                    self.logger.debug("Note attachments: all \(totalCount) already on server")
                }
                return
            }

            let uploadCount = needsUpload.count
            await MainActor.run {
                self.logger.info("Note attachments: uploading \(uploadCount) of \(totalCount)")
            }

            // Step 2: Upload each missing attachment
            for item in needsUpload {
                do {
                    let fileData = try Data(contentsOf: item.fileURL)
                    let uploadURL = URL(string: "\(siteURL)/api/sync/upload-note-attachment")!
                    var request = URLRequest(url: uploadURL)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue(item.noteSyncId, forHTTPHeaderField: "X-Cider-Note-Sync-Id")
                    request.setValue(item.filename, forHTTPHeaderField: "X-Cider-Attachment-Filename")
                    // Infer content type from extension
                    let ext = item.fileURL.pathExtension.lowercased()
                    let contentType = ext == "png" ? "image/png" : ext == "jpg" || ext == "jpeg" ? "image/jpeg" : "application/octet-stream"
                    request.setValue(contentType, forHTTPHeaderField: "Content-Type")
                    request.httpBody = fileData

                    let (_, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        await MainActor.run {
                            self.logger.debug("Uploaded attachment: \(item.filename) for note \(item.noteSyncId)")
                        }
                    }
                } catch {
                    await MainActor.run {
                        self.logger.error("Failed to upload attachment \(item.filename): \(error.localizedDescription)")
                    }
                }
            }
        }
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
