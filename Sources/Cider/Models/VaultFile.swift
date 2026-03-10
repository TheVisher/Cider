import Foundation
import UniformTypeIdentifiers

/// A file in the vault that isn't a Cider-native type (note, bookmark, etc.).
/// Represents images, PDFs, videos, documents, and any other file dropped into the vault.
struct VaultFile: Identifiable, Hashable {
    let id: UUID
    var filename: String
    var relativePath: String        // relative to vault root, e.g. "Work/photo.jpg"
    var fileType: VaultFileType
    var fileSize: Int64
    var createdAt: Date
    var modifiedAt: Date
    var folderID: UUID?

    var absoluteURL: URL {
        StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(relativePath)
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
