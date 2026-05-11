import XCTest
@testable import Cider

final class MediaSpaceDashboardModelTests: XCTestCase {
    func testDashboardPrefersStructuredMediaItemsOverBookmarkHeuristics() {
        let steamBookmark = bookmark(
            title: "Hades II on Steam",
            url: "https://store.steampowered.com/app/1145350/Hades_II/"
        )
        let unrelatedBookmark = bookmark(
            title: "Watch this CSS trick",
            url: "https://example.com/watch-css"
        )
        let item = MediaItem(
            id: "steam-1145350",
            type: .game,
            title: "Hades II",
            canonicalTitle: "hades ii",
            externalIDs: ["steamAppID": "1145350"],
            sourceBookmarkIDs: [steamBookmark.id],
            sourceURLs: [steamBookmark.urlString],
            confidence: 0.98
        )

        let model = MediaSpaceDashboardModel.make(
            bookmarks: [steamBookmark, unrelatedBookmark],
            mediaItems: [item],
            notes: []
        )

        XCTAssertEqual(model.items(for: .games).map(\.title), ["Hades II"])
        XCTAssertEqual(model.totalMediaItems, 1)
        XCTAssertTrue(model.items(for: .inbox).isEmpty)
        XCTAssertEqual(model.items(for: .games).first?.sourceCount, 2)
        XCTAssertEqual(model.items(for: .games).first?.detailMode, .structuredMediaItem)
    }

    func testDashboardUsesBookmarkHeuristicsOnlyForNeedsSortingFallback() {
        let model = MediaSpaceDashboardModel.make(
            bookmarks: [
                bookmark(title: "Interesting media thing", url: "https://example.com/save")
            ],
            mediaItems: [],
            notes: []
        )

        XCTAssertEqual(model.items(for: .inbox).map(\.title), ["Interesting media thing"])
        XCTAssertEqual(model.totalMediaItems, 1)
        XCTAssertEqual(model.reviewItems.map(\.title), ["Interesting media thing"])
        XCTAssertEqual(model.reviewItems.first?.detailMode, .sourceBookmark)
    }

    func testStructuredMediaItemFallbackKeepsReadableSourceSummary() {
        let item = MediaItem(
            id: "imdb-tt123",
            type: .movie,
            title: "Example Movie",
            canonicalTitle: "example movie",
            year: 2026,
            externalIDs: ["imdb": "tt123"],
            genres: ["Drama", "Thriller"],
            sourceURLs: ["https://www.imdb.com/title/tt123/"],
            confidence: 0.94,
            identificationReason: "IMDb title URL"
        )

        let model = MediaSpaceDashboardModel.make(bookmarks: [], mediaItems: [item])
        let mediaSpaceItem = model.items(for: .movies).first

        XCTAssertEqual(mediaSpaceItem?.metadataSummary, "2026 · Drama, Thriller")
        XCTAssertEqual(mediaSpaceItem?.sourceSubtitle, "imdb.com")
        XCTAssertEqual(mediaSpaceItem?.sourceCount, 1)
        XCTAssertEqual(mediaSpaceItem?.detailMode, .structuredMediaItem)
    }

    func testClassifiesCommonMediaBookmarksIntoConservativeSections() {
        let model = MediaSpaceDashboardModel.make(bookmarks: [
            bookmark(title: "Hades II on Steam", url: "https://store.steampowered.com/app/1145350/Hades_II/"),
            bookmark(title: "Dune: Part Two", url: "https://letterboxd.com/film/dune-part-two/"),
            bookmark(title: "Silo Season 2 trailer", url: "https://www.youtube.com/watch?v=silo"),
            bookmark(title: "The Book of Elsewhere", url: "https://www.goodreads.com/book/show/123"),
            bookmark(title: "A great video essay about editing", url: "https://www.youtube.com/watch?v=essay")
        ])

        XCTAssertEqual(model.items(for: .games).map(\.bookmark.title), ["Hades II on Steam"])
        XCTAssertEqual(model.items(for: .movies).map(\.bookmark.title), ["Dune: Part Two"])
        XCTAssertEqual(model.items(for: .shows).map(\.bookmark.title), ["Silo Season 2 trailer"])
        XCTAssertEqual(model.items(for: .books).map(\.bookmark.title), ["The Book of Elsewhere"])
        XCTAssertEqual(model.items(for: .references).map(\.bookmark.title), ["A great video essay about editing"])
    }

