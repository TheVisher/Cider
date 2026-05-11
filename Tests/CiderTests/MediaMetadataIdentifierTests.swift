import XCTest
@testable import Cider

final class MediaMetadataIdentifierTests: XCTestCase {
    func testProviderURLParsersExtractStableIDsWithoutNetwork() throws {
        XCTAssertEqual(
            try candidate("https://store.steampowered.com/app/1145350/Hades_II/").externalIDs["steamAppID"],
            "1145350"
        )
        XCTAssertEqual(
            try candidate("https://www.imdb.com/title/tt1160419/?ref_=fn_al_tt_1").externalIDs["imdb"],
            "tt1160419"
        )
        XCTAssertEqual(
            try candidate("https://letterboxd.com/film/dune-part-two/").externalIDs["letterboxd"],
            "dune-part-two"
        )
        XCTAssertEqual(
            try candidate("https://trakt.tv/movies/dune-2021").externalIDs["trakt"],
            "movie:dune-2021"
        )
        XCTAssertEqual(
            try candidate("https://trakt.tv/shows/silo").externalIDs["trakt"],
            "show:silo"
        )
        XCTAssertEqual(
            try candidate("https://www.themoviedb.org/movie/438631-dune").externalIDs["tmdb"],
            "movie:438631"
        )
        XCTAssertEqual(
            try candidate("https://www.goodreads.com/book/show/58784475-tomorrow-and-tomorrow-and-tomorrow").externalIDs["goodreads"],
            "58784475"
        )
        XCTAssertEqual(
            try candidate("https://app.thestorygraph.com/books/9780593321201").externalIDs["storygraph"],
            "9780593321201"
        )
        XCTAssertEqual(
            try candidate("https://tv.apple.com/us/movie/dune-part-two/umc.cmc.363aycnv6vy9qgekvew6fveb7").externalIDs["appleTV"],
            "movie:umc.cmc.363aycnv6vy9qgekvew6fveb7"
        )
        XCTAssertEqual(
            try candidate("https://boardgamegeek.com/boardgame/174430/gloomhaven").externalIDs["boardGameGeek"],
            "174430"
        )
    }

    func testProviderURLParsersAssignExpectedMediaTypes() throws {
        XCTAssertEqual(try candidate("https://store.steampowered.com/app/1145350/Hades_II/").type, .game)
        XCTAssertEqual(try candidate("https://letterboxd.com/film/dune-part-two/").type, .movie)
        XCTAssertEqual(try candidate("https://trakt.tv/movies/dune-2021").type, .movie)
        XCTAssertEqual(try candidate("https://trakt.tv/shows/silo").type, .show)
        XCTAssertEqual(try candidate("https://www.themoviedb.org/tv/125988-silo").type, .show)
        XCTAssertEqual(try candidate("https://www.goodreads.com/book/show/58784475").type, .book)
    }

    func testIMDbParserUsesExplicitTVSeriesTitleSignal() throws {
        let bookmark = Bookmark(
            title: "Dirk Gently's Holistic Detective Agency (TV Series 2016-2017)",
            urlString: "https://www.imdb.com/title/tt4047038/"
        )

        let result = MediaMetadataIdentifier().identify(bookmark: bookmark)

        XCTAssertEqual(result.candidate?.type, .show)
        XCTAssertEqual(result.candidate?.externalIDs["imdb"], "tt4047038")
    }

    func testIdentificationCreatesReferenceForGeneralMediaSources() {
        let bookmark = Bookmark(
            title: "A long video essay",
            urlString: "https://www.youtube.com/watch?v=abc123"
        )

        let result = MediaMetadataIdentifier().identify(bookmark: bookmark)

        XCTAssertEqual(result.disposition, .review)
        XCTAssertEqual(result.candidate?.type, .reference)
        XCTAssertLessThan(result.confidence, MediaMetadataIdentifier.confidentImportThreshold)
    }

