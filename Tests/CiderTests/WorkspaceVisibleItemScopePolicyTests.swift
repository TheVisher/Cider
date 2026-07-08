import XCTest
@testable import Cider

final class WorkspaceVisibleItemScopePolicyTests: XCTestCase {
    func testTopLevelLibraryRouteShowsExistingLibraryItems() {
        let presentation = WorkspaceRoutePresentation.presentation(for: .library(.overview))
        let bookmark = LibraryItemV2.bookmark(Bookmark(title: "Bookmark", urlString: "https://example.com"))
        let note = LibraryItemV2.note(Note(title: "Note"))
        let file = LibraryItemV2.vaultFile(VaultFile(
            id: UUID(),
            filename: "Archive.pdf",
            relativePath: "Documents/Archive.pdf",
            fileType: .pdf,
            fileSize: 10,
            createdAt: Date(),
            modifiedAt: Date(),
            folderID: nil
        ))
        let todo = LibraryItemV2.todo(TodoCard(title: "Task"))

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: presentation.visibleItemScope,
                items: [bookmark, note, file, todo],
                folderID: nil,
                tagIDs: [],
                searchText: ""
            ),
            [bookmark.id, note.id, file.id, todo.id]
        )
    }

    func testTopLevelLibraryRouteStaysTruthfullyEmptyWithoutLibraryItems() {
        let presentation = WorkspaceRoutePresentation.presentation(for: .library(.overview))

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: presentation.visibleItemScope,
                items: [],
                folderID: nil,
                tagIDs: [],
                searchText: ""
            ),
            []
        )
    }

    func testLibraryFeedScopeFiltersEntityTypesAndInboxState() {
        let folderID = UUID()
        let bookmark = LibraryItemV2.bookmark(Bookmark(title: "Bookmark", urlString: "https://example.com"))
        let note = LibraryItemV2.note(Note(title: "Note"))
        let assignedNote = LibraryItemV2.note(Note(title: "Assigned", folderID: folderID))

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: .libraryFeed(entityTypes: [.bookmark, .note], onlyUnassigned: false),
                items: [bookmark, note, assignedNote],
                folderID: nil,
                tagIDs: [],
                searchText: ""
            ),
            [bookmark.id, note.id, assignedNote.id]
        )

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: .libraryFeed(entityTypes: LibraryEntityType.activeCases, onlyUnassigned: true),
                items: [bookmark, note, assignedNote],
                folderID: nil,
                tagIDs: [],
                searchText: ""
            ),
            [bookmark.id, note.id]
        )
    }

    func testFolderTagAndSearchScopesUseTheRouteVisibleItems() {
        let folderID = UUID()
        let tagID = UUID()
        let folderBookmark = LibraryItemV2.bookmark(Bookmark(title: "Folder route", urlString: "https://example.com/folder", folderID: folderID))
        let tagNote = LibraryItemV2.note(Note(title: "Tagged route note", labelIDs: [tagID]))
        let unrelated = LibraryItemV2.bookmark(Bookmark(title: "Other", urlString: "https://example.com/other"))
        let items = [folderBookmark, tagNote, unrelated]

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: .folder,
                items: items,
                folderID: folderID,
                tagIDs: [],
                searchText: ""
            ),
            [folderBookmark.id]
        )

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: .tag,
                items: items,
                folderID: nil,
                tagIDs: [tagID],
                searchText: ""
            ),
            [tagNote.id]
        )

        XCTAssertEqual(
            WorkspaceVisibleItemScopePolicy.visibleItemIDs(
                for: .search,
                items: items,
                folderID: nil,
                tagIDs: [],
                searchText: "route"
            ),
            [folderBookmark.id, tagNote.id]
        )
    }
}
