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
    private static let excludedExtensions: Set<String> = ["md", "json", "webloc"]

    /// Directories that contain Cider internal data, not user files.
    private static let excludedDirectoryPrefixes: Set<String> = [
        ".cider-folders", ".history", ".attachments", ".thumbnails",
        ".originals", ".folder-covers", ".trash", ".ai",
        "Bookmarks", "Contacts", "DateCards", "Labels", "SavedViews",
        "Sources", "Stacks", "Tags", "Todos", "Whiteboards", "Clipboard",
        "Notes", "Unsorted", "Inbox"
    ]

    private init() {}

    /// Scans all vault folders for non-Cider files.
    func scan() {
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

            // Skip excluded directories
            let topComponent = relativePath.split(separator: "/").first.map(String.init) ?? relativePath
            if Self.excludedDirectoryPrefixes.contains(topComponent) {
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
            if dirPath.isEmpty || dirPath == "." {
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

        files = scanned.sorted { $0.modifiedAt > $1.modifiedAt }
        logger.info("Scanned vault files: \(scanned.count) items")
    }

    /// Returns all files in a given folder.
    func files(inFolder folderID: UUID?) -> [VaultFile] {
        files.filter { $0.folderID == folderID }
    }

    /// Returns all files of a given type.
    func files(ofType type: VaultFileType) -> [VaultFile] {
        files.filter { $0.fileType == type }
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
