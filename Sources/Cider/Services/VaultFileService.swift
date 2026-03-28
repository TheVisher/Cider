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

        let fm = FileManager.default
        let root = vaultRoot
        var scanned: [VaultFile] = []

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

                if let file = processFile(url: url, relativePath: relativePath) {
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
                    if let file = processFile(url: url, relativePath: relativePath) {
                        scanned.append(file)
                    }
                }
            }
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
    /// Migrates metadata to the new path-derived ID so it isn't orphaned.
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

        // Capture old ID before move
        let oldID = file.id

        do {
            try fm.moveItem(at: file.absoluteURL, to: destURL)

            // Migrate metadata to new path-derived ID (path changed → ID changed)
            let newRelativePath = destURL.path.replacingOccurrences(
                of: vaultRoot.path.hasSuffix("/") ? vaultRoot.path : vaultRoot.path + "/",
                with: ""
            )
            let newID = stableID(for: newRelativePath)
            if newID != oldID {
                VaultFileStorage.shared.migrateMetadata(from: oldID, to: newID)
            }

            scan()
        } catch {
            logger.error("Failed to move vault file: \(error.localizedDescription)")
        }
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
    private func processFile(url: URL, relativePath: String) -> VaultFile? {
        // Skip directories
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return nil
        }

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
        let createdAt = values?.creationDate ?? Date()
        let modifiedAt = values?.contentModificationDate ?? Date()
        let id = stableID(for: relativePath)

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
