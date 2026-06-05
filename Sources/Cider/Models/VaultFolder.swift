import Foundation

/// A folder backed by a real directory on disk in the Cider Vault.
/// Unlike the legacy `Folder` model (pure metadata), a `VaultFolder` maps 1:1
/// to a filesystem directory. Creating/renaming/deleting a `VaultFolder` creates/renames/deletes
/// the corresponding directory.
struct VaultFolder: Identifiable, Hashable, Codable {
    let id: UUID
    /// Path relative to the vault root, e.g. "Work" or "Work/Projects".
    var relativePath: String
    var createdAt: Date
    var updatedAt: Date
    var icon: String?
    /// Cover image path relative to the vault root (stored in `.cider-folders/covers/`).
    var coverImagePath: String?
    var coverImageOffsetY: Double?

    // MARK: - Derived Properties

    /// The folder's display name (last path component).
    var name: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    /// The parent folder's relative path, or `nil` if this is a root-level folder.
    var parentRelativePath: String? {
        let parent = (relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty || parent == "." ? nil : parent
    }

    /// Whether the icon is an emoji (vs SF Symbol name).
    var iconIsEmoji: Bool {
        guard let icon, let scalar = icon.unicodeScalars.first else { return false }
        return scalar.value > 127
    }

    var looksLikeArtifactPath: Bool {
        Self.looksLikeVaultArtifactPath(relativePath)
    }

    static func looksLikeVaultArtifactPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard let leaf = trimmed.split(separator: "/").last else { return false }
        guard let dot = leaf.lastIndex(of: ".") else { return false }
        let ext = leaf[leaf.index(after: dot)...].lowercased()
        return knownArtifactExtensions.contains(String(ext))
    }

    private static let knownArtifactExtensions: Set<String> = [
        "webloc", "md", "markdown", "ics", "vcf",
        "png", "jpg", "jpeg", "gif", "heic", "webp",
        "pdf", "txt", "rtf", "doc", "docx",
    ]

    init(
        id: UUID = UUID(),
        relativePath: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        icon: String? = nil,
        coverImagePath: String? = nil,
        coverImageOffsetY: Double? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.icon = icon
        self.coverImagePath = coverImagePath
        self.coverImageOffsetY = coverImageOffsetY
    }
}

/// Payload for trashing a vault folder (stored in trash manifest).
struct VaultFolderTrashPayload: Codable {
    let folder: VaultFolder
}
