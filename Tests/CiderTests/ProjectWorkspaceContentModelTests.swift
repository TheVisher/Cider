import XCTest
@testable import Cider

final class ProjectWorkspaceContentModelTests: XCTestCase {
    func testProjectReferencesIncludeLinkedAndTextMatchedItemsOnly() {
        let linkedID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let matchedID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let unrelatedID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let linkedRef = LibraryEntityRef(type: .bookmark, entityID: linkedID)
        let project = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let boards = [
            KanbanBoard(
                id: "2afee0",
                name: "Cider",
                columns: [
                    KanbanColumn(
                        id: "in_progress",
                        name: "In Progress",
                        cards: [
                            KanbanCard(id: "a18f97", title: "Project references MVP", linkedEntities: [linkedRef])
                        ]
                    )
                ]
            )
        ]
        let items: [LibraryItemV2] = [
            .bookmark(Bookmark(id: linkedID, title: "Linear inspiration", urlString: "https://linear.app")),
            .note(Note(id: matchedID, title: "Cider sidebar notes", content: "Reference IA")),
            .bookmark(Bookmark(id: unrelatedID, title: "Garden planning", urlString: "https://example.com/garden"))
        ]

        let references = ProjectReferenceProvider.references(for: project, items: items, boards: boards)

        XCTAssertEqual(references.map(\.item.title), ["Linear inspiration", "Cider sidebar notes"])
        XCTAssertEqual(references.first?.linkedCardCount, 1)
        XCTAssertTrue(references.first?.isLinkedToProjectCard == true)
        XCTAssertEqual(references.first?.reason, "Linked to 1 card")
    }

    func testProjectReferencesSearchFilePathsTagsAndBookmarkURLs() {
        let fileID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let bookmarkID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let project = ProjectWorkspace(
            id: "cider-ios",
            kind: .project,
            title: "Cider iOS",
            subtitle: "Mobile workspace",
            boardIDs: ["2d3f69"],
            referenceSearchTerms: ["cider ios", "cider mobile"]
        )
        let items: [LibraryItemV2] = [
            .vaultFile(VaultFile(
                id: fileID,
                filename: "dashboard.png",
                relativePath: "Projects/Cider iOS/Screenshots/dashboard.png",
                fileType: .image,
                fileSize: 128,
                createdAt: Date(timeIntervalSince1970: 10),
                modifiedAt: Date(timeIntervalSince1970: 10),
                folderID: nil
            )),
            .bookmark(Bookmark(
                id: bookmarkID,
                title: "Mobile navigation pattern",
                urlString: "https://example.com/cider-mobile-navigation",
                tags: ["inspiration"]
            ))
        ]

        let references = ProjectReferenceProvider.references(for: project, items: items, boards: [])

        XCTAssertEqual(references.map(\.item.title), ["Mobile navigation pattern", "dashboard.png"])
        XCTAssertEqual(references.map(\.reason), ["Matches Cider Mobile", "Matches Cider iOS"])
    }

    func testProjectOverviewSummarizesScopedBoardsAndHomeCommandCenter() {
        let cider = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(id: "next", title: "Next work")
                ]),
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [
                    KanbanCard(id: "active", title: "Active work")
                ]),
                KanbanColumn(id: "testing", name: "Testing", cards: [
                    KanbanCard(id: "qa", title: "Ready to Test"),
                    KanbanCard(id: "blocked", title: "Blocked by decision", tags: ["blocked"])
                ])
            ]
        )
        let web = KanbanBoard(
            id: "08c899",
            name: "Cider Web",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [
                    KanbanCard(id: "web-next", title: "Web next")
                ])
            ]
        )
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [cider, web])
        let ciderWorkspace = catalog.workspace(id: "cider")!

        let projectModel = ProjectWorkspaceOverviewProvider.model(for: ciderWorkspace, catalog: catalog, boards: [cider, web])
        let homeModel = ProjectWorkspaceOverviewProvider.model(for: catalog.home, catalog: catalog, boards: [cider, web])

        XCTAssertEqual(projectModel.boardSummaries.map(\.boardID), ["2afee0"])
        XCTAssertEqual(projectModel.totals.inProgress, 1)
        XCTAssertEqual(projectModel.totals.testing, 2)
        XCTAssertEqual(projectModel.totals.blocked, 1)
        XCTAssertEqual(homeModel.projectRows.map(\.projectID), ["cider", "cider-web"])
        XCTAssertEqual(homeModel.totals.queued, 2)
    }

    func testProjectOverviewExposesBoardCreationActionForProjectsOnly() {
        let board = KanbanBoard(id: "2afee0", name: "Cider")
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [board])
        let ciderWorkspace = catalog.workspace(id: "cider")!

        let projectModel = ProjectWorkspaceOverviewProvider.model(for: ciderWorkspace, catalog: catalog, boards: [board])
        let homeModel = ProjectWorkspaceOverviewProvider.model(for: catalog.home, catalog: catalog, boards: [board])

        XCTAssertEqual(projectModel.boardCreationActionTitle, "New Board")
        XCTAssertNil(homeModel.boardCreationActionTitle)
    }
}
