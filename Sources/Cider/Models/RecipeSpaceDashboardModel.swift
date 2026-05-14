import Foundation

struct RecipeSpaceSection: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let items: [RecipeCollectionItem]
}

struct RecipeSpaceSourceSummary: Identifiable, Hashable {
    let platform: RecipeSourcePlatform
    let count: Int

    var id: RecipeSourcePlatform { platform }
}

struct RecipeSpaceDashboardModel: Equatable {
    let items: [RecipeCollectionItem]

    var totalRecipeItems: Int { items.count }

    var needsReviewItems: [RecipeCollectionItem] {
        items.filter { $0.extractionStatus == .candidate || $0.extractionStatus == .needsReview }
    }

    var likedItems: [RecipeCollectionItem] {
        items.filter { $0.rating == .liked || $0.familyRatings.values.contains(.liked) }
    }

    var dislikedItems: [RecipeCollectionItem] {
        items.filter { $0.rating == .disliked || $0.familyRatings.values.contains(.disliked) }
    }

    var sourceSummaries: [RecipeSpaceSourceSummary] {
        let counts = Dictionary(items.map { ($0.sourcePlatform, 1) }, uniquingKeysWith: +)
        let preferred: [RecipeSourcePlatform] = [.tiktok, .instagram, .youtube, .recipeSite, .web]
        return preferred.compactMap { platform in
            guard let count = counts[platform], count > 0 else { return nil }
            return RecipeSpaceSourceSummary(platform: platform, count: count)
        }
    }

    var sections: [RecipeSpaceSection] {
        [
            RecipeSpaceSection(
                id: "collection",
                title: "Recipe Collection",
                subtitle: "Recipe-shaped saves with original source backlinks.",
                systemImage: "rectangle.grid.2x2",
                items: items
            ),
            RecipeSpaceSection(
                id: "needs-review",
                title: "Needs Review",
                subtitle: "Social or bookmark candidates that need extraction cleanup.",
                systemImage: "wand.and.stars",
                items: needsReviewItems
            ),
            RecipeSpaceSection(
                id: "liked",
                title: "Liked",
                subtitle: "Recipes with positive taste signals.",
                systemImage: "hand.thumbsup",
                items: likedItems
            ),
            RecipeSpaceSection(
                id: "disliked",
                title: "Disliked",
                subtitle: "Recipes to avoid or tweak next time.",
                systemImage: "hand.thumbsdown",
                items: dislikedItems
            ),
        ]
    }

    static let empty = RecipeSpaceDashboardModel(items: [])

    static func make(bookmarks: [Bookmark], existingItems: [RecipeCollectionItem] = []) -> RecipeSpaceDashboardModel {
        var bySource = Dictionary(uniqueKeysWithValues: existingItems.compactMap { item in
            item.sourceURL.isEmpty ? nil : (item.sourceURL, item)
        })

        for bookmark in bookmarks {
            let fields = RecipeSignalFields(bookmark)
            let extraction = shouldAttemptRecipeExtraction(bookmark, fields: fields)
                ? RecipeExtractor.extract(from: bookmark)
                : nil
            guard isRecipeCandidate(bookmark, fields: fields, extraction: extraction) else { continue }
            if bySource[bookmark.urlString] == nil {
                let chips = metadataChips(for: bookmark, fields: fields, extraction: extraction)
                let item = RecipeCollectionItem(
                    id: bookmark.id.uuidString.lowercased(),
                    title: extraction?.title ?? cleanedTitle(bookmark.title),
                    sourceBookmarkID: bookmark.id,
                    sourceURL: bookmark.urlString,
                    sourceRelativePath: bookmark.relativePath,
                    sourcePlatform: platform(for: bookmark),
                    extractionStatus: extraction?.status ?? extractionStatus(for: bookmark),
                    imageRemoteURL: bookmark.thumbnailRemoteURLString,
                    imageRelativePath: bookmark.thumbnailRelativePath,
                    ingredients: extraction?.ingredients ?? ingredientHints(from: fields),
                    instructions: extraction?.instructions ?? [],
                    servings: extraction?.servings,
                    totalTime: extraction?.totalTime,
                    metadataChips: chips
                )
                bySource[bookmark.urlString] = item
            }
        }

        return RecipeSpaceDashboardModel(
            items: Array(bySource.values).sorted { lhs, rhs in
                if lhs.extractionStatus == .parsed && rhs.extractionStatus != .parsed { return true }
                if lhs.extractionStatus != .parsed && rhs.extractionStatus == .parsed { return false }
                return lhs.updatedAt > rhs.updatedAt
            }
        )
    }

