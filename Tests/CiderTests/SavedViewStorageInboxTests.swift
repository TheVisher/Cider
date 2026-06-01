import XCTest
@testable import Cider

final class SavedViewStorageInboxTests: XCTestCase {
    @MainActor
    func testCanonicalInboxSavedViewLoadsWithAllActiveEntityTypes() throws {
        let savedViewURL = try makeSavedViewsFileURL()
        defer { try? FileManager.default.removeItem(at: savedViewURL.deletingLastPathComponent()) }

        try writeLegacySavedViews(
            [
                SavedView(
                    name: "Inbox",
                    filterSpec: SavedViewFilterSpec(
                        entityTypes: [.bookmark, .note],
                        onlyUnassigned: true
                    )
                )
            ],
            to: savedViewURL
        )

        let storage = SavedViewStorage(storageFileURL: savedViewURL)

        XCTAssertEqual(storage.savedViews.first?.filterSpec.entityTypes, LibraryEntityType.activeCases)
        XCTAssertTrue(storage.savedViews.first?.filterSpec.onlyUnassigned == true)
    }

    @MainActor
    func testCustomUnassignedSavedViewKeepsItsEntityScope() throws {
        let savedViewURL = try makeSavedViewsFileURL()
        defer { try? FileManager.default.removeItem(at: savedViewURL.deletingLastPathComponent()) }

        try writeLegacySavedViews(
            [
                SavedView(
                    name: "Bookmark Inbox",
                    filterSpec: SavedViewFilterSpec(
                        entityTypes: [.bookmark],
                        onlyUnassigned: true
                    )
                )
            ],
            to: savedViewURL
        )

        let storage = SavedViewStorage(storageFileURL: savedViewURL)

        XCTAssertEqual(storage.savedViews.first?.filterSpec.entityTypes, [.bookmark])
    }

    private func makeSavedViewsFileURL() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-saved-view-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent("_cider_saved_views.json")
    }

    private func writeLegacySavedViews(_ savedViews: [SavedView], to url: URL) throws {
        struct LegacySavedViewsSnapshot: Codable {
            var savedViews: [SavedView]
            var tabOrder: [UUID]
        }

        let snapshot = LegacySavedViewsSnapshot(
            savedViews: savedViews,
            tabOrder: savedViews.map(\.id)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: url)
    }
}
