import Foundation
import os

/// Exports existing Cider data into portable vault files.
/// Creates .webloc files for bookmarks, ensures folders exist as real directories,
/// and writes comprehensive sidecar metadata for all items.
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
        var bookmarkSidecarsWritten = 0
        var noteSidecarsWritten = 0
        var todoSidecarsWritten = 0
        var errors: [String] = []

        var summary: String {
            var parts: [String] = []
            if foldersCreated > 0 { parts.append("\(foldersCreated) folders created") }
            if weblocFilesCreated > 0 { parts.append("\(weblocFilesCreated) bookmark files exported") }
            if bookmarkSidecarsWritten > 0 { parts.append("\(bookmarkSidecarsWritten) bookmark metadata written") }
            if noteSidecarsWritten > 0 { parts.append("\(noteSidecarsWritten) note metadata written") }
            if todoSidecarsWritten > 0 { parts.append("\(todoSidecarsWritten) todo metadata written") }
            if parts.isEmpty { parts.append("Everything already up to date") }
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
        migrateTodos(&result)

        logger.info("Migration complete: \(result.summary)")
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

    /// Exports each bookmark as a .webloc file and writes sidecar metadata.
    private func migrateBookmarks(_ result: inout MigrationResult) {
        let bookmarks = BookmarksStorage.shared.bookmarks
        let fm = FileManager.default

        for bookmark in bookmarks {
            // Determine target directory
            let (dirURL, dirRelativePath) = resolveDirectory(for: bookmark.folderID, fallback: StorageType.bookmarks.ciderSubpath)

            // Create .webloc file if bookmark has a URL
            if bookmark.hasURL, let url = bookmark.url {
                let filename = sanitizeFilename(bookmark.title.isEmpty ? "Untitled" : bookmark.title) + ".webloc"
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

                // Write sidecar metadata
                writeSidecarForBookmark(bookmark, filename: filename, dirRelativePath: dirRelativePath, result: &result)
            }
        }
    }

    private func writeSidecarForBookmark(_ bookmark: Bookmark, filename: String, dirRelativePath: String, result: inout MigrationResult) {
        // Build tag list: merge string tags + label names
        var allTags = bookmark.tags
        let labelNames = bookmark.labelIDs.compactMap { CardLabelStorage.shared.label(for: $0)?.name }
        for name in labelNames where !allTags.contains(name) {
            allTags.append(name)
        }

        var meta = SidecarItemMetadata()
        meta.tags = allTags.isEmpty ? nil : allTags.sorted()
        meta.summary = bookmark.aiSummary
        meta.date = ISO8601DateFormatter().string(from: bookmark.createdAt)

        // Store extra fields AI tools might find useful
        var extra: [String: AnyCodableValue] = [:]
        if !bookmark.urlString.isEmpty {
            extra["url"] = .string(bookmark.urlString)
        }
        if !bookmark.notes.isEmpty {
            extra["notes"] = .string(bookmark.notes)
        }
        if let colors = bookmark.dominantColors, !colors.isEmpty {
            extra["dominantColors"] = .array(colors.map { .string($0) })
        }
        if !extra.isEmpty {
            meta.extra = extra
        }

        if !meta.isEmpty {
            SidecarService.shared.setMetadata(meta, for: filename, inDirectory: dirRelativePath)
            result.bookmarkSidecarsWritten += 1
        }
    }

    // MARK: - Notes

    /// Writes sidecar metadata for all notes.
    private func migrateNotes(_ result: inout MigrationResult) {
        let notes = NotesStorage.shared.notes

        for note in notes {
            SidecarService.shared.syncNote(note)
            result.noteSidecarsWritten += 1
        }
    }

    // MARK: - Todos

    /// Writes sidecar metadata for all todos.
    private func migrateTodos(_ result: inout MigrationResult) {
        let todos = TodoCardStorage.shared.todoCards

        for todo in todos {
            let filename = "\(todo.id).json"
            let dirRelativePath = "\(StoragePaths.ciderInternalDir)/\(StorageType.todos.ciderSubpath)"

            var meta = SidecarItemMetadata()
            let labelNames = todo.labelIDs.compactMap { CardLabelStorage.shared.label(for: $0)?.name }
            meta.tags = labelNames.isEmpty ? nil : labelNames.sorted()

            if let dueDate = todo.dueDate {
                meta.date = ISO8601DateFormatter().string(from: dueDate)
            }

            var extra: [String: AnyCodableValue] = [:]
            extra["title"] = .string(todo.title)
            if !todo.details.isEmpty {
                extra["details"] = .string(todo.details)
            }
            if let priority = todo.priority {
                extra["priority"] = .string(priority.rawValue)
            }
            extra["isCompleted"] = .bool(todo.isCompleted)
            meta.extra = extra

            if !meta.isEmpty {
                SidecarService.shared.setMetadata(meta, for: filename, inDirectory: dirRelativePath)
                result.todoSidecarsWritten += 1
            }
        }
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
}
