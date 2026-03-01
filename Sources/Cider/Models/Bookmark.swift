import CoreGraphics
import Foundation

enum BookmarkDisplayMode: String, Codable, CaseIterable {
    case list
    case grid
    case masonry

    var displayName: String {
        switch self {
        case .list:
            "List"
        case .grid:
            "Grid"
        case .masonry:
            "Masonry"
        }
    }

    var icon: String {
        switch self {
        case .list:
            "list.bullet"
        case .grid:
            "square.grid.2x2"
        case .masonry:
            "rectangle.grid.1x2"
        }
    }
}

enum BookmarkCardSize: String, Codable, CaseIterable {
    case compact
    case comfortable
    case large
    case extraLarge

    var displayName: String {
        switch self {
        case .compact:
            "Compact"
        case .comfortable:
            "Comfortable"
        case .large:
            "Large"
        case .extraLarge:
            "Extra Large"
        }
    }

    var shortLabel: String {
        switch self {
        case .compact:
            "S"
        case .comfortable:
            "M"
        case .large:
            "L"
        case .extraLarge:
            "XL"
        }
    }

    var cardMinWidth: CGFloat {
        switch self {
        case .compact:
            196
        case .comfortable:
            220
        case .large:
            252
        case .extraLarge:
            286
        }
    }

    var gridThumbnailHeight: CGFloat {
        switch self {
        case .compact:
            124
        case .comfortable:
            140
        case .large:
            164
        case .extraLarge:
            188
        }
    }

    var masonryThumbnailHeightMin: CGFloat {
        switch self {
        case .compact:
            104
        case .comfortable:
            120
        case .large:
            144
        case .extraLarge:
            168
        }
    }

    var masonryThumbnailHeightMax: CGFloat {
        switch self {
        case .compact:
            320
        case .comfortable:
            360
        case .large:
            400
        case .extraLarge:
            440
        }
    }

    var masonryThumbnailHeightFallback: CGFloat {
        switch self {
        case .compact:
            154
        case .comfortable:
            180
        case .large:
            208
        case .extraLarge:
            236
        }
    }

    var listThumbnailWidth: CGFloat {
        switch self {
        case .compact:
            60
        case .comfortable:
            72
        case .large:
            84
        case .extraLarge:
            96
        }
    }

    var listThumbnailHeight: CGFloat {
        switch self {
        case .compact:
            44
        case .comfortable:
            52
        case .large:
            62
        case .extraLarge:
            72
        }
    }

    var sliderValue: Double {
        switch self {
        case .compact: 0
        case .comfortable: 1
        case .large: 2
        case .extraLarge: 3
        }
    }

    init(sliderValue: Double) {
        switch Int(sliderValue.rounded()) {
        case 0: self = .compact
        case 1: self = .comfortable
        case 2: self = .large
        default: self = .extraLarge
        }
    }
}

struct CardSizing {
    let scale: Double

    var cardMinWidth: CGFloat { interpolate(196, 240, 340, 520) }
    var gridThumbnailHeight: CGFloat { interpolate(124, 160, 220, 360) }
    var masonryThumbnailHeightMin: CGFloat { interpolate(104, 140, 200, 300) }
    var masonryThumbnailHeightMax: CGFloat { interpolate(320, 400, 540, 720) }
    var masonryThumbnailHeightFallback: CGFloat { interpolate(154, 200, 300, 420) }
    var listThumbnailWidth: CGFloat { interpolate(60, 80, 120, 180) }
    var listThumbnailHeight: CGFloat { interpolate(44, 60, 88, 130) }

    var isExtraLarge: Bool { scale > 2.5 }

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        let stops = [a, b, c, d]
        let clamped = min(max(scale, 0), 3)
        let lower = Int(clamped)
        let upper = min(lower + 1, 3)
        let frac = CGFloat(clamped - Double(lower))
        return stops[lower] + frac * (stops[upper] - stops[lower])
    }
}

