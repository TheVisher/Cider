import XCTest
@testable import Cider

final class LegacyViewStorageInboxTests: XCTestCase {
    @MainActor
    func testCanonicalInboxLegacyViewLoadsWithAllActiveEntityTypes() throws {
        let legacyViewURL = try makeLegacyViewsFileURL()
        defer { try? FileManager.default.removeItem(at: legacyViewURL.deletingLastPathComponent()) }

        try writeLegacyViewSnapshot(
            [
                LegacyView(
                    name: "Inbox",
                    filterSpec: LibraryFilterSpec(
                        entityTypes: [.bookmark, .note],
                        onlyUnassigned: true
                    )
                )
            ],
            to: legacyViewURL
        )

        let storage = LegacyViewStorage(storageFileURL: legacyViewURL)

        XCTAssertEqual(storage.views.first?.filterSpec.entityTypes, LibraryEntityType.activeCases)
        XCTAssertTrue(storage.views.first?.filterSpec.onlyUnassigned == true)
    }

    @MainActor
    func testCustomUnassignedLegacyViewKeepsItsEntityScope() throws {
        let legacyViewURL = try makeLegacyViewsFileURL()
        defer { try? FileManager.default.removeItem(at: legacyViewURL.deletingLastPathComponent()) }

        try writeLegacyViewSnapshot(
            [
                LegacyView(
                    name: "Bookmark Inbox",
                    filterSpec: LibraryFilterSpec(
                        entityTypes: [.bookmark],
                        onlyUnassigned: true
                    )
                )
            ],
            to: legacyViewURL
        )

        let storage = LegacyViewStorage(storageFileURL: legacyViewURL)

        XCTAssertEqual(storage.views.first?.filterSpec.entityTypes, [.bookmark])
    }

    private func makeLegacyViewsFileURL() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-legacy-view-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent("_cider_saved_views.json")
    }

    private func writeLegacyViewSnapshot(_ views: [LegacyView], to url: URL) throws {
        struct LegacyViewSnapshot: Codable {
            var views: [LegacyView]
            var tabOrder: [UUID]

            private enum CodingKeys: String, CodingKey {
                case views = "savedViews"
                case tabOrder
            }
        }

        let snapshot = LegacyViewSnapshot(
            views: views,
            tabOrder: views.map(\.id)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url)
    }
}
