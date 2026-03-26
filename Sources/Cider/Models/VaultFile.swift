import Foundation

/// A file in the vault that isn't a Cider-native type (note, bookmark, etc.).
/// Represents images, PDFs, videos, documents, and any other file dropped into the vault.
struct VaultFile: Identifiable, Hashable, Codable {
    let id: UUID
    var filename: String
    var relativePath: String        // relative to vault root, e.g. "Work/photo.jpg"
    var fileType: VaultFileType
    var fileSize: Int64
    var createdAt: Date
    var modifiedAt: Date
    var folderID: UUID?

    // MARK: - Metadata (persisted via VaultFileStorage)

    var title: String?              // User-set or AI-suggested title (nil = use filename)
    var notes: String = ""          // User or AI notes
    var labelIDs: [UUID] = []       // Tag labels
    var ocrText: String?            // OCR-extracted text for search
    var dominantColors: [String]?   // Hex color strings

    var absoluteURL: URL {
        StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath)
    }

    /// Display title — uses metadata title if set, otherwise the filename without extension.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return (filename as NSString).deletingPathExtension
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, filename, relativePath, fileType, fileSize
        case createdAt, modifiedAt, folderID
        case title, notes, labelIDs, ocrText, dominantColors
    }

    init(
        id: UUID,
        filename: String,
        relativePath: String,
        fileType: VaultFileType,
        fileSize: Int64,
        createdAt: Date,
        modifiedAt: Date,
        folderID: UUID?,
        title: String? = nil,
        notes: String = "",
        labelIDs: [UUID] = [],
        ocrText: String? = nil,
        dominantColors: [String]? = nil
    ) {
        self.id = id
        self.filename = filename
        self.relativePath = relativePath
        self.fileType = fileType
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.folderID = folderID
        self.title = title
        self.notes = notes
        self.labelIDs = labelIDs
        self.ocrText = ocrText
        self.dominantColors = dominantColors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        relativePath = try c.decode(String.self, forKey: .relativePath)
        fileType = try c.decode(VaultFileType.self, forKey: .fileType)
        fileSize = try c.decode(Int64.self, forKey: .fileSize)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        labelIDs = try c.decodeIfPresent([UUID].self, forKey: .labelIDs) ?? []
        ocrText = try c.decodeIfPresent(String.self, forKey: .ocrText)
        dominantColors = try c.decodeIfPresent([String].self, forKey: .dominantColors)
    }
}

/// Categorizes vault files for card rendering and viewer selection.
enum VaultFileType: String, Codable, Hashable {
    case image
    case pdf
    case video
    case audio
    case document      // Word, Pages, spreadsheets, etc.
    case archive       // zip, tar, etc.
    case unknown

    /// Infers file type from a file extension.
    static func from(extension ext: String) -> VaultFileType {
        let lower = ext.lowercased()

        // Images
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tiff", "tif", "bmp", "svg", "ico", "raw", "cr2", "nef", "arw"].contains(lower) {
            return .image
        }

        // PDF
        if lower == "pdf" { return .pdf }

        // Video
        if ["mp4", "mov", "avi", "mkv", "m4v", "webm", "wmv", "flv"].contains(lower) {
            return .video
        }

        // Audio
        if ["mp3", "m4a", "wav", "aac", "flac", "ogg", "wma", "aiff", "alac"].contains(lower) {
            return .audio
        }

        // Documents
        if ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "rtf", "txt", "csv", "tsv"].contains(lower) {
            return .document
        }

        // Archives
        if ["zip", "tar", "gz", "7z", "rar", "dmg", "iso"].contains(lower) {
            return .archive
        }

        return .unknown
    }

    var displayName: String {
        switch self {
        case .image: return "Image"
        case .pdf: return "PDF"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .archive: return "Archive"
        case .unknown: return "File"
        }
    }

    var systemImageName: String {
        switch self {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .unknown: return "doc"
        }
    }
}
