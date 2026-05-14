import Foundation
import Testing
@testable import Cider

@Suite("Recipe Space Dashboard Model Tests")
struct RecipeSpaceDashboardModelTests {
    @Test("recipe preset describes a collection space rather than cookbook")
    func recipePresetDescribesCollectionSpace() {
        let preset = CiderSpacePreset.defaults(for: .recipes)

        #expect(preset.title == "Recipes")
        #expect(preset.systemImage == "fork.knife")
        #expect(preset.purpose.localizedCaseInsensitiveContains("collection"))
        #expect(!preset.purpose.localizedCaseInsensitiveContains("cookbook"))
        #expect(preset.routingHints.contains { $0.localizedCaseInsensitiveContains("source") })
    }

    @Test("recipe space pulls candidates from recipe folders and recipe hosts")
    func recipeSpacePullsCandidatesFromBookmarks() {
        let recipeFolderBookmark = Bookmark(
            title: "Loaded Greek Gyro Fries",
            urlString: "https://example.com/loaded-greek-gyro-fries",
            relativePath: "Food/Recipes/Loaded Greek Gyro Fries.webloc"
        )
        let recipeHostBookmark = Bookmark(
            title: "Chocolate chip cookies",
            urlString: "https://www.allrecipes.com/chocolate-chip-cookies"
        )
        let unrelated = Bookmark(
            title: "Swift package notes",
            urlString: "https://swift.org/package-manager/"
        )

        let model = RecipeSpaceDashboardModel.make(bookmarks: [recipeFolderBookmark, recipeHostBookmark, unrelated])

        #expect(model.totalRecipeItems == 2)
        #expect(model.items.map(\.title).contains("Loaded Greek Gyro Fries"))
        #expect(model.items.map(\.title).contains("Chocolate chip cookies"))
        #expect(!model.items.map(\.title).contains("Swift package notes"))
    }

    @Test("social recipe candidates preserve source backlink metadata")
    func socialRecipeCandidatesPreserveSourceBacklinks() {
        let tiktok = Bookmark(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            title: "TikTok · crispy rice salmon recipe",
            urlString: "https://www.tiktok.com/@cook/video/12345",
            notes: "crispy rice salmon recipe with spicy mayo",
            relativePath: "Food/Recipes/TikTok crispy rice salmon.webloc"
        )

        let item = RecipeSpaceDashboardModel.make(bookmarks: [tiktok]).items.first

        #expect(item?.sourcePlatform == .tiktok)
        #expect(item?.sourceBookmarkID == tiktok.id)
        #expect(item?.sourceURL == tiktok.urlString)
        #expect(item?.sourceBacklinkLabel == "TikTok")
        #expect(item?.extractionStatus == .candidate)
    }

    @Test("recipe ratings include global and family taste signals")
    func recipeRatingsIncludeGlobalAndFamilyTasteSignals() {
        var item = RecipeCollectionItem(
            title: "Taco Pasta",
            sourceBookmarkID: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            sourceURL: "https://example.com/taco-pasta"
        )

        item = item.settingRating(.liked, for: nil)
        item = item.settingRating(.disliked, for: "Kid A")

        #expect(item.rating == .liked)
        #expect(item.familyRatings["Kid A"] == .disliked)
        #expect(item.ratingSummary == "Liked · Kid A disliked")
    }

    @Test("recipe extractor pulls structured recipe data from JSON-LD notes")
    func recipeExtractorPullsStructuredRecipeDataFromJSONLDNotes() throws {
        let bookmark = Bookmark(
            title: "Blog recipe",
            urlString: "https://example.com/crispy-rice",
            notes: """
            <script type="application/ld+json">
            {
              "@context": "https://schema.org",
              "@type": "Recipe",
              "name": "Crispy Rice Salmon Bites",
              "recipeYield": "4 servings",
              "totalTime": "PT35M",
              "recipeIngredient": ["2 cups sushi rice", "8 oz salmon", "spicy mayo"],
              "recipeInstructions": [
                {"@type":"HowToStep", "text":"Bake the salmon."},
                {"@type":"HowToStep", "text":"Crisp the rice and top with salmon."}
              ]
            }
            </script>
            """,
            relativePath: "Food/Recipes/Crispy Rice.webloc"
        )

        let extraction = try #require(RecipeExtractor.extract(from: bookmark))

        #expect(extraction.title == "Crispy Rice Salmon Bites")
        #expect(extraction.ingredients == ["2 cups sushi rice", "8 oz salmon", "spicy mayo"])
        #expect(extraction.instructions == ["Bake the salmon.", "Crisp the rice and top with salmon."])
        #expect(extraction.servings == "4 servings")
        #expect(extraction.totalTime == "35 min")
        #expect(extraction.status == .parsed)
    }

