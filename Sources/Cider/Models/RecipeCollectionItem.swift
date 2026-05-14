import Foundation

enum RecipeSourcePlatform: String, Codable, CaseIterable, Hashable {
    case tiktok
    case instagram
    case youtube
    case recipeSite
    case web

    var displayName: String {
        switch self {
        case .tiktok: "TikTok"
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        case .recipeSite: "Recipe site"
        case .web: "Web"
        }
    }
}

enum RecipeExtractionStatus: String, Codable, CaseIterable, Hashable {
    case candidate
    case parsed
    case needsReview
    case manual

    var displayName: String {
        switch self {
        case .candidate: "Candidate"
        case .parsed: "Parsed"
        case .needsReview: "Needs review"
        case .manual: "Manual"
        }
    }
}

enum RecipeRating: String, Codable, CaseIterable, Hashable {
    case liked
    case disliked

    var displayName: String {
        switch self {
        case .liked: "Liked"
        case .disliked: "Disliked"
        }
    }
}

struct RecipeCollectionItem: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var sourceBookmarkID: UUID?
    var sourceURL: String
    var sourceRelativePath: String?
    var sourcePlatform: RecipeSourcePlatform
    var extractionStatus: RecipeExtractionStatus
    var imageRemoteURL: String?
    var imageRelativePath: String?
    var ingredients: [String]
    var instructions: [String]
    var servings: String?
    var totalTime: String?
    var metadataChips: [String]
    var rating: RecipeRating?
    var familyRatings: [String: RecipeRating]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString.lowercased(),
        title: String,
        sourceBookmarkID: UUID? = nil,
        sourceURL: String,
        sourceRelativePath: String? = nil,
        sourcePlatform: RecipeSourcePlatform = .web,
        extractionStatus: RecipeExtractionStatus = .candidate,
        imageRemoteURL: String? = nil,
        imageRelativePath: String? = nil,
        ingredients: [String] = [],
        instructions: [String] = [],
        servings: String? = nil,
        totalTime: String? = nil,
        metadataChips: [String] = [],
        rating: RecipeRating? = nil,
        familyRatings: [String: RecipeRating] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.sourceBookmarkID = sourceBookmarkID
        self.sourceURL = sourceURL
        self.sourceRelativePath = sourceRelativePath
        self.sourcePlatform = sourcePlatform
        self.extractionStatus = extractionStatus
        self.imageRemoteURL = imageRemoteURL
        self.imageRelativePath = imageRelativePath
        self.ingredients = ingredients
        self.instructions = instructions
        self.servings = servings
        self.totalTime = totalTime
        self.metadataChips = metadataChips
        self.rating = rating
        self.familyRatings = familyRatings
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var sourceBacklinkLabel: String {
        sourcePlatform.displayName
    }

    var ratingSummary: String {
        var parts: [String] = []
        if let rating {
            parts.append(rating.displayName)
        }
        let familyParts = familyRatings.keys.sorted().compactMap { name -> String? in
            guard let rating = familyRatings[name] else { return nil }
            return "\(name) \(rating.rawValue)"
        }
        parts.append(contentsOf: familyParts)
        return parts.joined(separator: " · ")
    }

    func settingRating(_ rating: RecipeRating, for familyMember: String?) -> RecipeCollectionItem {
        var copy = self
        if let familyMember = familyMember?.trimmingCharacters(in: .whitespacesAndNewlines), !familyMember.isEmpty {
            copy.familyRatings[familyMember] = rating
        } else {
            copy.rating = rating
        }
        copy.updatedAt = Date()
        return copy
    }
}
