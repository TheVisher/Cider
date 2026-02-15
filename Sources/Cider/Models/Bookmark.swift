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
}

struct Bookmark: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var urlString: String
    var createdAt: Date
    var updatedAt: Date
    var notes: String
    var tags: [String]
    var folderID: UUID?
    var thumbnailRemoteURLString: String?
    var thumbnailRelativePath: String?
    var metadataUpdatedAt: Date?
    var isEnriching: Bool = false

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case urlString
        case createdAt
        case updatedAt
        case notes
        case tags
        case folderID
        case thumbnailRemoteURLString
        case thumbnailRelativePath
        case metadataUpdatedAt
    }

    init(
        id: UUID = UUID(),
        title: String,
        urlString: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        notes: String = "",
        tags: [String] = [],
        folderID: UUID? = nil,
        thumbnailRemoteURLString: String? = nil,
        thumbnailRelativePath: String? = nil,
        metadataUpdatedAt: Date? = nil,
        isEnriching: Bool = false
    ) {
        self.id = id
        self.title = title
        self.urlString = urlString
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.notes = notes
        self.tags = tags
        self.folderID = folderID
        self.thumbnailRemoteURLString = thumbnailRemoteURLString
        self.thumbnailRelativePath = thumbnailRelativePath
        self.metadataUpdatedAt = metadataUpdatedAt
        self.isEnriching = isEnriching
    }

    var url: URL? {
        URL(string: urlString)
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

        let basePath = NSString(string: CiderConfig.load().bookmarksDirectory).expandingTildeInPath
        return URL(fileURLWithPath: basePath, isDirectory: true).appendingPathComponent(thumbnailRelativePath)
    }
}
