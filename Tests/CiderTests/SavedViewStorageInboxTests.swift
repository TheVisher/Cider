import XCTest
@testable import Cider

final class SavedViewStorageInboxTests: XCTestCase {
    @MainActor
    func testCanonicalInboxSavedViewLoadsWithAllActiveEntityTypes() throws {
        let savedViewURL = try makeSavedViewsFileURL()
        defer { try? FileManager.default.removeItem(at: savedViewURL.deletingLastPathComponent()) }

        let storage = SavedViewStorage(storageFileURL: savedViewURL)
        storage.createSavedView(
            name: "Inbox",
            filterSpec: SavedViewFilterSpec(
                entityTypes: [.bookmark, .note],
                onlyUnassigned: true
            )
        )

        let reloaded = SavedViewStorage(storageFileURL: savedViewURL)

        XCTAssertEqual(reloaded.savedViews.first?.filterSpec.entityTypes, LibraryEntityType.activeCases)
        XCTAssertTrue(reloaded.savedViews.first?.filterSpec.onlyUnassigned == true)
    }

    @MainActor
    func testCustomUnassignedSavedViewKeepsItsEntityScope() throws {
        let savedViewURL = try makeSavedViewsFileURL()
        defer { try? FileManager.default.removeItem(at: savedViewURL.deletingLastPathComponent()) }

        let storage = SavedViewStorage(storageFileURL: savedViewURL)
        storage.createSavedView(
            name: "Bookmark Inbox",
            filterSpec: SavedViewFilterSpec(
                entityTypes: [.bookmark],
                onlyUnassigned: true
            )
        )

        let reloaded = SavedViewStorage(storageFileURL: savedViewURL)

        XCTAssertEqual(reloaded.savedViews.first?.filterSpec.entityTypes, [.bookmark])
    }

    private func makeSavedViewsFileURL() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-saved-view-storage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir.appendingPathComponent("_cider_saved_views.json")
    }
}
