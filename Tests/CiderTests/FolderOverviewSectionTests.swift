import XCTest
@testable import Cider

final class FolderOverviewSectionTests: XCTestCase {
    func testBuildSectionsIncludesImmediateChildrenWithDirectItemsOnly() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let rootID = UUID()
        let childAID = UUID()
        let childBID = UUID()
        let grandchildID = UUID()

        let folders = [
            Folder(id: rootID, name: "Products"),
            Folder(id: childBID, name: "Desk & Office", parentID: rootID),
            Folder(id: childAID, name: "Clothing", parentID: rootID),
            Folder(id: grandchildID, name: "Shirts", parentID: childAID)
        ]

        let childBookmarkOlder = Bookmark(
            id: UUID(),
            title: "Older child item",
            urlString: "https://example.com/older",
            createdAt: now.addingTimeInterval(-60),
            updatedAt: now.addingTimeInterval(-60),
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: childAID
        )
        let childBookmarkNewer = Bookmark(
            id: UUID(),
            title: "Newer child item",
            urlString: "https://example.com/newer",
            createdAt: now,
            updatedAt: now,
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: childAID
        )
        let otherChildNote = Note(
            id: UUID(),
            title: "Desk note",
            createdAt: now.addingTimeInterval(-120),
            modifiedAt: now.addingTimeInterval(-120),
            folderID: childBID
        )
        let grandchildNote = Note(
            id: UUID(),
            title: "Nested shirt note",
            createdAt: now.addingTimeInterval(-30),
            modifiedAt: now.addingTimeInterval(-30),
            folderID: grandchildID
        )
        let rootNote = Note(
            id: UUID(),
            title: "Root note",
            createdAt: now.addingTimeInterval(-10),
            modifiedAt: now.addingTimeInterval(-10),
            folderID: rootID
        )

        let sections = FolderOverviewSection.buildSections(
            parentFolderID: rootID,
            folders: folders,
            items: [
                .bookmark(childBookmarkOlder),
                .bookmark(childBookmarkNewer),
                .note(otherChildNote),
                .note(grandchildNote),
                .note(rootNote)
            ] as [LibraryItemV2]
        )

