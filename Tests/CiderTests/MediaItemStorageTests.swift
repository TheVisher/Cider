import XCTest
@testable import Cider

final class MediaItemStorageTests: XCTestCase {
    private func makeTempRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-media-item-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        return tempRoot
    }

    func testMediaItemYAMLRoundTripsHumanReadableFieldsAndStableID() throws {
        let item = MediaItem(
            id: "steam-1145350",
            type: .game,
            title: "Hades II",
            canonicalTitle: "hades ii",
            year: 2024,
            releaseDate: "2024-05-06",
            externalIDs: ["steamAppID": "1145350"],
            posterImagePath: nil,
            coverImageURL: "https://cdn.example/hades.jpg",
            genres: ["Action", "Roguelike"],
            categories: ["Steam"],
            status: .want,
            sourceBookmarkIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!],
            sourceRelativePaths: ["Inbox/Bookmarks/Hades II.webloc"],
            sourceURLs: ["https://store.steampowered.com/app/1145350/Hades_II/"],
            confidence: 0.98,
            identificationReason: "Steam app URL contained stable app id 1145350.",
            rawProviderPayloadPath: "Spaces/Media/.cider/provider-payloads/steam-1145350.json",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let yaml = try MediaItemYAMLCodec.encode(item)

        XCTAssertTrue(yaml.contains("id: steam-1145350"))
        XCTAssertTrue(yaml.contains("type: game"))
        XCTAssertTrue(yaml.contains("steamAppID: '1145350'"))
        XCTAssertTrue(yaml.contains("sourceURLs:"))

        let decoded = try MediaItemYAMLCodec.decode(yaml)

        XCTAssertEqual(decoded.id, "steam-1145350")
        XCTAssertEqual(decoded.type, .game)
        XCTAssertEqual(decoded.externalIDs["steamAppID"], "1145350")
        XCTAssertEqual(decoded.sourceURLs, ["https://store.steampowered.com/app/1145350/Hades_II/"])
        XCTAssertEqual(decoded.status, .want)
    }

    @MainActor
    func testStorageWritesMediaItemsUnderMediaSpaceCiderDirectoryAndReloads() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = MediaItemStorage(vaultRoot: tempRoot)
        let item = MediaItem(
            id: "imdb-tt1160419",
            type: .movie,
            title: "Dune",
            canonicalTitle: "dune",
            year: 2021,
            externalIDs: ["imdb": "tt1160419"],
            sourceURLs: ["https://www.imdb.com/title/tt1160419/"],
            confidence: 0.9
        )

        try storage.upsert(item)

        let expectedURL = tempRoot
            .appendingPathComponent("Spaces/Media/.cider/media-items/imdb-tt1160419.yaml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
        let yaml = try String(contentsOf: expectedURL, encoding: .utf8)
        XCTAssertTrue(yaml.contains("title: Dune"))

        let reloaded = MediaItemStorage(vaultRoot: tempRoot)
        XCTAssertEqual(reloaded.items.map(\.id), ["imdb-tt1160419"])
        XCTAssertEqual(reloaded.items.first?.externalIDs["imdb"], "tt1160419")
    }

    @MainActor
    func testUpsertPreservesStableIDAndMergesSourcesForSameMediaItem() throws {
        let tempRoot = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        let storage = MediaItemStorage(vaultRoot: tempRoot)

        try storage.upsert(MediaItem(
            id: "steam-1145350",
            type: .game,
            title: "Hades II",
            canonicalTitle: "hades ii",
            externalIDs: ["steamAppID": "1145350"],
            sourceBookmarkIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000001")!],
            sourceURLs: ["https://store.steampowered.com/app/1145350/Hades_II/"],
            confidence: 0.98
        ))
        try storage.upsert(MediaItem(
            id: "steam-1145350",
            type: .game,
            title: "Hades II",
            canonicalTitle: "hades ii",
            externalIDs: ["steamAppID": "1145350"],
            sourceBookmarkIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000002")!],
            sourceURLs: ["https://steamcommunity.com/app/1145350"],
            confidence: 0.95
        ))

        XCTAssertEqual(storage.items.count, 1)
        XCTAssertEqual(storage.items[0].id, "steam-1145350")
        XCTAssertEqual(storage.items[0].sourceBookmarkIDs.count, 2)
        XCTAssertEqual(storage.items[0].sourceURLs.count, 2)
    }
}
