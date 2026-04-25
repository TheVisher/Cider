import Foundation
import os

/// Ensures existing Cider data has portable vault files.
/// Creates missing `.webloc` artifacts for SQLite-backed bookmarks.
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

    // MARK: - Bookmarks

    /// Ensures each live SQLite-backed bookmark has a `.webloc` file.
    private func migrateBookmarks(_ result: inout MigrationResult) {
        let bookmarks = VaultBookmarkService.shared.bookmarks
        let fm = FileManager.default

        for var bookmark in bookmarks {
            if let relativePath = bookmark.relativePath,
               fm.fileExists(atPath: vaultRoot.appendingPathComponent(relativePath).path) {
                continue
            }

            // Determine target directory
            let (dirURL, dirRelativePath) = resolveDirectory(for: bookmark.folderID)

            // Create .webloc file if bookmark has a URL
            if bookmark.hasURL {
                do {
                    bookmark.relativePath = try BookmarkFileService.shared.write(
                        bookmark: bookmark,
                        toDirectory: dirURL,
                        dirRelativePath: dirRelativePath
                    )
                    VaultBookmarkService.shared.persistBookmarkToDatabase(bookmark)
                    result.weblocFilesCreated += 1
                } catch {
                    result.errors.append("Failed to write \(bookmark.title): \(error.localizedDescription)")
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
    private func resolveDirectory(for folderID: UUID?) -> (URL, String) {
        if let folderID {
            if let vaultFolder = VaultFolderService.shared.folders.first(where: { $0.id == folderID }) {
                let dirURL = vaultRoot.appendingPathComponent(vaultFolder.relativePath)
                return (dirURL, vaultFolder.relativePath)
            }
        }
        let dirURL = StoragePaths.cachedInboxSubdirectoryURL(for: .bookmarks)
        let relativePath = "\(StoragePaths.inboxDir)/\(StorageType.bookmarks.inboxSubfolderName ?? "Bookmarks")"
        return (dirURL, relativePath)
    }

    private func shouldSkipLegacySidecar(at url: URL) -> Bool {
        let components = url.pathComponents
        return components.contains(".trash") || components.contains(StoragePaths.ciderInternalDir)
    }
}