    @Test("recipe extractor pulls ingredients and steps from social captions")
    func recipeExtractorPullsIngredientsAndStepsFromSocialCaptions() throws {
        let bookmark = Bookmark(
            title: "TikTok · weeknight miso pasta recipe",
            urlString: "https://www.tiktok.com/@cook/video/67890",
            notes: """
            Weeknight miso pasta recipe
            Ingredients:
            - spaghetti
            - white miso
            - butter
            Steps:
            1. Boil pasta.
            2. Whisk miso with butter and pasta water.
            3. Toss together.
            """,
            relativePath: "Food/Recipes/TikTok Miso Pasta.webloc"
        )

        let extraction = try #require(RecipeExtractor.extract(from: bookmark))

        #expect(extraction.title == "weeknight miso pasta recipe")
        #expect(extraction.ingredients == ["spaghetti", "white miso", "butter"])
        #expect(extraction.instructions == ["Boil pasta.", "Whisk miso with butter and pasta water.", "Toss together."])
        #expect(extraction.status == .needsReview)
    }

    @Test("recipe extractor pulls inline social ingredient sections from captured TikTok notes")
    func recipeExtractorPullsInlineSocialIngredientSectionsFromCapturedTikTokNotes() throws {
        let bookmark = Bookmark(
            title: "Banana bread cinnamon rolls recipe — Annika Eats",
            urlString: "https://www.tiktok.com/t/ZP8g7xsNJ",
            notes: """
            Replying to @Hannah 3 million views later, the recipe for these banana bread cinnamon rolls is below 👇🏼 if you want more details head to the blog: https://annikaeats.com/banana-bread-batter-cinnamon-buns-no-knead-recipe/ ingredients: For the dough - 360 ml whole milk warm 2 tsp instant yeast 500g flour 60g butter
            By AnnikaEats
            Via TikTok
            """,
            relativePath: "Food/Recipes/Banana bread cinnamon rolls recipe — Annika Eats.webloc"
        )

        let extraction = try #require(RecipeExtractor.extract(from: bookmark))

        #expect(extraction.ingredients.contains("For the dough"))
        #expect(extraction.ingredients.contains("360 ml whole milk warm"))
        #expect(extraction.ingredients.contains("2 tsp instant yeast"))
        #expect(extraction.status == .needsReview)
    }

    @Test("dashboard uses parsed recipe extraction instead of keyword hints when available")
    func dashboardUsesParsedRecipeExtractionWhenAvailable() throws {
        let bookmark = Bookmark(
            title: "Chocolate cake post",
            urlString: "https://example.com/chocolate-cake",
            notes: """
            Ingredients:
            - cocoa powder
            - flour
            - eggs
            Instructions:
            1. Mix batter.
            2. Bake until set.
            """,
            relativePath: "Food/Recipes/Chocolate Cake.webloc"
        )

        let item = try #require(RecipeSpaceDashboardModel.make(bookmarks: [bookmark]).items.first)

        #expect(item.ingredients == ["cocoa powder", "flour", "eggs"])
        #expect(item.instructions == ["Mix batter.", "Bake until set."])
        #expect(item.extractionStatus == .needsReview)
        #expect(item.metadataChips.contains("Recipe pulled"))
    }

    @Test("dashboard gates extraction so unrelated ingredient-like notes do not become recipe cards")
    func dashboardGatesExtractionForUnrelatedIngredientLikeNotes() {
        let unrelated = (0..<200).map { index in
            Bookmark(
                title: "SDK rollout note \(index)",
                urlString: "https://developer.example.com/sdk-rollout-\(index)",
                notes: """
                Ingredients:
                - migration plan
                - release checklist
                - runtime flags
                Instructions:
                1. Audit call sites.
                2. Ship behind a feature flag.
                """
            )
        }
        let realRecipe = Bookmark(
            title: "Weeknight chicken rice recipe",
            urlString: "https://example.com/weeknight-chicken-rice",
            notes: "Ingredients:\n- chicken\n- rice",
            relativePath: "Food/Recipes/Weeknight chicken rice.webloc"
        )

        let start = ContinuousClock.now
        let model = RecipeSpaceDashboardModel.make(bookmarks: unrelated + [realRecipe])
        let elapsed = start.duration(to: ContinuousClock.now)
        print("RECIPE_DASHBOARD_GATE bookmarks=201 recipes=\(model.items.count) elapsed=\(elapsed)")

        #expect(model.items.map(\.title) == ["Weeknight chicken rice recipe"])
    }
}
