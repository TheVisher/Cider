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
}
