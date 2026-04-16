import Foundation
import os

/// Exports existing Cider data into portable vault files.
/// Creates `.webloc` files for bookmarks and ensures folders exist as real directories.
///
/// This is a one-time migration tool — safe to run multiple times (idempotent).
@MainActor
final class VaultMigrationService {
    static let shared = VaultMigrationService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "VaultMigration"
    )

    private var vaultRoot: URL { StoragePaths.cachedVaultDirectoryURL }

    struct MigrationResult {
        var foldersCreated = 0
        var weblocFilesCreated = 0
        var errors: [String] = []

        var summary: String {
            var parts: [String] = []
            if foldersCreated > 0 { parts.append("\(foldersCreated) folders created") }
            if weblocFilesCreated > 0 { parts.append("\(weblocFilesCreated) bookmark files exported") }
            if parts.isEmpty { parts.append("Everything already up to date") }
            if !errors.isEmpty { parts.append("\(errors.count) errors") }
            return parts.joined(separator: ", ")
        }
    }

    struct LegacySidecarCleanupResult {
        var noteSidecarFilesDeleted = 0
        var bookmarkSidecarFilesDeleted = 0
        var bookmarkSidecarFilesSkipped = 0
        var errors: [String] = []

        var summary: String {
            var parts: [String] = []
            if noteSidecarFilesDeleted > 0 { parts.append("\(noteSidecarFilesDeleted) note sidecars removed") }
            if bookmarkSidecarFilesDeleted > 0 { parts.append("\(bookmarkSidecarFilesDeleted) bookmark sidecars removed") }
            if bookmarkSidecarFilesSkipped > 0 {
                parts.append("\(bookmarkSidecarFilesSkipped) bookmark sidecars left in place until bookmark import runs")
            }
            if parts.isEmpty { parts.append("No legacy sidecars found") }
            if !errors.isEmpty { parts.append("\(errors.count) errors") }
            return parts.joined(separator: ", ")
        }
    }

    // MARK: - Public

    func runFullMigration() async -> MigrationResult {
        var result = MigrationResult()
        logger.info("Starting vault migration…")

        migrateFolders(&result)
        migrateBookmarks(&result)
        migrateNotes(&result)
        logger.info("Migration complete: \(result.summary)")
        return result
    }

    func removeLegacySidecars() -> LegacySidecarCleanupResult {
        var result = LegacySidecarCleanupResult()
        let fm = FileManager.default
        let config = CiderConfig.load()

        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else {
            result.errors.append("Could not enumerate vault for legacy sidecars")
            return result
        }

        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            guard name == ".cider-meta.json" || name == BookmarkFileService.sidecarFileName else { continue }
            if shouldSkipLegacySidecar(at: url) { continue }

            if name == BookmarkFileService.sidecarFileName && !config.didMigrateBookmarkSidecarsToSQLite {
                result.bookmarkSidecarFilesSkipped += 1
                continue
            }

            do {
                try fm.removeItem(at: url)
                if name == ".cider-meta.json" {
                    result.noteSidecarFilesDeleted += 1
                } else {
                    result.bookmarkSidecarFilesDeleted += 1
                }
            } catch {
                result.errors.append("Failed to remove \(url.path): \(error.localizedDescription)")
            }
        }

        logger.info("Legacy sidecar cleanup complete: \(result.summary)")
        return result
    }

    // MARK: - Folders

    /// Ensures every legacy Folder has a corresponding real vault directory.
    private func migrateFolders(_ result: inout MigrationResult) {
        let legacyFolders = BookmarksStorage.shared.folders
        let vaultFolderService = VaultFolderService.shared
        let existingPaths = Set(vaultFolderService.folders.map(\.relativePath))

        for folder in legacyFolders {
            // Check if a VaultFolder already exists with the same name
            let name = VaultFolderService.sanitizeDirectoryName(folder.name)
            guard !name.isEmpty else { continue }

            // Check by folder name (not ID — legacy and vault folders have different IDs)
            if existingPaths.contains(name) { continue }

            // Also check if the folder is nested
            let parentPath: String?
            if let parentID = folder.parentID,
               let parent = legacyFolders.first(where: { $0.id == parentID }) {
                parentPath = VaultFolderService.sanitizeDirectoryName(parent.name)
            } else {
                parentPath = nil
            }

            let fullPath = parentPath.map { "\($0)/\(name)" } ?? name
            if existingPaths.contains(fullPath) { continue }

            // Create the vault folder
            if vaultFolderService.createFolder(name: folder.name, parentID: parentID(for: folder.parentID, in: vaultFolderService)) != nil {
                result.foldersCreated += 1
                logger.info("Created vault directory for legacy folder: \(folder.name)")
            } else {
                result.errors.append("Failed to create folder: \(folder.name)")
            }
        }
    }

    /// Resolves a legacy folder parent ID to a VaultFolder parent ID.
    private func parentID(for legacyParentID: UUID?, in service: VaultFolderService) -> UUID? {
        guard let legacyParentID else { return nil }
        guard let legacyParent = BookmarksStorage.shared.folders.first(where: { $0.id == legacyParentID }) else { return nil }
        let name = VaultFolderService.sanitizeDirectoryName(legacyParent.name)
        return service.folders.first(where: { $0.relativePath == name })?.id
    }

    // MARK: - Bookmarks

    /// Exports each bookmark as a `.webloc` file.
    private func migrateBookmarks(_ result: inout MigrationResult) {
        let bookmarks = BookmarksStorage.shared.bookmarks
        let fm = FileManager.default

        for bookmark in bookmarks {
            // Determine target directory
            let (dirURL, _) = resolveDirectory(for: bookmark.folderID, fallback: StorageType.bookmarks.ciderSubpath)

            // Create .webloc file if bookmark has a URL
            if bookmark.hasURL, let url = bookmark.url {
                let baseName = sanitizeFilename(bookmark.title.isEmpty ? "Untitled" : bookmark.title)
                let filename = BookmarkFileService.shared.uniqueFilename(for: baseName, extension: "webloc", in: dirURL)
                let fileURL = dirURL.appendingPathComponent(filename)

                if !fm.fileExists(atPath: fileURL.path) {
                    let plist: [String: String] = ["URL": url.absoluteString]
                    if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
                        do {
                            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
                            try data.write(to: fileURL, options: .atomic)
                            result.weblocFilesCreated += 1
                        } catch {
                            result.errors.append("Failed to write \(filename): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Notes

    /// Notes no longer need export-time sidecar regeneration.
    private func migrateNotes(_ result: inout MigrationResult) {
        _ = result
    }

    // MARK: - Helpers

    /// Resolves a folder ID to a real directory URL and its vault-relative path.
    private func resolveDirectory(for folderID: UUID?, fallback: String) -> (URL, String) {
        if let folderID {
            // Try VaultFolder first
            if let vaultFolder = VaultFolderService.shared.folders.first(where: { $0.id == folderID }) {
                let dirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                return (dirURL, vaultFolder.relativePath)
            }
            // Try legacy folder → find matching VaultFolder by name
            if let legacyFolder = BookmarksStorage.shared.folders.first(where: { $0.id == folderID }) {
                let name = VaultFolderService.sanitizeDirectoryName(legacyFolder.name)
                if let vaultFolder = VaultFolderService.shared.folders.first(where: { $0.relativePath == name }) {
                    let dirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                    return (dirURL, vaultFolder.relativePath)
                }
            }
        }
        // Fallback to type directory inside .cider/
        let ciderPath = "\(StoragePaths.ciderInternalDir)/\(fallback)"
        let dirURL = vaultRoot.appendingPathComponent(ciderPath)
        return (dirURL, ciderPath)
    }

    /// Sanitizes a string for use as a filename (removes invalid characters).
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = name.components(separatedBy: invalid).joined(separator: "-")
        // Trim to reasonable length
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }
        return sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldSkipLegacySidecar(at url: URL) -> Bool {
        let components = url.pathComponents
        return components.contains(".trash") || components.contains(StoragePaths.ciderInternalDir)
    }
}