struct Bookmark: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var urlString: String
    var createdAt: Date
    var updatedAt: Date
    var notes: String
    var tags: [String]
    var labelIDs: [UUID]
    var dismissedLabelIDs: [UUID]
    var folderID: UUID?
    var thumbnailRemoteURLString: String?
    var thumbnailRelativePath: String?
    var originalImageRelativePath: String?
    var metadataUpdatedAt: Date?
    var isEnriching: Bool = false

    // AI-generated fields (all optional — backwards compatible)
    var aiSummary: String?           // Foundation Models 2-sentence summary
    var ocrText: String?             // Vision OCR text from thumbnail (for search)
    var dominantColors: [String]?    // Hex color strings extracted from thumbnail

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case urlString
        case createdAt
        case updatedAt
        case notes
        case tags
        case labelIDs
        case dismissedLabelIDs
        case folderID
        case thumbnailRemoteURLString
        case thumbnailRelativePath
        case originalImageRelativePath
        case metadataUpdatedAt
        case aiSummary
        case ocrText
        case dominantColors
    }

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String = "",
        tags: [String] = [],
        labelIDs: [UUID] = [],
        dismissedLabelIDs: [UUID] = [],
        folderID: UUID? = nil,
        thumbnailRemoteURLString: String? = nil,
        thumbnailRelativePath: String? = nil,
        originalImageRelativePath: String? = nil,
        metadataUpdatedAt: Date? = nil,
        isEnriching: Bool = false,
        aiSummary: String? = nil,
        ocrText: String? = nil,
        dominantColors: [String]? = nil
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.tags = tags
        self.labelIDs = labelIDs
        self.dismissedLabelIDs = dismissedLabelIDs
        self.folderID = folderID
        self.thumbnailRemoteURLString = thumbnailRemoteURLString
        self.thumbnailRelativePath = thumbnailRelativePath
        self.originalImageRelativePath = originalImageRelativePath
        self.metadataUpdatedAt = metadataUpdatedAt
        self.isEnriching = isEnriching
        self.aiSummary = aiSummary
        self.ocrText = ocrText
        self.dominantColors = dominantColors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        urlString = try container.decode(String.self, forKey: .urlString)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        notes = try container.decode(String.self, forKey: .notes)
        tags = try container.decode([String].self, forKey: .tags)
        labelIDs = try container.decodeIfPresent([UUID].self, forKey: .labelIDs) ?? []
        dismissedLabelIDs = try container.decodeIfPresent([UUID].self, forKey: .dismissedLabelIDs) ?? []
        folderID = try container.decodeIfPresent(UUID.self, forKey: .folderID)
        thumbnailRemoteURLString = try container.decodeIfPresent(String.self, forKey: .thumbnailRemoteURLString)
        thumbnailRelativePath = try container.decodeIfPresent(String.self, forKey: .thumbnailRelativePath)
        originalImageRelativePath = try container.decodeIfPresent(String.self, forKey: .originalImageRelativePath)
        metadataUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .metadataUpdatedAt)
        aiSummary = try container.decodeIfPresent(String.self, forKey: .aiSummary)
        ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
        dominantColors = try container.decodeIfPresent([String].self, forKey: .dominantColors)
    }

    var url: URL? {
        URL(string: urlString)
    }

    /// Whether this bookmark has a meaningful URL (not just an image-only entry).
    var hasURL: Bool {
        guard let url, let host = url.host, !host.isEmpty else { return false }
        return url.scheme == "http" || url.scheme == "https" || !host.isEmpty
    }

    var hostDisplay: String {
        guard let host = url?.host, !host.isEmpty else {
            return "Unknown Source"
        }

        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }

        return host
    }

    var thumbnailFileURL: URL? {
        guard let thumbnailRelativePath, !thumbnailRelativePath.isEmpty else {
            return nil
        }
        return StoragePaths.cachedDirectoryURL(for: .bookmarks).appendingPathComponent(thumbnailRelativePath)
    }

    var originalImageFileURL: URL? {
        guard let originalImageRelativePath, !originalImageRelativePath.isEmpty else {
            return nil
        }
        return StoragePaths.cachedDirectoryURL(for: .bookmarks).appendingPathComponent(originalImageRelativePath)
    }
}
