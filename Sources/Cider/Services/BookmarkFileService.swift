import Foundation
import os

/// Manages individual `.webloc` files and per-folder `_cider_bookmarks.json` sidecars.
///
/// Each bookmark is stored as a macOS `.webloc` plist file (URL only) plus an entry
/// in the folder's sidecar JSON (all Cider metadata — tags, labels, thumbnails, etc.).
///
/// This service handles:
/// - Writing/reading `.webloc` files
/// - Per-folder sidecar persistence
/// - Filename sanitization and collision handling
/// - Moving bookmarks between folders (files + image assets)
/// - Deleting bookmarks (files + image assets + sidecar cleanup)
@MainActor
final class BookmarkFileService {
    static let shared = BookmarkFileService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "BookmarkFileService"
    )

    static let sidecarFileName = "_cider_bookmarks.json"
    static let thumbnailsDir = ".thumbnails"
    static let originalsDir = ".originals"

    private let fm = FileManager.default

    private init() {}

    // MARK: - Sidecar Model

    /// Per-folder sidecar file mapping filenames → bookmark metadata.
    struct BookmarkFolderSidecar: Codable {
        var items: [String: BookmarkSidecarEntry]

        init(items: [String: BookmarkSidecarEntry] = [:]) {
            self.items = items
        }
    }

    /// All Cider-internal metadata for a single bookmark (everything except the URL,
    /// which lives in the `.webloc` file itself).
    struct BookmarkSidecarEntry: Codable {
        var id: UUID
        var title: String
        var createdAt: Date
        var updatedAt: Date
        var notes: String
        var tags: [String]
        var labelIDs: [UUID]
        var dismissedLabelIDs: [UUID]
        var thumbnailRemoteURLString: String?
        var thumbnailFilename: String?
        var originalImageFilename: String?
        var metadataUpdatedAt: Date?
        var aiSummary: String?
        var ocrText: String?
        var dominantColors: [String]?
        var mediaType: BookmarkMediaType?
        var carouselImageFilenames: [String]?
        var readerUnavailable: Bool?
        var preferredHeroMode: String?
    }

    // MARK: - Write

    /// Writes a bookmark as a `.webloc` file and updates the folder's sidecar.
    /// Returns the vault-relative path of the written file (e.g. `"Entertainment/YouTube - Some Video.webloc"`).
    @discardableResult
    func write(bookmark: Bookmark, toDirectory dirURL: URL, dirRelativePath: String) throws -> String {
        // Create .webloc
        let filename = uniqueFilename(
            for: sanitizedFilename(bookmark.title.isEmpty ? "Untitled" : bookmark.title),
            extension: "webloc",
            in: dirURL
        )
        let fileURL = dirURL.appendingPathComponent(filename)

        if bookmark.hasURL, let url = bookmark.url {
            let plist: [String: String] = ["URL": url.absoluteString]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try fm.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
        }

        // Update sidecar
        let entry = sidecarEntry(from: bookmark)
        updateSidecar(at: dirURL, setting: filename, to: entry)

        let relativePath = dirRelativePath.isEmpty ? filename : "\(dirRelativePath)/\(filename)"
        logger.info("Wrote bookmark file: \(relativePath)")
        return relativePath
    }

    // MARK: - Read

    /// Reads a single `.webloc` file + its sidecar entry and returns a `Bookmark`.
    func read(filename: String, from dirURL: URL, dirRelativePath: String) -> Bookmark? {
        let fileURL = dirURL.appendingPathComponent(filename)

        // Read URL from .webloc plist
        guard let data = try? Data(contentsOf: fileURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String],
              let urlString = plist["URL"] else {
            return nil
        }

        // Read sidecar entry
        let sidecar = loadSidecar(at: dirURL)
        let entry = sidecar.items[filename]

        let relativePath = dirRelativePath.isEmpty ? filename : "\(dirRelativePath)/\(filename)"

        return Bookmark(
            id: entry?.id ?? UUID(),
            title: entry?.title ?? titleFromFilename(filename),
            urlString: urlString,
            createdAt: entry?.createdAt ?? Date(),
            updatedAt: entry?.updatedAt ?? Date(),
            notes: entry?.notes ?? "",
            tags: entry?.tags ?? [],
            labelIDs: entry?.labelIDs ?? [],
            dismissedLabelIDs: entry?.dismissedLabelIDs ?? [],
            folderID: nil, // derived from directory, not stored
            thumbnailRemoteURLString: entry?.thumbnailRemoteURLString,
            thumbnailRelativePath: entry?.thumbnailFilename.map { "\(Self.thumbnailsDir)/\($0)" },
            originalImageRelativePath: entry?.originalImageFilename.map { "\(Self.originalsDir)/\($0)" },
            metadataUpdatedAt: entry?.metadataUpdatedAt,
            aiSummary: entry?.aiSummary,
            ocrText: entry?.ocrText,
            dominantColors: entry?.dominantColors,
            mediaType: entry?.mediaType,
            carouselImagePaths: entry?.carouselImageFilenames,
            readerUnavailable: entry?.readerUnavailable,
            preferredHeroMode: entry?.preferredHeroMode,
            relativePath: relativePath
        )
    }

    /// Scans a directory for all `.webloc` files and returns bookmarks.
    func readAll(from dirURL: URL, dirRelativePath: String) -> [Bookmark] {
        guard let contents = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil) else {
            return []
        }
        return contents
            .filter { $0.pathExtension.lowercased() == "webloc" }
            .compactMap { read(filename: $0.lastPathComponent, from: dirURL, dirRelativePath: dirRelativePath) }
    }

    // MARK: - Move

    /// Moves a bookmark from one folder to another, including its `.webloc` file and image assets.
    func move(
        bookmark: Bookmark,
        filename: String,
        from sourceDirURL: URL,
        to destDirURL: URL,
        destDirRelativePath: String
    ) throws -> String {
        let destFilename = uniqueFilename(
            for: sanitizedFilename(bookmark.title.isEmpty ? "Untitled" : bookmark.title),
            extension: "webloc",
            in: destDirURL
        )

        try fm.createDirectory(at: destDirURL, withIntermediateDirectories: true)

        // Move .webloc file
        let sourceFileURL = sourceDirURL.appendingPathComponent(filename)
        let destFileURL = destDirURL.appendingPathComponent(destFilename)
        try fm.moveItem(at: sourceFileURL, to: destFileURL)

        // Move thumbnail if present
        let sidecar = loadSidecar(at: sourceDirURL)
        if let entry = sidecar.items[filename] {
            if let thumbName = entry.thumbnailFilename {
                moveAsset(named: thumbName, subdir: Self.thumbnailsDir, from: sourceDirURL, to: destDirURL)
            }
            if let origName = entry.originalImageFilename {
                moveAsset(named: origName, subdir: Self.originalsDir, from: sourceDirURL, to: destDirURL)
            }
            if let carousel = entry.carouselImageFilenames {
                for name in carousel {
                    moveAsset(named: name, subdir: Self.originalsDir, from: sourceDirURL, to: destDirURL)
                }
            }
        }

        // Update sidecars: remove from source, add to dest
        let entry = sidecar.items[filename] ?? sidecarEntry(from: bookmark)
        removeSidecarEntry(at: sourceDirURL, filename: filename)
        updateSidecar(at: destDirURL, setting: destFilename, to: entry)

        let relativePath = destDirRelativePath.isEmpty ? destFilename : "\(destDirRelativePath)/\(destFilename)"
        logger.info("Moved bookmark: \(filename) → \(relativePath)")
        return relativePath
    }

    // MARK: - Delete

    /// Deletes a bookmark's `.webloc` file, image assets, and sidecar entry.
    func delete(filename: String, from dirURL: URL) {
        // Remove .webloc file
        let fileURL = dirURL.appendingPathComponent(filename)
        try? fm.removeItem(at: fileURL)

        // Remove image assets
        let sidecar = loadSidecar(at: dirURL)
        if let entry = sidecar.items[filename] {
            if let thumbName = entry.thumbnailFilename {
                let thumbURL = dirURL.appendingPathComponent(Self.thumbnailsDir).appendingPathComponent(thumbName)
                try? fm.removeItem(at: thumbURL)
            }
            if let origName = entry.originalImageFilename {
                let origURL = dirURL.appendingPathComponent(Self.originalsDir).appendingPathComponent(origName)
                try? fm.removeItem(at: origURL)
            }
            if let carousel = entry.carouselImageFilenames {
                for name in carousel {
                    let url = dirURL.appendingPathComponent(Self.originalsDir).appendingPathComponent(name)
                    try? fm.removeItem(at: url)
                }
            }
        }

        // Remove sidecar entry
        removeSidecarEntry(at: dirURL, filename: filename)
        logger.info("Deleted bookmark file: \(filename)")
    }

    // MARK: - Sidecar I/O

    func loadSidecar(at dirURL: URL) -> BookmarkFolderSidecar {
        let fileURL = dirURL.appendingPathComponent(Self.sidecarFileName)
        guard let data = try? Data(contentsOf: fileURL) else {
            return BookmarkFolderSidecar()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(BookmarkFolderSidecar.self, from: data)) ?? BookmarkFolderSidecar()
    }

    private func writeSidecar(_ sidecar: BookmarkFolderSidecar, at dirURL: URL) {
        let fileURL = dirURL.appendingPathComponent(Self.sidecarFileName)

        if sidecar.items.isEmpty {
            try? fm.removeItem(at: fileURL)
            return
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(sidecar) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func updateSidecar(at dirURL: URL, setting filename: String, to entry: BookmarkSidecarEntry) {
        var sidecar = loadSidecar(at: dirURL)
        sidecar.items[filename] = entry
        writeSidecar(sidecar, at: dirURL)
    }

    private func removeSidecarEntry(at dirURL: URL, filename: String) {
        var sidecar = loadSidecar(at: dirURL)
        sidecar.items.removeValue(forKey: filename)
        writeSidecar(sidecar, at: dirURL)
    }

    // MARK: - Filename Helpers

    /// Sanitizes a title for use as a filename. Removes characters invalid on macOS.
    func sanitizedFilename(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?*\"<>|")
        var sanitized = title.components(separatedBy: invalid).joined(separator: "-")
        // Remove leading dots (hidden files on macOS)
        while sanitized.hasPrefix(".") { sanitized = String(sanitized.dropFirst()) }
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        // Truncate to leave room for extension + collision suffix
        if sanitized.count > 200 {
            sanitized = String(sanitized.prefix(200))
        }
        return sanitized.isEmpty ? "Untitled" : sanitized
    }

    /// Returns a unique filename in the directory, appending ` (2)`, ` (3)`, etc. if needed.
    func uniqueFilename(for baseName: String, extension ext: String, in dirURL: URL) -> String {
        let candidate = "\(baseName).\(ext)"
        let candidateURL = dirURL.appendingPathComponent(candidate)
        if !fm.fileExists(atPath: candidateURL.path) {
            return candidate
        }

        var counter = 2
        while true {
            let numbered = "\(baseName) (\(counter)).\(ext)"
            let numberedURL = dirURL.appendingPathComponent(numbered)
            if !fm.fileExists(atPath: numberedURL.path) {
                return numbered
            }
            counter += 1
        }
    }

    /// Extracts a display title from a `.webloc` filename (strips extension).
    private func titleFromFilename(_ filename: String) -> String {
        (filename as NSString).deletingPathExtension
    }

    // MARK: - Asset Helpers

    /// Moves a single image asset between folder hidden directories.
    private func moveAsset(named name: String, subdir: String, from sourceDir: URL, to destDir: URL) {
        let sourceURL = sourceDir.appendingPathComponent(subdir).appendingPathComponent(name)
        guard fm.fileExists(atPath: sourceURL.path) else { return }

        let destSubdirURL = destDir.appendingPathComponent(subdir)
        try? fm.createDirectory(at: destSubdirURL, withIntermediateDirectories: true)
        let destURL = destSubdirURL.appendingPathComponent(name)
        try? fm.moveItem(at: sourceURL, to: destURL)
    }

    // MARK: - Conversion Helpers

    /// Creates a sidecar entry from a Bookmark model.
    func sidecarEntry(from bookmark: Bookmark) -> BookmarkSidecarEntry {
        BookmarkSidecarEntry(
            id: bookmark.id,
            title: bookmark.title,
            createdAt: bookmark.createdAt,
            updatedAt: bookmark.updatedAt,
            notes: bookmark.notes,
            tags: bookmark.tags,
            labelIDs: bookmark.labelIDs,
            dismissedLabelIDs: bookmark.dismissedLabelIDs,
            thumbnailRemoteURLString: bookmark.thumbnailRemoteURLString,
            thumbnailFilename: bookmark.thumbnailRelativePath.map { ($0 as NSString).lastPathComponent },
            originalImageFilename: bookmark.originalImageRelativePath.map { ($0 as NSString).lastPathComponent },
            metadataUpdatedAt: bookmark.metadataUpdatedAt,
            aiSummary: bookmark.aiSummary,
            ocrText: bookmark.ocrText,
            dominantColors: bookmark.dominantColors,
            mediaType: bookmark.mediaType,
            carouselImageFilenames: bookmark.carouselImagePaths?.map { ($0 as NSString).lastPathComponent },
            readerUnavailable: bookmark.readerUnavailable,
            preferredHeroMode: bookmark.preferredHeroMode
        )
    }
}
