import Foundation

// MARK: - Clipboard Item Type

enum ClipboardItemType: String, Codable {
    case url
    case image
    case text
    case richText

    var iconName: String {
        switch self {
        case .url: return "link"
        case .image: return "photo"
        case .text: return "doc.text"
        case .richText: return "doc.richtext"
        }
    }

    var displayName: String {
        switch self {
        case .url: return "URL"
        case .image: return "Image"
        case .text: return "Text"
        case .richText: return "Rich Text"
        }
    }
}

// MARK: - Clipboard Item

struct ClipboardItem: Identifiable, Codable {
    let id: UUID
    let type: ClipboardItemType
    let timestamp: Date
    let sourceAppName: String?
    let sourceAppBundleID: String?

    // Content
    let textContent: String?
    let imageSize: CGSize?    // Original image dimensions

    // Persistence
    var isSaved: Bool
    var savedItemID: UUID?           // ID of the saved bookmark or note (for deletion tracking)
    var imageFileID: UUID?           // UUID for the image file on disk
    var imageFileExtension: String?  // e.g. "png", "jpeg"

    // Transient — not persisted
    var imageData: Data?

    private enum CodingKeys: String, CodingKey {
        case id, type, timestamp, sourceAppName, sourceAppBundleID
        case textContent, imageSize
        case isSaved, savedItemID, imageFileID, imageFileExtension
    }

    init(
        type: ClipboardItemType,
        textContent: String? = nil,
        imageData: Data? = nil,
        imageSize: CGSize? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) {
        self.id = UUID()
        self.type = type
        self.timestamp = Date()
        self.textContent = textContent
        self.imageData = imageData
        self.imageSize = imageSize
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isSaved = false
        self.imageFileID = nil
        self.imageFileExtension = nil
    }

    var displayPreview: String {
        switch type {
        case .url:
            return textContent ?? "URL"
        case .image:
            if let size = imageSize {
                return "\(Int(size.width)) x \(Int(size.height))"
            }
            return "Image"
        case .text, .richText:
            return textContent ?? ""
        }
    }

    var typeIcon: String {
        type.iconName
    }
}
