import Combine
import CommonCrypto
import Foundation
import os

/// Scans vault folders for non-Cider files (images, PDFs, videos, etc.)
/// and makes them available as VaultFile items for display in the UI.
@MainActor
final class VaultFileService: ObservableObject {
    static let shared = VaultFileService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultFileService"
    )

    @Published private(set) var files: [VaultFile] = []

    private var vaultRoot: URL { StoragePaths.cachedVaultDirectoryURL }

    // MARK: - UUID Stabilization (id-map sidecar)
    //
    // Prior versions derived `VaultFile.id` from a SHA-256 of the vault-relative
    // path. That meant moving a file changed its ID and broke every cross-reference
    // (labels, item_links, trash). We now store a stable UUID per path in
    // `.cider/vault-files/id-map.json` so that in-app moves preserve the UUID.
    //
    // KNOWN LIMITATION: External Finder moves bypass `assignFile` and therefore
    // orphan the old id-map entry. A fresh UUID is generated on the next scan,
    // which loses label/link associations. Task 12 (Startup Reconciliation) will
    // recover these via content-based matching.
    private var idMap: [String: UUID] = [:]
    private var idMapLoaded = false

    private var idMapDirectoryURL: URL {
        vaultRoot
            .appendingPathComponent(StoragePaths.ciderInternalDir)
            .appendingPathComponent("vault-files")
    }

    private var idMapFileURL: URL {
        idMapDirectoryURL.appendingPathComponent("id-map.json")
    }

    /// File extensions that are Cider-native and handled by other services.
    private static let excludedExtensions: Set<String> = ["md", "json", "webloc", "ics", "vcf"]

    /// Directories excluded from the main vault scan.
    /// `.cider/` is hidden and auto-skipped by .skipsHiddenFiles.
    /// Inbox is excluded from main scan — its vault-file subfolders are scanned separately.
    private static let excludedDirectoryPrefixes: Set<String> = [
        "Unsorted", "Inbox"
    ]

    /// Inbox subdirectory names for vault file types.
    static let inboxImagesDirName = "Images"
    static let inboxVideosDirName = "Videos"
    static let inboxFilesDirName = "Files"

    // MARK: - File Watching

    private var watcher: FSEventsWatcher?
    private var isScanning = false
    private var pendingRescan = false

    private init() {}

    // MARK: - Testing Helpers

    /// Testing-only: directly set an id-map entry (no disk I/O).
    func _setIDMapEntryForTesting(path: String, id: UUID) {
        idMap[path] = id
        idMapLoaded = true
    }

    /// Testing-only: read an id-map entry.
    func _idMapEntryForTesting(path: String) -> UUID? {
        idMap[path]
    }

    /// Testing-only: read the full id-map snapshot.
    func _idMapSnapshotForTesting() -> [String: UUID] {
        idMap
    }

    /// Testing-only: clear the in-memory id-map.
    func _resetIDMapForTesting() {
        idMap = [:]
        idMapLoaded = false
    }

    /// Testing-only: compute a legacy path-derived ID (used to seed pre-migration state).
    func _stableIDForTesting(path: String) -> UUID {
        stableID(for: path)
    }

    // MARK: - Public API

    /// Ensures Inbox vault-file subdirectories exist.
    func ensureInboxDirectories() {
        let fm = FileManager.default
        let inboxRoot = vaultRoot.appendingPathComponent("Inbox")
        for dirName in [Self.inboxImagesDirName, Self.inboxVideosDirName, Self.inboxFilesDirName] {
            let dirURL = inboxRoot.appendingPathComponent(dirName)
            try? fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }

    /// Scans all vault folders + Inbox vault-file subdirectories for non-Cider files.
    func scan() {
        guard !isScanning else { pendingRescan = true; return }
        isScanning = true
        defer {
            isScanning = false
            if pendingRescan {
                pendingRescan = false
                scan()
            }
        }

        // Ensure id-map is loaded (and run one-time migration on first run).
        //
        // Migration gate: the path-derived → stable-UUID migration must run at
        // most ONCE. We track it in SQLite (`schema_migrations` table) so that
        // losing id-map.json (backup restore, sync conflict, user cleanup)
        // doesn't cause us to re-mint UUIDs and orphan every label/link.
        //
        // Order of precedence on startup:
        //   1. Load id-map from sidecar if present.
        //   2. If id-map is empty but SQLite `vault_files` has rows, rebuild
        //      it from there (recovers lost/corrupted sidecar).
        //   3. Only run the one-time migration if it's never been recorded
        //      in `schema_migrations`.
        if !idMapLoaded {
            loadIDMap()
            if idMap.isEmpty {
                rebuildIDMapFromDatabase()
            }
            if !hasRunOneTimeIDMigration() {
                runOneTimeIDMigration()
                recordOneTimeIDMigration()
            }
            idMapLoaded = true
        }

        let fm = FileManager.default
        let root = vaultRoot
        var scanned: [VaultFile] = []
        var idMapDirty = false

        // ── 1. Scan user folders (everything except Inbox/ and Unsorted/) ──
        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey,
                .creationDateKey, .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                let relativePath = url.path.hasPrefix(rootPrefix) ? String(url.path.dropFirst(rootPrefix.count)) : url.path
                let components = relativePath.split(separator: "/").map(String.init)

                // Skip excluded top-level directories
                if let topComponent = components.first,
                   Self.excludedDirectoryPrefixes.contains(topComponent) {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if let file = processFile(url: url, relativePath: relativePath, idMapDirty: &idMapDirty) {
                    scanned.append(file)
                }
            }
        }

        // ── 2. Scan Inbox vault-file subdirectories (Images/, Videos/, Files/) ──
        let inboxRoot = root.appendingPathComponent("Inbox")
        for dirName in [Self.inboxImagesDirName, Self.inboxVideosDirName, Self.inboxFilesDirName] {
            let dirURL = inboxRoot.appendingPathComponent(dirName)
            guard fm.fileExists(atPath: dirURL.path) else { continue }

            if let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey, .fileSizeKey,
                    .creationDateKey, .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                let relativePath = url.path.hasPrefix(rootPrefix) ? String(url.path.dropFirst(rootPrefix.count)) : url.path
                    if let file = processFile(url: url, relativePath: relativePath, idMapDirty: &idMapDirty) {
                        scanned.append(file)
                    }
                }
            }
        }

        // Prune id-map entries for files that no longer exist on disk, and
        // delete the corresponding SQLite rows so metadata doesn't leak. This
        // keeps the sidecar + SQLite in sync when files are deleted externally
        // (Finder, sync client, `rm` in terminal, etc.).
        //
        // Check `FileManager.fileExists` directly instead of comparing against
        // `scanned`, because scan-time filters (zero-byte, symlinks, excluded
        // extensions) omit files that still exist on disk. Pruning on "not in
        // scan results" would wipe SQLite rows for zero-byte in-progress writes.
        let staleKeys = idMap.keys.filter { relPath in
            let absPath = root.appendingPathComponent(relPath).path
            return !fm.fileExists(atPath: absPath)
        }
        if !staleKeys.isEmpty {
            let orphanedIDs: [UUID] = staleKeys.compactMap { idMap[$0] }
            for key in staleKeys { idMap.removeValue(forKey: key) }
            idMapDirty = true

            // Delete orphaned rows in a single transaction.
            if !orphanedIDs.isEmpty, let db = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil {
                do {
                    try db.withTransaction {
                        for uuid in orphanedIDs {
                            VaultFileStorage.shared.deleteVaultFileFromDatabase(db, fileID: uuid)
                        }
                    }
                } catch {
                    logger.error("Failed to delete orphaned vault file rows: \(error.localizedDescription)")
                }
            }
        }

        if idMapDirty {
            saveIDMap()
        }

        // Apply persisted metadata (title, notes, labels, OCR, colors)
        VaultFileStorage.shared.applyMetadata(to: &scanned)

        files = scanned.sorted { $0.modifiedAt > $1.modifiedAt }
        logger.info("Scanned vault files: \(scanned.count) items")

        // Persist each scanned file to SQLite in a single transaction. Base fields
        // (filename/size/type/createdAt/updatedAt) come from the scan; overlay
        // fields (title/notes/labels/ocr/colors) are applied by applyMetadata above.
        persistScannedFilesToDatabase(files)

        // Schedule enrichment for new un-enriched image files
        VaultFileEnrichment.shared.scheduleAll()
    }

    /// Persist all scanned vault files to SQLite in one transaction.
    private func persistScannedFilesToDatabase(_ files: [VaultFile]) {
        guard let db = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil else { return }
        do {
            try db.withTransaction {
                for file in files {
                    try VaultFileStorage.shared.persistVaultFileToDatabaseInner(db, file: file)
                }
            }
        } catch {
            logger.error("Failed to persist scanned vault files to SQLite: \(error.localizedDescription)")
        }
    }

    /// Starts watching the vault root for file changes and auto-rescanning.
    func startWatching() {
        stopWatching()
        let rootPath = vaultRoot.path
        watcher = FSEventsWatcher(path: rootPath, latency: 1.0) { [weak self] paths in
            // Skip events from .cider/ metadata writes to avoid scan-on-own-write loops
            let hasUserFileChange = paths.contains { !$0.contains("/.cider/") }
            guard hasUserFileChange else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isScanning {
                    self.pendingRescan = true
                } else {
                    self.scan()
                }
            }
        }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Queries

    func files(inFolder folderID: UUID?) -> [VaultFile] {
        files.filter { $0.folderID == folderID }
    }

    func files(ofType type: VaultFileType) -> [VaultFile] {
        files.filter { $0.fileType == type }
    }

    func file(for id: UUID) -> VaultFile? {
        files.first { $0.id == id }
    }

    // MARK: - Mutation

    /// Moves a vault file to a different folder by physically moving the file.
    /// The file's UUID is preserved across the move via the id-map sidecar, so
    /// labels/links/trash references remain valid.
    func assignFile(_ fileID: UUID, toFolder folderID: UUID?) {
        guard let index = files.firstIndex(where: { $0.id == fileID }) else { return }
        let file = files[index]
        let fm = FileManager.default

        let targetDir: URL
        if let folderID, let folder = VaultFolderService.shared.folder(for: folderID) {
            targetDir = vaultRoot.appendingPathComponent(folder.relativePath)
        } else {
            // Unfiled — move to appropriate Inbox subfolder
            targetDir = inboxDirectory(for: file.fileType)
        }
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        var destURL = targetDir.appendingPathComponent(file.filename)
        guard destURL != file.absoluteURL else { return }

        // Handle filename collision at destination
        if fm.fileExists(atPath: destURL.path) {
            let base = (file.filename as NSString).deletingPathExtension
            let ext = (file.filename as NSString).pathExtension
            var counter = 2
            while fm.fileExists(atPath: destURL.path) {
                destURL = targetDir.appendingPathComponent("\(base) (\(counter)).\(ext)")
                counter += 1
            }
        }

        do {
            try fm.moveItem(at: file.absoluteURL, to: destURL)

            // Remap id-map: SAME UUID at the new relative path.
            let oldRelativePath = file.relativePath
            let newRelativePath = destURL.path.replacingOccurrences(
                of: vaultRoot.path.hasSuffix("/") ? vaultRoot.path : vaultRoot.path + "/",
                with: ""
            )
            if !idMapLoaded {
                loadIDMap()
                idMapLoaded = true
            }
            idMap.removeValue(forKey: oldRelativePath)
            idMap[newRelativePath] = file.id
            saveIDMap()

            scan()
        } catch {
            logger.error("Failed to move vault file: \(error.localizedDescription)")
        }
    }

    /// Reinstates an id-map entry for a restored file. Called by
    /// `TrashStorage.restoreVaultFile` BEFORE `scan()` so the rescan finds the
    /// file at its (possibly collision-renamed) path and preserves the original
    /// UUID instead of minting a fresh one.
    func reinstateIDMapEntry(relativePath: String, uuid: UUID) {
        if !idMapLoaded {
            loadIDMap()
            idMapLoaded = true
        }
        idMap[relativePath] = uuid
        saveIDMap()
    }

    // MARK: - id-map sidecar

    private func loadIDMap() {
        guard let data = try? Data(contentsOf: idMapFileURL) else {
            idMap = [:]
            return
        }
        do {
            idMap = try JSONDecoder().decode([String: UUID].self, from: data)
            logger.info("Loaded vault file id-map: \(self.idMap.count) entries")
        } catch {
            logger.warning("Failed to decode vault file id-map: \(error.localizedDescription)")
            idMap = [:]
        }
    }

    private func saveIDMap() {
        let fm = FileManager.default
        try? fm.createDirectory(at: idMapDirectoryURL, withIntermediateDirectories: true)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let data = try encoder.encode(idMap)
            try data.write(to: idMapFileURL, options: .atomic)
        } catch {
            logger.error("Failed to save vault file id-map: \(error.localizedDescription)")
        }
    }

    /// Rebuilds the in-memory id-map from SQLite `items` rows when the sidecar
    /// is missing or empty. Recovers from a lost / corrupted / sync-conflicted
    /// `id-map.json` without re-running migration (which would mint fresh
    /// UUIDs and orphan all label/link/trash references).
    private func rebuildIDMapFromDatabase() {
        guard let db = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil else { return }
        do {
            let stmt = try db.prepare("""
                SELECT i.id, i.relative_path
                FROM items i
                JOIN vault_files vf ON vf.item_id = i.id
                WHERE i.type = 'vaultFile' AND i.relative_path IS NOT NULL;
                """)
            var rebuilt: [String: UUID] = [:]
            while try stmt.step() {
                guard let uuid = DatabaseHelpers.decodeUUID(stmt.string(at: 0)) else { continue }
                let path = stmt.optionalString(at: 1) ?? ""
                guard !path.isEmpty else { continue }
                rebuilt[path] = uuid
            }
            if !rebuilt.isEmpty {
                idMap = rebuilt
                saveIDMap()
                logger.info("Rebuilt vault file id-map from SQLite: \(rebuilt.count) entries")
            }
        } catch {
            logger.error("Failed to rebuild id-map from database: \(error.localizedDescription)")
        }
    }

    /// Looks up an existing vault-file UUID in SQLite by its relative path.
    /// Used to heal id-map drift: if the sidecar lost an entry but SQLite
    /// still has the row, adopt the existing UUID instead of minting a new
    /// one that would trip the items.relative_path UNIQUE constraint.
    private func lookupExistingVaultFileID(relativePath: String) -> UUID? {
        guard let db = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil else { return nil }
        do {
            let stmt = try db.prepare("""
                SELECT i.id FROM items i
                JOIN vault_files vf ON vf.item_id = i.id
                WHERE i.type = 'vaultFile' AND i.relative_path = ?
                LIMIT 1;
                """)
            stmt.bind(relativePath, at: 1)
            guard try stmt.step() else { return nil }
            return DatabaseHelpers.decodeUUID(stmt.string(at: 0))
        } catch {
            logger.error("Failed to look up existing vault file ID for path: \(error.localizedDescription)")
            return nil
        }
    }

    /// Migration ledger name for the path-derived → stable-UUID migration.
    private static let uuidStabilizationMigrationName = "vault_file_uuid_stabilization"

    /// Returns true if the one-time UUID stabilization migration has already
    /// been recorded in `schema_migrations`.
    private func hasRunOneTimeIDMigration() -> Bool {
        guard let db = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil else {
            // No DB available — fall back to the legacy "sidecar existed" test
            // so we don't run migration over and over in a broken environment.
            return FileManager.default.fileExists(atPath: idMapFileURL.path)
        }
        do {
            let stmt = try db.prepare("SELECT 1 FROM schema_migrations WHERE name = ? LIMIT 1;")
            stmt.bind(Self.uuidStabilizationMigrationName, at: 1)
            return try stmt.step()
        } catch {
            logger.error("Failed to check schema_migrations: \(error.localizedDescription)")
            return false
        }
    }

    /// Records that the one-time UUID stabilization migration has run.
    private func recordOneTimeIDMigration() {
        guard let db = CiderDatabase.shared.isOpen ? CiderDatabase.shared : nil else { return }
        do {
            let stmt = try db.prepare("INSERT OR REPLACE INTO schema_migrations (name, applied_at) VALUES (?, ?);")
            stmt.bind(Self.uuidStabilizationMigrationName, at: 1)
                .bind(Date().timeIntervalSince1970, at: 2)
            try stmt.step()
        } catch {
            logger.error("Failed to record schema_migrations row: \(error.localizedDescription)")
        }
    }

    /// One-time migration from path-derived UUIDs to stable UUIDs.
    ///
    /// Before this change, `VaultFile.id` was a SHA-256 hash of `relativePath`.
    /// That meant `VaultFileStorage`'s metadata index (`_cider_vault_files_index.json`)
    /// was keyed by those path-derived IDs. On the first run with the new code,
    /// we walk the filesystem, compute the OLD path-derived ID for each file,
    /// mint a FRESH UUID, update the id-map, and carry the old metadata entry
    /// over to the new UUID.
    private func runOneTimeIDMigration() {
        let fm = FileManager.default
        let root = vaultRoot
        var migratedCount = 0

        func migrateFile(at url: URL, relativePath: String) {
            // Basic filtering mirroring processFile (skip dirs/symlinks/cider-native).
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
            if resourceValues?.isDirectory == true { return }
            if resourceValues?.isSymbolicLink == true { return }
            let ext = url.pathExtension.lowercased()
            if Self.excludedExtensions.contains(ext) || ext.isEmpty { return }
            let fileSize = Int64(resourceValues?.fileSize ?? 0)
            guard fileSize > 0 else { return }

            let oldID = stableID(for: relativePath)
            let newID = UUID()
            idMap[relativePath] = newID
            // Carry any metadata keyed by the old path-derived ID over to the new UUID.
            VaultFileStorage.shared.migrateMetadata(from: oldID, to: newID)
            migratedCount += 1
        }

        // 1. User folders
        if let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            while let url = enumerator.nextObject() as? URL {
                let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                let relativePath = url.path.hasPrefix(rootPrefix) ? String(url.path.dropFirst(rootPrefix.count)) : url.path
                let components = relativePath.split(separator: "/").map(String.init)
                if let top = components.first, Self.excludedDirectoryPrefixes.contains(top) {
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                migrateFile(at: url, relativePath: relativePath)
            }
        }

        // 2. Inbox vault-file subdirectories
        let inboxRoot = root.appendingPathComponent("Inbox")
        for dirName in [Self.inboxImagesDirName, Self.inboxVideosDirName, Self.inboxFilesDirName] {
            let dirURL = inboxRoot.appendingPathComponent(dirName)
            guard fm.fileExists(atPath: dirURL.path) else { continue }
            if let enumerator = fm.enumerator(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                while let url = enumerator.nextObject() as? URL {
                    let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
                    let relativePath = url.path.hasPrefix(rootPrefix) ? String(url.path.dropFirst(rootPrefix.count)) : url.path
                    migrateFile(at: url, relativePath: relativePath)
                }
            }
        }

        saveIDMap()
        if migratedCount > 0 {
            logger.info("Migrated \(migratedCount) vault files from path-derived IDs to stable UUIDs")
        }
    }

    /// Refreshes metadata overlay on current files without a full disk rescan.
    /// Use after metadata-only changes (labels, title, notes) instead of scan().
    func refreshMetadata() {
        VaultFileStorage.shared.applyMetadata(to: &files)
        objectWillChange.send()
    }

    // MARK: - Private Helpers

    /// Returns the appropriate Inbox subdirectory for a file type.
    private func inboxDirectory(for fileType: VaultFileType) -> URL {
        let inboxRoot = vaultRoot.appendingPathComponent("Inbox")
        switch fileType {
        case .image:
            return inboxRoot.appendingPathComponent(Self.inboxImagesDirName)
        case .video:
            return inboxRoot.appendingPathComponent(Self.inboxVideosDirName)
        default:
            return inboxRoot.appendingPathComponent(Self.inboxFilesDirName)
        }
    }

    /// Processes a single URL from the enumerator into a VaultFile, or nil if it should be skipped.
    /// Resolves the file's stable UUID via the id-map sidecar, generating a fresh one
    /// if this path isn't yet known and marking `idMapDirty` so the caller saves it.
    private func processFile(url: URL, relativePath: String, idMapDirty: inout Bool) -> VaultFile? {
        // Skip directories and symlinks
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if resourceValues?.isDirectory == true { return nil }
        if resourceValues?.isSymbolicLink == true { return nil }

        // Skip Cider-native file types
        let ext = url.pathExtension.lowercased()
        if Self.excludedExtensions.contains(ext) || ext.isEmpty {
            return nil
        }

        let fileType = VaultFileType.from(extension: ext)
        let values = try? url.resourceValues(forKeys: [
            .fileSizeKey, .creationDateKey, .contentModificationDateKey
        ])

        let fileSize = Int64(values?.fileSize ?? 0)
        guard fileSize > 0 else { return nil } // Skip zero-byte files (in-progress writes, corrupted)
        let createdAt = values?.creationDate ?? Date()
        let modifiedAt = values?.contentModificationDate ?? Date()

        // Resolve stable UUID. SQLite is the source of truth because the
        // items.relative_path UNIQUE constraint enforces it — if the id-map
        // disagrees with SQLite, SQLite wins and we heal the id-map in place.
        // This covers three drift modes:
        //   1. id-map miss but SQLite has a row  → adopt SQLite's id
        //   2. id-map hit that matches SQLite    → use it (fast path)
        //   3. id-map hit that disagrees with SQLite → adopt SQLite's id
        // Without this, a stale id-map entry causes every rescan to try to
        // INSERT a new row at an existing relative_path and trip UNIQUE
        // indefinitely.
        let id: UUID
        if let dbID = lookupExistingVaultFileID(relativePath: relativePath) {
            id = dbID
            if idMap[relativePath] != dbID {
                idMap[relativePath] = dbID
                idMapDirty = true
            }
        } else if let existing = idMap[relativePath] {
            // No SQLite row yet — first persist for a newly-scanned file.
            id = existing
        } else {
            let fresh = UUID()
            idMap[relativePath] = fresh
            idMapDirty = true
            id = fresh
        }

        // Determine folder ID from the directory
        let dirPath = (relativePath as NSString).deletingLastPathComponent
        let folderID: UUID?
        let inboxPrefixes = [
            "Inbox/\(Self.inboxImagesDirName)",
            "Inbox/\(Self.inboxVideosDirName)",
            "Inbox/\(Self.inboxFilesDirName)",
            "Inbox"
        ]
        if dirPath.isEmpty || dirPath == "." || inboxPrefixes.contains(dirPath) {
            folderID = nil
        } else {
            folderID = VaultFolderService.shared.folders.first(where: { $0.relativePath == dirPath })?.id
        }

        return VaultFile(
            id: id,
            filename: url.lastPathComponent,
            relativePath: relativePath,
            fileType: fileType,
            fileSize: fileSize,
            createdAt: createdAt,
            modifiedAt: modifiedAt,
            folderID: folderID
        )
    }

    /// Derives a deterministic UUID from a vault-relative path using SHA-256.
    ///
    /// LEGACY: This is only used by the one-time migration path
    /// (`runOneTimeIDMigration`) to compute the OLD pre-migration IDs so that
    /// metadata keyed by them can be carried over to the new stable UUIDs.
    /// New code paths should resolve IDs via the id-map sidecar, not this function.
    private func stableID(for path: String) -> UUID {
        guard let data = path.data(using: .utf8) else { return UUID() }
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        _ = data.withUnsafeBytes { CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return NSUUID(uuidBytes: &bytes) as UUID
    }
}
