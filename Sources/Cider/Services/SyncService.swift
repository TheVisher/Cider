import Combine
import Foundation
import os

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

struct SyncNotePayloadPreview: Equatable {
    let ciderSyncId: String
    let title: String
    let content: String
    let tags: [String]
    let folderSyncId: String?
}

/// Local compatibility hook for storage mutation paths.
///
/// Remote sync is intentionally absent on desktop while the new backend/sync
/// design is rebuilt. Storage services still call these hooks after local
/// bookmark, folder, and note mutations; this object keeps those call sites
/// safe without linking or invoking any remote runtime.
@MainActor
final class SyncService: ObservableObject {
    static let shared = SyncService()

    @Published var isSyncing = false
    @Published var lastSyncedAt: Date?
    @Published var lastError: String?

    private static let syncTokenKeychainKey = "syncToken"

    private let logger = Logger(subsystem: "com.cider.app", category: "Sync")

    private let pendingDeletionsKey = "CiderSyncPendingDeletions"
    private let pendingFolderDeletionsKey = "CiderSyncPendingFolderDeletions"
    private let pendingNoteDeletionsKey = "CiderSyncPendingNoteDeletions"

    private var pendingDeletions: [String]
    private var pendingFolderDeletions: [String]
    private var pendingNoteDeletions: [String]

    private init() {
        pendingDeletions = UserDefaults.standard.stringArray(forKey: pendingDeletionsKey) ?? []
        pendingFolderDeletions = UserDefaults.standard.stringArray(forKey: pendingFolderDeletionsKey) ?? []
        pendingNoteDeletions = UserDefaults.standard.stringArray(forKey: pendingNoteDeletionsKey) ?? []
        migrateSyncTokenToKeychainIfNeeded()
    }

    struct FolderDependencyPartition {
        let ready: [SyncPulledFolder]
        let unresolved: [SyncPulledFolder]
    }

    struct FolderDuplicateQuarantineDecision {
        let shouldQuarantine: Bool
        let canonicalFolderID: UUID?
        let reason: String?
    }

    nonisolated static func partitionPulledFoldersByResolvedParent(
        _ folders: [SyncPulledFolder],
        availableFolderIDs: Set<String>
    ) -> FolderDependencyPartition {
        var ready: [SyncPulledFolder] = []
        var unresolved: [SyncPulledFolder] = []
        for folder in folders {
            guard folder.ciderSyncId != nil else { continue }
            let isDeletion = (folder.deleted ?? false) || folder.purged == true
            if let parentSyncId = folder.parentSyncId?.lowercased(),
               !isDeletion,
               !availableFolderIDs.contains(parentSyncId) {
                unresolved.append(folder)
            } else {
                ready.append(folder)
            }
        }
        return FolderDependencyPartition(ready: ready, unresolved: unresolved)
    }

    nonisolated static func duplicateQuarantineDecisionForPulledFolder(
        name: String,
        parentID: UUID?,
        folders: [VaultFolder]
    ) -> FolderDuplicateQuarantineDecision {
        let sanitized = sanitizePulledFolderName(name)
        guard !sanitized.isEmpty else {
            return FolderDuplicateQuarantineDecision(
                shouldQuarantine: true,
                canonicalFolderID: nil,
                reason: "empty_sanitized_name"
            )
        }

        let parentPath = parentID.flatMap { parentID in
            folders.first(where: { $0.id == parentID })?.relativePath
        }
        let targetRelativePath = parentPath.map { "\($0)/\(sanitized)" } ?? sanitized

        if let exact = folders.first(where: { $0.relativePath == targetRelativePath }) {
            return FolderDuplicateQuarantineDecision(
                shouldQuarantine: true,
                canonicalFolderID: exact.id,
                reason: "exact_path_exists"
            )
        }

        let canonicalName = stripNumericSuffixes(from: sanitized)
        if canonicalName != sanitized {
            let canonicalPath = parentPath.map { "\($0)/\(canonicalName)" } ?? canonicalName
            if let canonical = folders.first(where: { $0.relativePath == canonicalPath }) {
                return FolderDuplicateQuarantineDecision(
                    shouldQuarantine: true,
                    canonicalFolderID: canonical.id,
                    reason: "numeric_suffix_sibling"
                )
            }
        }

        if parentID == nil {
            let normalizedName = normalizedFolderComponent(sanitized)
            let nestedMatches = folders.filter { folder in
                folder.relativePath.contains("/")
                    && normalizedFolderComponent(URL(fileURLWithPath: folder.relativePath).lastPathComponent) == normalizedName
            }

            if nestedMatches.count == 1 {
                return FolderDuplicateQuarantineDecision(
                    shouldQuarantine: true,
                    canonicalFolderID: nestedMatches[0].id,
                    reason: "root_duplicate_of_nested_folder"
                )
            } else if nestedMatches.count > 1 {
                return FolderDuplicateQuarantineDecision(
                    shouldQuarantine: true,
                    canonicalFolderID: nil,
                    reason: "ambiguous_root_duplicate_of_nested_folder"
                )
            }
        }

        return FolderDuplicateQuarantineDecision(
            shouldQuarantine: false,
            canonicalFolderID: nil,
            reason: nil
        )
    }

