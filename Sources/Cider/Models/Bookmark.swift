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

struct Bookmark: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var urlString: String
    var createdAt: Date
    var updatedAt: Date
    var notes: String
    var tags: [String]
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