    func testVagueMediaWordsDoNotCreateConfidentMediaItems() {
        let bookmarks = [
            Bookmark(title: "Steam Easy Espresso", urlString: "https://example.com/espresso"),
            Bookmark(title: "Seasonal desk collection", urlString: "https://example.com/seasonal-desk"),
            Bookmark(title: "Watch this CSS trick", urlString: "https://example.com/watch-css"),
        ]

        let report = MediaBackfillPlanner().plan(bookmarks: bookmarks, existingItems: [])

        XCTAssertTrue(report.proposedItems.isEmpty)
        XCTAssertEqual(report.reviewItems.count, 0)
        XCTAssertEqual(report.skippedCount, 3)
    }

    func testBackfillDedupesMultipleBookmarksForSameStableProviderID() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let bookmarks = [
            Bookmark(
                id: firstID,
                title: "Hades II on Steam",
                urlString: "https://store.steampowered.com/app/1145350/Hades_II/",
                relativePath: "Inbox/Bookmarks/Hades II.webloc"
            ),
            Bookmark(
                id: secondID,
                title: "Hades II community",
                urlString: "https://steamcommunity.com/app/1145350",
                relativePath: "Bookmarks/Games/Hades II community.webloc"
            ),
        ]

        let report = MediaBackfillPlanner().plan(bookmarks: bookmarks, existingItems: [])

        XCTAssertEqual(report.proposedItems.count, 1)
        let item = report.proposedItems[0]
        XCTAssertEqual(item.id, "steam-1145350")
        XCTAssertEqual(item.sourceBookmarkIDs.sorted { $0.uuidString < $1.uuidString }, [firstID, secondID])
        XCTAssertEqual(Set(item.sourceURLs), Set(bookmarks.map(\.urlString)))
    }

    func testBackfillUpdatesExistingMediaItemWhenNewSourceMatchesStableProviderID() {
        let existingID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let newID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let existing = MediaItem(
            id: "steam-1145350",
            type: .game,
            title: "Hades II",
            externalIDs: ["steamAppID": "1145350"],
            sourceBookmarkIDs: [existingID],
            sourceRelativePaths: ["Media/Games/Hades II.webloc"],
            sourceURLs: ["https://store.steampowered.com/app/1145350/Hades_II/"],
            confidence: 0.99
        )
        let bookmarks = [
            Bookmark(
                id: newID,
                title: "Hades II community",
                urlString: "https://steamcommunity.com/app/1145350",
                relativePath: "Inbox/Bookmarks/Hades II community.webloc"
            )
        ]

        let report = MediaBackfillPlanner().plan(bookmarks: bookmarks, existingItems: [existing])

        XCTAssertEqual(report.proposedItems.count, 1)
        let item = report.proposedItems[0]
        XCTAssertEqual(item.id, "steam-1145350")
        XCTAssertEqual(item.sourceBookmarkIDs.sorted { $0.uuidString < $1.uuidString }, [existingID, newID])
        XCTAssertEqual(
            Set(item.sourceURLs),
            [
                "https://store.steampowered.com/app/1145350/Hades_II/",
                "https://steamcommunity.com/app/1145350",
            ]
        )
    }

    @MainActor
    func testDryRunDoesNotWriteFilesButApplyDoes() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-media-backfill-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let bookmarks = [
            Bookmark(title: "Hades II", urlString: "https://store.steampowered.com/app/1145350/Hades_II/")
        ]
        let storage = MediaItemStorage(vaultRoot: tempRoot)
        let service = MediaBackfillService(storage: storage)

        let dryRun = try service.identify(bookmarks: bookmarks, mode: .dryRun)
        XCTAssertEqual(dryRun.proposedItems.count, 1)
        XCTAssertTrue(storage.items.isEmpty)

        let apply = try service.identify(bookmarks: bookmarks, mode: .apply)
        XCTAssertEqual(apply.createdCount, 1)
        XCTAssertEqual(storage.items.map(\.id), ["steam-1145350"])
    }

    private func candidate(_ urlString: String) throws -> MediaIdentificationCandidate {
        let bookmark = Bookmark(title: "Saved media", urlString: urlString)
        let result = MediaMetadataIdentifier().identify(bookmark: bookmark)
        return try XCTUnwrap(result.candidate, "Expected candidate for \(urlString)")
    }
}