    func startIfEnabled() {
        resetIdleState()
        logger.debug("Remote sync is unavailable; preserving local-only mutation hooks")
    }

    func stop() {
        resetIdleState()
    }

    func trackDeletion(of bookmarkID: UUID) {
        append(bookmarkID, to: &pendingDeletions, key: pendingDeletionsKey)
    }

    func cancelDeletion(of bookmarkID: UUID) {
        remove(bookmarkID, from: &pendingDeletions, key: pendingDeletionsKey)
    }

    func trackNoteDeletion(of noteID: UUID) {
        append(noteID, to: &pendingNoteDeletions, key: pendingNoteDeletionsKey)
    }

    func cancelNoteDeletion(of noteID: UUID) {
        remove(noteID, from: &pendingNoteDeletions, key: pendingNoteDeletionsKey)
    }

    func trackFolderDeletion(of folderID: UUID) {
        append(folderID, to: &pendingFolderDeletions, key: pendingFolderDeletionsKey)
    }

    func cancelFolderDeletion(of folderID: UUID) {
        remove(folderID, from: &pendingFolderDeletions, key: pendingFolderDeletionsKey)
    }

    func syncNow() {
        resetIdleState()
        logger.debug("Manual sync ignored because remote sync is unavailable")
    }

    func forceReconcile() {
        resetIdleState()
        logger.debug("Manual reconcile ignored because remote sync is unavailable")
    }

    func pushAfterLocalChange() {
        resetIdleState()
        logger.debug("Local mutation observed; no remote push is configured")
    }

    static func notePayloadPreviewForTesting(from note: Note) -> SyncNotePayloadPreview {
        SyncNotePayloadPreview(
            ciderSyncId: note.id.uuidString.lowercased(),
            title: note.title,
            content: note.resolvedContent,
            tags: note.tags,
            folderSyncId: note.folderID?.uuidString.lowercased()
        )
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

    private nonisolated static func normalizedFolderComponent(_ value: String) -> String {
        stripNumericSuffixes(from: value).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private nonisolated static func sanitizePulledFolderName(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: "/", with: "-")
        value = value.replacingOccurrences(of: ":", with: "-")
        value = value.replacingOccurrences(of: "\0", with: "")
        while value.hasPrefix(".") { value = String(value.dropFirst()) }
        return value.isEmpty ? "Folder" : value
    }

    private nonisolated static func stripNumericSuffixes(from value: String) -> String {
        var current = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(.*?)(?:\s+\d+)+$"#
        while let range = current.range(of: pattern, options: .regularExpression) {
            let matched = String(current[range])
            guard let suffixRange = matched.range(of: #"(?:\s+\d+)+$"#, options: .regularExpression) else {
                break
            }
            let stripped = matched[..<suffixRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !stripped.isEmpty, stripped != current else { break }
            current = stripped
        }
        return current
    }

    private func append(_ id: UUID, to values: inout [String], key: String) {
        let value = id.uuidString.lowercased()
        guard !values.contains(value) else { return }
        values.append(value)
        UserDefaults.standard.set(values, forKey: key)
    }

    private func remove(_ id: UUID, from values: inout [String], key: String) {
        let value = id.uuidString.lowercased()
        values.removeAll { $0.lowercased() == value }
        UserDefaults.standard.set(values, forKey: key)
    }

    private func resetIdleState() {
        isSyncing = false
        lastError = nil
    }

    private func migrateSyncTokenToKeychainIfNeeded() {
        var config = CiderConfig.load()
        guard !config.syncToken.isEmpty else { return }
        KeychainHelper.save(key: Self.syncTokenKeychainKey, value: config.syncToken)
        config.syncToken = ""
        config.syncEnabled = false
        config.syncURL = ""
        config.save()
        logger.info("Migrated legacy sync token to Keychain and disabled remote sync config")
    }
}
