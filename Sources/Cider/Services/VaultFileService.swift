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

    /// File extensions that are Cider-native and handled by other services.
    /// These are excluded from vault file scanning.
    private static let excludedExtensions: Set<String> = ["md", "json", "webloc", "ics", "vcf"]

    /// Directories that contain Cider internal data, not user files.
    /// `.cider/` is hidden and auto-skipped by .skipsHiddenFiles.
    /// `Unsorted` is a legacy directory prefix.
    private static let excludedDirectoryPrefixes: Set<String> = [
        "Unsorted"
    ]

    /// Inbox subdirectory names that hold Cider-native files (skip scanning those).
    private static let inboxNativeSubdirs: Set<String> = [
        "Bookmarks", "Notes", "Contacts", "Todos", "Date Cards"
    ]

    // MARK: - File Watching

    private var watcher: FSEventsWatcher?
    private var isScanning = false

    private init() {}

    // MARK: - Public API

    /// Scans all vault folders (including Inbox) for non-Cider files.
    func scan() {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let fm = FileManager.default
        let root = vaultRoot

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey,
                .creationDateKey, .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            files = []
            return
        }

        var scanned: [VaultFile] = []

        while let url = enumerator.nextObject() as? URL {
            let relativePath = url.path.replacingOccurrences(of: root.path + "/", with: "")
            let components = relativePath.split(separator: "/").map(String.init)

            // Skip excluded top-level directories
            if let topComponent = components.first,
               Self.excludedDirectoryPrefixes.contains(topComponent) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Skip Inbox subdirectories that hold native Cider files
            // (e.g., Inbox/Bookmarks/, Inbox/Notes/) but allow non-native files in Inbox root
            if components.count >= 2, components[0] == "Inbox",
               Self.inboxNativeSubdirs.contains(components[1]) {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            // Skip directories
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                continue
            }

            // Skip Cider-native file types
            let ext = url.pathExtension.lowercased()
            if Self.excludedExtensions.contains(ext) || ext.isEmpty {
                continue
            }

            let fileType = VaultFileType.from(extension: ext)
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .creationDateKey, .contentModificationDateKey
            ])

            let fileSize = Int64(values?.fileSize ?? 0)
            let createdAt = values?.creationDate ?? Date()
            let modifiedAt = values?.contentModificationDate ?? Date()

            // Derive a stable UUID from the path
            let id = stableID(for: relativePath)

            // Determine folder ID from the directory
            let dirPath = (relativePath as NSString).deletingLastPathComponent
            let folderID: UUID?
            if dirPath.isEmpty || dirPath == "." || dirPath == "Inbox" {
                folderID = nil
            } else {
                folderID = VaultFolderService.shared.folders.first(where: { $0.relativePath == dirPath })?.id
            }

            scanned.append(VaultFile(
                id: id,
                filename: url.lastPathComponent,
                relativePath: relativePath,
                fileType: fileType,
                fileSize: fileSize,
                createdAt: createdAt,
                modifiedAt: modifiedAt,
                folderID: folderID
            ))
        }

        // Apply persisted metadata (title, notes, labels, OCR, colors)
        VaultFileStorage.shared.applyMetadata(to: &scanned)

        files = scanned.sorted { $0.modifiedAt > $1.modifiedAt }
        logger.info("Scanned vault files: \(scanned.count) items")

        // Schedule enrichment for new un-enriched image files
        VaultFileEnrichment.shared.scheduleAll()
    }

    /// Starts watching the vault root for file changes and auto-rescanning.
    func startWatching() {
        stopWatching()
        watcher = FSEventsWatcher(path: vaultRoot.path, latency: 1.0) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isScanning else { return }
                self.scan()
            }
        }
        watcher?.start()
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    // MARK: - Queries

    /// Returns all files in a given folder.
    func files(inFolder folderID: UUID?) -> [VaultFile] {
        files.filter { $0.folderID == folderID }
    }

    /// Returns all files of a given type.
    func files(ofType type: VaultFileType) -> [VaultFile] {
        files.filter { $0.fileType == type }
    }

    /// Returns a file by ID.
    func file(for id: UUID) -> VaultFile? {
        files.first { $0.id == id }
    }

    // MARK: - Mutation

    /// Moves a vault file to a different folder by physically moving the file.
    func assignFile(_ fileID: UUID, toFolder folderID: UUID?) {
        guard let index = files.firstIndex(where: { $0.id == fileID }) else { return }
        let file = files[index]
        let fm = FileManager.default

        // Determine target directory
        let targetDir: URL
        if let folderID, let folder = VaultFolderService.shared.folder(for: folderID) {
            targetDir = vaultRoot.appendingPathComponent(folder.relativePath)
        } else {
            // Unfiled — move to Inbox root
            targetDir = vaultRoot.appendingPathComponent("Inbox")
        }
        try? fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

        let destURL = targetDir.appendingPathComponent(file.filename)
        guard destURL != file.absoluteURL else { return }

        do {
            try fm.moveItem(at: file.absoluteURL, to: destURL)
            // Rescan to pick up new path and folder assignment
            scan()
        } catch {
            logger.error("Failed to move vault file: \(error.localizedDescription)")
        }
    }

    /// Deletes a vault file from disk and rescans.
    func deleteFile(_ fileID: UUID) -> VaultFile? {
        guard let file = files.first(where: { $0.id == fileID }) else { return nil }
        try? FileManager.default.removeItem(at: file.absoluteURL)
        VaultFileStorage.shared.removeMetadata(for: fileID)
        scan()
        return file
    }

    // MARK: - Private

    /// Derives a stable UUID from a vault-relative path using SHA-256.
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