    func testUnknownMediaCandidateGoesToNeedsSortingAndUnrelatedBookmarkIsIgnored() {
        let model = MediaSpaceDashboardModel.make(bookmarks: [
            bookmark(title: "Interesting media thing", url: "https://example.com/save"),
            bookmark(title: "SQLite docs", url: "https://sqlite.org/docs.html")
        ])

        XCTAssertEqual(model.items(for: .inbox).map(\.bookmark.title), ["Interesting media thing"])
        XCTAssertEqual(model.totalMediaItems, 1)
    }

    func testBookmarkDirectoryNameDoesNotMakeEveryBookmarkABook() {
        let model = MediaSpaceDashboardModel.make(bookmarks: [
            bookmark(
                title: "SQLite notes",
                url: "https://sqlite.org",
                relativePath: "Inbox/Bookmarks/SQLite notes.webloc"
            )
        ])

        XCTAssertTrue(model.items(for: .books).isEmpty)
        XCTAssertEqual(model.totalMediaItems, 0)
    }

    func testGeneralSummaryWordsDoNotForceMediaClassification() {
        let model = MediaSpaceDashboardModel.make(bookmarks: [
            Bookmark(
                title: "EnKanto - Mexican Restaurant",
                urlString: "https://www.tiktok.com/t/example",
                aiSummary: "A short clip that shows a local restaurant."
            ),
            bookmark(
                title: "Crab Season - Menu",
                url: "https://crabseason.example/menu",
                relativePath: "Bookmarks/Shows/Crab Season - Menu.webloc"
            ),
            bookmark(
                title: "Bifrost: The Ultimate All-in-One Standing Desk Collection",
                url: "https://dezctop.com/products/bifrost-series",
                relativePath: "Bookmarks/Shows/Bifrost.webloc"
            ),
            bookmark(
                title: "Steam Easy Espresso",
                url: "https://example.com/espresso",
                relativePath: "Bookmarks/Games/Steam Easy Espresso.webloc"
            )
        ])

        XCTAssertEqual(model.totalMediaItems, 0)
    }

    func testTasteSignalsComeFromPreferenceNotesWithoutCreatingMediaItems() {
        let note = Note(
            title: "Favorite games I discussed with Hermes",
            content: "I loved Outer Wilds and Disco Elysium.",
            modifiedAt: Date(timeIntervalSince1970: 2),
            relativePath: "Notes/Favorites.md"
        )

        let model = MediaSpaceDashboardModel.make(bookmarks: [], notes: [note])

        XCTAssertEqual(model.totalMediaItems, 0)
        XCTAssertEqual(model.tasteSignals().map(\.note.title), ["Favorite games I discussed with Hermes"])
        XCTAssertEqual(model.tasteSignals().first?.section, .games)
    }

    func testFeaturedItemsPreferVisualRecentMediaSections() {
        let oldMovie = bookmark(
            title: "Old Movie",
            url: "https://letterboxd.com/film/old-movie/",
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let recentGame = bookmark(
            title: "Recent Game",
            url: "https://store.steampowered.com/app/1/recent/",
            updatedAt: Date(timeIntervalSince1970: 10)
        )

        let model = MediaSpaceDashboardModel.make(bookmarks: [oldMovie, recentGame])

        XCTAssertEqual(model.featuredItems.map(\.bookmark.title), ["Old Movie", "Recent Game"])
    }

    private func bookmark(
        title: String,
        url: String,
        tags: [String] = [],
        relativePath: String? = nil,
        updatedAt: Date = Date()
    ) -> Bookmark {
        Bookmark(
            title: title,
            urlString: url,
            updatedAt: updatedAt,
            tags: tags,
            relativePath: relativePath
        )
    }
}