    private static func shouldAttemptRecipeExtraction(_ bookmark: Bookmark, fields: RecipeSignalFields) -> Bool {
        if bookmark.relativePath?.localizedCaseInsensitiveContains("Food/Recipes") == true { return true }
        if fields.raw.contains("Cider native recipe extraction source".lowercased()) { return true }
        if containsAny(fields.raw, recipeHosts) { return true }
        if platform(for: bookmark) != .web && containsAnyWord(fields, recipeWords + foodWords) { return true }
        return containsAnyWord(fields, recipeWords) && containsAnyWord(fields, foodWords)
    }

    private static func isRecipeCandidate(_ bookmark: Bookmark, fields: RecipeSignalFields, extraction: ExtractedRecipe? = nil) -> Bool {
        if extraction != nil { return true }
        if bookmark.relativePath?.localizedCaseInsensitiveContains("Food/Recipes") == true { return true }
        if containsAny(fields.raw, recipeHosts) { return true }
        if platform(for: bookmark) != .web && containsAnyWord(fields, recipeWords) { return true }
        return containsAnyWord(fields, recipeWords) && containsAnyWord(fields, foodWords)
    }

    private static func platform(for bookmark: Bookmark) -> RecipeSourcePlatform {
        let host = bookmark.url?.host?.lowercased() ?? ""
        if host.contains("tiktok.com") { return .tiktok }
        if host.contains("instagram.com") { return .instagram }
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtube }
        if recipeHosts.contains(where: { host.contains($0) }) { return .recipeSite }
        return .web
    }

    private static func extractionStatus(for bookmark: Bookmark) -> RecipeExtractionStatus {
        switch platform(for: bookmark) {
        case .recipeSite:
            return .needsReview
        case .tiktok, .instagram, .youtube:
            return .candidate
        case .web:
            return bookmark.notes.localizedCaseInsensitiveContains("ingredients") ? .needsReview : .candidate
        }
    }

    private static func cleanedTitle(_ title: String) -> String {
        title
            .replacingOccurrences(of: "TikTok · ", with: "")
            .replacingOccurrences(of: "TikTok - ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func metadataChips(for bookmark: Bookmark, fields: RecipeSignalFields, extraction: ExtractedRecipe? = nil) -> [String] {
        var chips = [platform(for: bookmark).displayName]
        if extraction != nil {
            chips.append("Recipe pulled")
        }
        if let totalTime = extraction?.totalTime {
            chips.append(totalTime)
        }
        if let servings = extraction?.servings {
            chips.append(servings)
        }
        for word in ["dinner", "dessert", "breakfast", "lunch", "snack", "chicken", "pasta", "salmon", "cookies"] where fields.words.contains(word) {
            chips.append(word.capitalized)
        }
        return Array(chips.prefix(5))
    }

    private static func ingredientHints(from fields: RecipeSignalFields) -> [String] {
        return ["chicken", "pasta", "salmon", "rice", "miso", "butter", "cookies", "chocolate", "taco", "potato"]
            .filter { fields.words.contains($0) }
            .prefix(5)
            .map { $0.capitalized }
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func containsAnyWord(_ fields: RecipeSignalFields, _ words: [String]) -> Bool {
        words.contains { fields.words.contains($0) }
    }

    private static let recipeHosts = [
        "allrecipes.com", "seriouseats.com", "smittenkitchen.com", "bonappetit.com", "foodnetwork.com",
        "nytcooking.com", "kingarthurbaking.com", "delish.com", "epicurious.com", "budgetbytes.com",
        "recipetineats.com", "pinchofyum.com", "tasty.co"
    ]

    private static let recipeWords = ["recipe", "recipes", "ingredients", "cook", "cooking", "bake", "baking", "meal"]
    private static let foodWords = ["food", "dinner", "lunch", "breakfast", "dessert", "chicken", "pasta", "salmon", "rice", "cookies", "taco", "fries"]
}

private struct RecipeSignalFields {
    let raw: String
    let words: Set<String>

    init(_ bookmark: Bookmark) {
        raw = [
            bookmark.title,
            bookmark.urlString,
            bookmark.notes,
            bookmark.aiSummary ?? "",
            bookmark.ocrText ?? "",
            bookmark.tags.joined(separator: " "),
            bookmark.relativePath ?? "",
        ]
        .joined(separator: " ")
        .lowercased()
        words = Set(raw.split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }
}