        XCTAssertEqual(sections.map(\.folder.name), ["Clothing", "Desk & Office"])
        XCTAssertEqual(sections[0].items.map(\.title), ["Newer child item", "Older child item"])
        XCTAssertEqual(sections[1].items.map(\.title), ["Desk note"])
        XCTAssertFalse(sections.flatMap(\.items).map(\.title).contains("Nested shirt note"))
        XCTAssertFalse(sections.flatMap(\.items).map(\.title).contains("Root note"))
    }

    func testBuildSectionsIncludesImmediateChildrenEvenWhenEmpty() {
        let rootID = UUID()
        let emptyChildID = UUID()
        let filledChildID = UUID()

        let folders = [
            Folder(id: rootID, name: "Food"),
            Folder(id: emptyChildID, name: "Recipes", parentID: rootID),
            Folder(id: filledChildID, name: "Restaurants", parentID: rootID)
        ]

        let bookmark = Bookmark(
            id: UUID(),
            title: "Cafe",
            urlString: "https://example.com/cafe",
            createdAt: .now,
            updatedAt: .now,
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: filledChildID
        )

        let sections = FolderOverviewSection.buildSections(
            parentFolderID: rootID,
            folders: folders,
            items: [.bookmark(bookmark)] as [LibraryItemV2]
        )

        XCTAssertEqual(sections.map(\.folder.name), ["Recipes", "Restaurants"])
        XCTAssertTrue(sections[0].items.isEmpty)
        XCTAssertEqual(sections[1].items.map(\.title), ["Cafe"])
    }

    func testPreviewLayoutUsesTrailingMoreCardWhenWidthCannotFitAllItems() {
        let items = makeItems(count: 5)

        let layout = FolderOverviewSection.previewLayout(
            items: items,
            availableWidth: 520,
            preferredCardWidth: 160,
            itemSpacing: 12
        )

        XCTAssertEqual(layout.visibleItemCount, 2)
        XCTAssertTrue(layout.showsMoreCard)
        XCTAssertEqual(layout.remainingItemCount, 3)
    }

    func testPreviewLayoutShowsAllItemsWhenEnoughWidth() {
        let items = makeItems(count: 3)

        let layout = FolderOverviewSection.previewLayout(
            items: items,
            availableWidth: 640,
            preferredCardWidth: 160,
            itemSpacing: 12
        )

        XCTAssertEqual(layout.visibleItemCount, 3)
        XCTAssertFalse(layout.showsMoreCard)
        XCTAssertEqual(layout.remainingItemCount, 0)
    }

    func testPreviewLayoutKeepsOneRealPreviewWhenOnlyOneCardFits() {
        let items = makeItems(count: 4)

        let layout = FolderOverviewSection.previewLayout(
            items: items,
            availableWidth: 120,
            preferredCardWidth: 160,
            itemSpacing: 12
        )

        XCTAssertEqual(layout.visibleItemCount, 1)
        XCTAssertFalse(layout.showsMoreCard)
        XCTAssertEqual(layout.remainingItemCount, 3)
    }

    func testFolderCardSummaryPrefersDirectItemsForBadgeAndShowsBothMetrics() {
        let rootID = UUID()
        let childID = UUID()
        let siblingID = UUID()

        let folders = [
            Folder(id: rootID, name: "Products"),
            Folder(id: childID, name: "Clothing", parentID: rootID),
            Folder(id: siblingID, name: "Desk", parentID: rootID)
        ]

        let items = [
            makeBookmark(title: "Arm Rest", folderID: rootID),
            makeBookmark(title: "Mouse", folderID: childID)
        ]

        let summary = FolderCardSummary.build(
            folderID: rootID,
            folders: folders,
            items: items
        )

        XCTAssertEqual(summary.directItemCount, 1)
        XCTAssertEqual(summary.childFolderCount, 2)
        XCTAssertEqual(summary.badgeCount, 1)
        XCTAssertEqual(
            summary.metrics,
            [
                FolderCardSummary.Metric(count: 1, systemImage: "square.stack"),
                FolderCardSummary.Metric(count: 2, systemImage: "folder")
            ]
        )
        XCTAssertFalse(summary.isEmpty)
    }

    func testFolderCardSummaryUsesChildFolderCountWhenNoDirectItemsExist() {
        let rootID = UUID()
        let childID = UUID()

        let folders = [
            Folder(id: rootID, name: "Restaurants"),
            Folder(id: childID, name: "Bellevue", parentID: rootID)
        ]

        let summary = FolderCardSummary.build(
            folderID: rootID,
            folders: folders,
            items: []
        )

        XCTAssertEqual(summary.directItemCount, 0)
        XCTAssertEqual(summary.childFolderCount, 1)
        XCTAssertEqual(summary.badgeCount, 1)
        XCTAssertEqual(
            summary.metrics,
            [FolderCardSummary.Metric(count: 1, systemImage: "folder")]
        )
        XCTAssertFalse(summary.isEmpty)
    }

    func testFolderCardSummaryOnlyReportsEmptyWhenNoItemsOrChildFoldersExist() {
        let folderID = UUID()

        let summary = FolderCardSummary.build(
            folderID: folderID,
            folders: [Folder(id: folderID, name: "Empty")],
            items: []
        )

        XCTAssertEqual(summary.badgeCount, nil)
        XCTAssertTrue(summary.metrics.isEmpty)
        XCTAssertTrue(summary.isEmpty)
    }

    func testFolderCardSummaryContentDescriptionHandlesSubfolderOnlyFolders() {
        let summary = FolderCardSummary.build(
            directItemCount: 0,
            childFolderCount: 9
        )

        XCTAssertEqual(summary.contentDescription, "9 subfolders")
    }

    func testFolderCardSummaryContentDescriptionHandlesMixedFolders() {
        let summary = FolderCardSummary.build(
            directItemCount: 1,
            childFolderCount: 5
        )

        XCTAssertEqual(summary.contentDescription, "1 direct item and 5 subfolders")
    }

    func testFolderCardSummaryTotalCountCombinesDirectItemsAndChildFolders() {
        let summary = FolderCardSummary.build(
            directItemCount: 1,
            childFolderCount: 2
        )

        XCTAssertEqual(summary.totalCount, 3)
    }

    func testFolderCardSummaryTotalCountIsZeroWhenFolderIsEmpty() {
        let summary = FolderCardSummary.build(
            directItemCount: 0,
            childFolderCount: 0
        )

        XCTAssertEqual(summary.totalCount, 0)
    }

    private func makeItems(count: Int) -> [LibraryItemV2] {
        let now = Date(timeIntervalSince1970: 1_745_084_400)

        return (0..<count).map { index in
            let bookmark = Bookmark(
                id: UUID(),
                title: "Item \(index)",
                urlString: "https://example.com/\(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                updatedAt: now.addingTimeInterval(TimeInterval(-index)),
                notes: "",
                tags: [],
                labelIDs: [],
                dismissedLabelIDs: [],
                folderID: UUID()
            )
            return .bookmark(bookmark)
        }
    }

    private func makeBookmark(title: String, folderID: UUID) -> LibraryItemV2 {
        .bookmark(
            Bookmark(
                id: UUID(),
                title: title,
                urlString: "https://example.com/\(title)",
                createdAt: .now,
                updatedAt: .now,
                notes: "",
                tags: [],
                labelIDs: [],
                dismissedLabelIDs: [],
                folderID: folderID
            )
        )
    }
}
