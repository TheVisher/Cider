import Combine
import Foundation
import os

/// Reads and writes `.cider-meta.json` sidecar files in the vault.
/// AI tools and Cider both use this format — one JSON file per directory
/// mapping filenames to their metadata (tags, summaries, dates, etc.).
@MainActor
final class SidecarService: ObservableObject {
    static let shared = SidecarService()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Cider",
        category: "SidecarService"
    )

    static let sidecarFileName = ".cider-meta.json"

    /// Cached sidecar files keyed by directory path (relative to vault root).
    /// Empty string key = vault root directory.
    @Published private(set) var cache: [String: SidecarFile] = [:]

    private var vaultRoot: URL { StoragePaths.cachedVaultDirectoryURL }

    private init() {}

    // MARK: - Reading

    /// Returns metadata for a specific file in the vault.
    /// - Parameters:
    ///   - filename: The file's name (e.g. "My Note.md")
    ///   - directoryRelativePath: Directory path relative to vault root (e.g. "Work" or "")
    func metadata(for filename: String, inDirectory directoryRelativePath: String) -> SidecarItemMetadata? {
        let key = directoryRelativePath.isEmpty ? "" : directoryRelativePath
        if let cached = cache[key] {
            return cached.items[filename]
        }
        // Load on demand
        let sidecar = loadSidecarFile(directoryRelativePath: directoryRelativePath)
        cache[key] = sidecar
        return sidecar.items[filename]
    }

    /// Returns metadata for a note, resolving its directory from relativePath.
    func metadata(forNote note: Note) -> SidecarItemMetadata? {
        let filename = (note.relativePath as NSString).lastPathComponent
        let dirPath: String
        if note.relativePath.contains("/") {
            dirPath = (note.relativePath as NSString).deletingLastPathComponent
        } else {
            dirPath = "\(StoragePaths.inboxDir)/Notes"
        }
        return metadata(for: filename, inDirectory: dirPath)
    }

    /// Loads all sidecar files in the vault. Called on launch and when
    /// FSEvents detects changes to `.cider-meta.json` files.
    func loadAll() {
        cache.removeAll()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: vaultRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var count = 0
        // Also check vault root itself
        let rootSidecar = vaultRoot.appendingPathComponent(Self.sidecarFileName)
        if fm.fileExists(atPath: rootSidecar.path) {
            if let sidecar = parseSidecarFile(at: rootSidecar) {
                cache[""] = sidecar
                count += sidecar.items.count
            }
        }

        while let url = enumerator.nextObject() as? URL {
            guard url.lastPathComponent == Self.sidecarFileName else { continue }
            let dirURL = url.deletingLastPathComponent()
            let relativeDirPath = dirURL.path.replacingOccurrences(of: vaultRoot.path + "/", with: "")
            if relativeDirPath == vaultRoot.path { continue } // skip root, handled above

            if let sidecar = parseSidecarFile(at: url) {
                cache[relativeDirPath] = sidecar
                count += sidecar.items.count
            }
        }
        logger.info("Loaded sidecar metadata: \(count) items across \(self.cache.count) directories")
    }

    /// Reloads a single directory's sidecar file (e.g. after FSEvents notification).
    func reload(directoryRelativePath: String) {
        let sidecar = loadSidecarFile(directoryRelativePath: directoryRelativePath)
        let key = directoryRelativePath.isEmpty ? "" : directoryRelativePath
        if sidecar.items.isEmpty {
            cache.removeValue(forKey: key)
        } else {
            cache[key] = sidecar
        }
    }

    // MARK: - Writing

    /// Sets or updates metadata for a file. Merges with existing sidecar data.
    func setMetadata(
        _ metadata: SidecarItemMetadata,
        for filename: String,
        inDirectory directoryRelativePath: String
    ) {
        let key = directoryRelativePath.isEmpty ? "" : directoryRelativePath
        var sidecar = cache[key] ?? loadSidecarFile(directoryRelativePath: directoryRelativePath)

        if metadata.isEmpty {
            sidecar.items.removeValue(forKey: filename)
        } else {
            sidecar.items[filename] = metadata
        }

        cache[key] = sidecar
        writeSidecarFile(sidecar, directoryRelativePath: directoryRelativePath)
    }

    /// Adds tags to a file's sidecar metadata, merging with existing tags.
    func addTags(_ tags: [String], for filename: String, inDirectory directoryRelativePath: String) {
        var meta = metadata(for: filename, inDirectory: directoryRelativePath) ?? SidecarItemMetadata()
        var existing = Set(meta.tags ?? [])
        for tag in tags { existing.insert(tag) }
        meta.tags = Array(existing).sorted()
        setMetadata(meta, for: filename, inDirectory: directoryRelativePath)
    }

    /// Removes tags from a file's sidecar metadata.
    func removeTags(_ tags: [String], for filename: String, inDirectory directoryRelativePath: String) {
        guard var meta = metadata(for: filename, inDirectory: directoryRelativePath) else { return }
        let toRemove = Set(tags)
        meta.tags = (meta.tags ?? []).filter { !toRemove.contains($0) }
        if (meta.tags ?? []).isEmpty { meta.tags = nil }
        setMetadata(meta, for: filename, inDirectory: directoryRelativePath)
    }

    /// Sets or clears the summary for a file.
    func setSummary(_ summary: String?, for filename: String, inDirectory directoryRelativePath: String) {
        var meta = metadata(for: filename, inDirectory: directoryRelativePath) ?? SidecarItemMetadata()
        meta.summary = summary
        setMetadata(meta, for: filename, inDirectory: directoryRelativePath)
    }

    /// Removes all metadata for a file (e.g. when the file is deleted).
    func removeMetadata(for filename: String, inDirectory directoryRelativePath: String) {
        let key = directoryRelativePath.isEmpty ? "" : directoryRelativePath
        guard var sidecar = cache[key] else { return }
        sidecar.items.removeValue(forKey: filename)
        if sidecar.items.isEmpty {
            cache.removeValue(forKey: key)
            // Delete the sidecar file if empty
            let dirURL = directoryRelativePath.isEmpty
                ? vaultRoot
                : vaultRoot.appendingPathComponent(directoryRelativePath)
            let fileURL = dirURL.appendingPathComponent(Self.sidecarFileName)
            try? FileManager.default.removeItem(at: fileURL)
        } else {
            cache[key] = sidecar
            writeSidecarFile(sidecar, directoryRelativePath: directoryRelativePath)
        }
    }

    // MARK: - Private

    private func loadSidecarFile(directoryRelativePath: String) -> SidecarFile {
        let dirURL = directoryRelativePath.isEmpty
            ? vaultRoot
            : vaultRoot.appendingPathComponent(directoryRelativePath)
        let fileURL = dirURL.appendingPathComponent(Self.sidecarFileName)
        return parseSidecarFile(at: fileURL) ?? SidecarFile()
    }

    private func parseSidecarFile(at url: URL) -> SidecarFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SidecarFile.self, from: data)
    }

    private func writeSidecarFile(_ sidecar: SidecarFile, directoryRelativePath: String) {
        let dirURL = directoryRelativePath.isEmpty
            ? vaultRoot
            : vaultRoot.appendingPathComponent(directoryRelativePath)
        let fileURL = dirURL.appendingPathComponent(Self.sidecarFileName)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sidecar) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
