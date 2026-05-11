import Foundation

enum MediaItemType: String, Codable, CaseIterable, Hashable {
    case movie
    case show
    case game
    case book
    case reference
    case unknown
}

enum MediaItemStatus: String, Codable, CaseIterable, Hashable {
    case unknown
    case want
    case consuming
    case completed
    case paused
    case abandoned
    case favorite
}

struct MediaItem: Identifiable, Codable, Hashable {
    var id: String
    var type: MediaItemType
    var title: String
    var canonicalTitle: String
    var year: Int?
    var releaseDate: String?
    var externalIDs: [String: String]
    var posterImagePath: String?
    var coverImageURL: String?
    var genres: [String]
    var categories: [String]
    var status: MediaItemStatus
    var sourceBookmarkIDs: [UUID]
    var sourceRelativePaths: [String]
    var sourceURLs: [String]
    var confidence: Double
    var identificationReason: String?
    var rawProviderPayloadPath: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String,
        type: MediaItemType,
        title: String,
        canonicalTitle: String? = nil,
        year: Int? = nil,
        releaseDate: String? = nil,
        externalIDs: [String: String] = [:],
        posterImagePath: String? = nil,
        coverImageURL: String? = nil,
        genres: [String] = [],
        categories: [String] = [],
        status: MediaItemStatus = .unknown,
        sourceBookmarkIDs: [UUID] = [],
        sourceRelativePaths: [String] = [],
        sourceURLs: [String] = [],
        confidence: Double = 0,
        identificationReason: String? = nil,
        rawProviderPayloadPath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.canonicalTitle = canonicalTitle ?? Self.canonicalTitle(for: title)
        self.year = year
        self.releaseDate = releaseDate
        self.externalIDs = externalIDs
        self.posterImagePath = posterImagePath
        self.coverImageURL = coverImageURL
        self.genres = genres
        self.categories = categories
        self.status = status
        self.sourceBookmarkIDs = sourceBookmarkIDs
        self.sourceRelativePaths = sourceRelativePaths
        self.sourceURLs = sourceURLs
        self.confidence = confidence
        self.identificationReason = identificationReason
        self.rawProviderPayloadPath = rawProviderPayloadPath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static func canonicalTitle(for title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
    }

    func mergingSources(from other: MediaItem, now: Date = Date()) -> MediaItem {
        var merged = self
        merged.sourceBookmarkIDs = Self.merge(sourceBookmarkIDs, other.sourceBookmarkIDs)
        merged.sourceRelativePaths = Self.merge(sourceRelativePaths, other.sourceRelativePaths)
        merged.sourceURLs = Self.merge(sourceURLs, other.sourceURLs)
        merged.externalIDs = externalIDs.merging(other.externalIDs) { current, _ in current }
        merged.genres = Self.merge(genres, other.genres)
        merged.categories = Self.merge(categories, other.categories)
        merged.confidence = max(confidence, other.confidence)
        merged.updatedAt = now
        if merged.posterImagePath == nil { merged.posterImagePath = other.posterImagePath }
        if merged.coverImageURL == nil { merged.coverImageURL = other.coverImageURL }
        if merged.rawProviderPayloadPath == nil { merged.rawProviderPayloadPath = other.rawProviderPayloadPath }
        if merged.identificationReason == nil { merged.identificationReason = other.identificationReason }
        return merged
    }

    private static func merge<T: Hashable>(_ lhs: [T], _ rhs: [T]) -> [T] {
        var seen = Set<T>()
        return (lhs + rhs).filter { seen.insert($0).inserted }
    }
}
