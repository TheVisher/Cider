import Foundation
import os

/// One-time migration that moves all app-internal directories from the vault root
/// into the hidden `.cider/` subdirectory. After migration, the vault root contains
/// only user-visible folders (plus CLAUDE.md and Unsorted/).
enum VaultStructureMigration {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultStructureMigration"
    )

    /// Old directory name → new name inside `.cider/`.
    private static let directoryMappings: [(old: String, new: String)] = {
        var mappings: [(String, String)] = StorageType.allCases.map { type in
            (type.rawValue, type.ciderSubpath)
        }
        // Non-StorageType directories
        mappings.append((".cider-folders", "folders"))
        mappings.append(("AI Chat", "ai-chat"))
        mappings.append((".ai", "ai"))
        return mappings
    }()

    /// Runs the migration if it hasn't been completed yet.
    /// Call before `StoragePaths.ensureVaultStructure()` in AppDelegate.
    static func migrateIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateVaultToCiderDir else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let ciderDir = vaultRoot.appendingPathComponent(StoragePaths.ciderInternalDir)

        logger.info("Starting vault → .cider/ migration")

        // Create .cider/ parent
        do {
            try fm.createDirectory(at: ciderDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create .cider/ directory: \(error.localizedDescription)")
            return
        }

        // Move each old directory to new location
        for mapping in directoryMappings {
            let source = vaultRoot.appendingPathComponent(mapping.old)
            let dest = ciderDir.appendingPathComponent(mapping.new)

            guard fm.fileExists(atPath: source.path) else {
                logger.info("Skipping \(mapping.old) — does not exist")
                continue
            }

            if fm.fileExists(atPath: dest.path) {
                logger.info("Skipping \(mapping.old) → .cider/\(mapping.new) — destination already exists")
                continue
            }

            do {
                try fm.moveItem(at: source, to: dest)
                logger.info("Moved \(mapping.old) → .cider/\(mapping.new)")
            } catch {
                logger.error("Failed to move \(mapping.old): \(error.localizedDescription)")
            }
        }

        // Move .cider-index.json → .cider/index.json
        let oldIndex = vaultRoot.appendingPathComponent(".cider-index.json")
        let newIndex = ciderDir.appendingPathComponent("index.json")
        if fm.fileExists(atPath: oldIndex.path) && !fm.fileExists(atPath: newIndex.path) {
            do {
                try fm.moveItem(at: oldIndex, to: newIndex)
                logger.info("Moved .cider-index.json → .cider/index.json")
            } catch {
                logger.error("Failed to move index: \(error.localizedDescription)")
            }
        }

        // Invalidate cached paths so they resolve to the new locations
        StoragePaths.invalidateCachedDirectory()

        // Set flag and save
        config.didMigrateVaultToCiderDir = true
        config.save()

        logger.info("Vault → .cider/ migration complete")
    }

    // MARK: - Phase 2: Move content files from .cider/ to Inbox/

    /// Moves .webloc files from .cider/bookmarks/ to Inbox/Bookmarks/ and
    /// .md files from .cider/notes/ to Inbox/Notes/.
    /// Metadata files (_cider_bookmarks_metadata.json, _cider_notes_index.json, etc.) stay in .cider/.
    /// Call after `migrateIfNeeded()` and before storage services initialize.
    static func migrateContentToInboxIfNeeded() {
        var config = CiderConfig.load()
        guard !config.didMigrateContentToInbox else { return }

        let fm = FileManager.default
        let vaultRoot = StoragePaths.vaultDirectoryURL(config: config)
        let ciderDir = vaultRoot.appendingPathComponent(StoragePaths.ciderInternalDir)
        let inboxDir = vaultRoot.appendingPathComponent(StoragePaths.inboxDir)

        logger.info("Starting .cider/ → Inbox/ content migration")

        // --- Bookmarks: move .webloc files + sidecar + assets ---
        let ciderBookmarksDir = ciderDir.appendingPathComponent(StorageType.bookmarks.ciderSubpath)
        let inboxBookmarksDir = inboxDir.appendingPathComponent("Bookmarks")

        do {
            try fm.createDirectory(at: inboxBookmarksDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Inbox/Bookmarks/: \(error.localizedDescription)")
        }

        // Move .webloc files and per-folder sidecar JSONs from .cider/bookmarks/ → Inbox/Bookmarks/
        // Keep: _cider_bookmarks_metadata.json (master metadata), .thumbnails/, .originals/, .trash/
        let bookmarkKeepPrefixes: Set<String> = ["_cider_bookmarks_metadata.json", ".thumbnails", ".originals", ".trash"]
        if let contents = try? fm.contentsOfDirectory(at: ciderBookmarksDir, includingPropertiesForKeys: nil) {
            for item in contents {
                let name = item.lastPathComponent
                if bookmarkKeepPrefixes.contains(name) { continue }

                let dest = inboxBookmarksDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dest.path) { continue }
                do {
                    try fm.moveItem(at: item, to: dest)
                } catch {
                    logger.error("Failed to move bookmark content \(name): \(error.localizedDescription)")
                }
            }
        }

        // Update bookmark relativePaths in the master metadata JSON
        updateBookmarkMetadataPaths(
            metadataURL: ciderBookmarksDir.appendingPathComponent("_cider_bookmarks_metadata.json"),
            oldPrefix: "\(StoragePaths.ciderInternalDir)/\(StorageType.bookmarks.ciderSubpath)",
            newPrefix: "\(StoragePaths.inboxDir)/Bookmarks"
        )

        // --- Notes: move .md files + .attachments/ + .history/ ---
        let ciderNotesDir = ciderDir.appendingPathComponent(StorageType.notes.ciderSubpath)
        let inboxNotesDir = inboxDir.appendingPathComponent("Notes")

        do {
            try fm.createDirectory(at: inboxNotesDir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create Inbox/Notes/: \(error.localizedDescription)")
        }

        // Move only .md files from .cider/notes/ → Inbox/Notes/
        // Keep: index file, .history/ (snapshots), .attachments/, .trash/
        let noteKeepNames: Set<String> = ["_cider_notes_index.json", ".trash", ".history", ".attachments"]
        if let contents = try? fm.contentsOfDirectory(at: ciderNotesDir, includingPropertiesForKeys: nil) {
            for item in contents {
                let name = item.lastPathComponent
                if noteKeepNames.contains(name) { continue }

                let dest = inboxNotesDir.appendingPathComponent(name)
                if fm.fileExists(atPath: dest.path) { continue }
                do {
                    try fm.moveItem(at: item, to: dest)
                } catch {
                    logger.error("Failed to move note content \(name): \(error.localizedDescription)")
                }
            }
        }

        // Create remaining Inbox subfolders for future use
        for typeName in ["Contacts", "Todos", "Date Cards"] {
            let subdir = inboxDir.appendingPathComponent(typeName)
            try? fm.createDirectory(at: subdir, withIntermediateDirectories: true)
        }

        // Invalidate cached paths
        StoragePaths.invalidateCachedDirectory()

        config.didMigrateContentToInbox = true
        config.save()

        logger.info(".cider/ → Inbox/ content migration complete")
    }

    /// Updates bookmark relativePath entries in the master metadata JSON file.
    /// Bookmarks with paths starting with `oldPrefix` get rewritten to `newPrefix`.
    private static func updateBookmarkMetadataPaths(metadataURL: URL, oldPrefix: String, newPrefix: String) {
        guard let data = try? Data(contentsOf: metadataURL) else { return }
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        guard var bookmarks = json["bookmarks"] as? [[String: Any]] else { return }

        var changed = false
        for i in bookmarks.indices {
            if let path = bookmarks[i]["relativePath"] as? String,
               path.hasPrefix(oldPrefix) {
                bookmarks[i]["relativePath"] = newPrefix + path.dropFirst(oldPrefix.count)
                changed = true
            }
        }

        guard changed else { return }
        json["bookmarks"] = bookmarks

        if let updatedData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? updatedData.write(to: metadataURL, options: .atomic)
            logger.info("Updated \(bookmarks.count) bookmark paths in metadata")
        }
    }
}
