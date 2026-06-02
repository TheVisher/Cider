import XCTest
@testable import Cider

final class WorkspaceRouteTransitionPolicyTests: XCTestCase {
    func testTransitionClearsStaleCompanionStateWhenLeavingFolderForLibraryFeed() {
        let folderID = UUID()
        let tagID = UUID()
        let selectedItemID = UUID().uuidString
        let state = WorkspaceRouteCompanionState(
            selectedFolderID: folderID,
            selectedTagIDs: [tagID],
            selectedItemIDs: [selectedItemID],
            focusedItemID: selectedItemID,
            selectionAnchorID: selectedItemID,
            sidebarSearchText: "old",
            debouncedSearchText: "old",
            hasOpenDetail: true,
            hasAIAssistantContext: true
        )

        let result = WorkspaceRouteTransitionPolicy.state(
            afterNavigatingFrom: .library(.folder(folderID)),
            to: .library(.files),
            current: state
        )

        XCTAssertNil(result.selectedFolderID)
        XCTAssertTrue(result.selectedTagIDs.isEmpty)
        XCTAssertTrue(result.selectedItemIDs.isEmpty)
        XCTAssertNil(result.focusedItemID)
        XCTAssertNil(result.selectionAnchorID)
        XCTAssertEqual(result.sidebarSearchText, "")
        XCTAssertEqual(result.debouncedSearchText, "")
        XCTAssertFalse(result.hasOpenDetail)
        XCTAssertFalse(result.hasAIAssistantContext)
    }

    func testTransitionPreservesLocalPresentationPreferences() {
        let state = WorkspaceRouteCompanionState(
            displayMode: .grid,
            cardSizeScale: 1.4,
            projectBoardInspectorVisible: true
        )

        let result = WorkspaceRouteTransitionPolicy.state(
            afterNavigatingFrom: .library(.all),
            to: .projects(.workspace(projectID: "cider", section: .board(boardID: "2afee0", milestoneCardID: nil))),
            current: state
        )

        XCTAssertEqual(result.displayMode, .grid)
        XCTAssertEqual(result.cardSizeScale, 1.4)
        XCTAssertTrue(result.projectBoardInspectorVisible)
    }

    func testRoutePresentationOwnsVisibleScopeForLibraryRoutes() {
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(for: .library(.files)).visibleItemScope,
            .libraryFeed(entityTypes: [.vaultFile], onlyUnassigned: false)
        )
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(for: .library(.folder(UUID()))).visibleItemScope,
            .folder
        )
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(for: .library(.tag(UUID()))).visibleItemScope,
            .tag
        )
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(for: .library(.search("route"))).visibleItemScope,
            .search
        )
    }

    func testRoutePresentationKeepsProjectBoardAndLibraryFeedCoherent() {
        let projectBoard = WorkspaceRoutePresentation.presentation(
            for: .projects(.workspace(
                projectID: "cider",
                section: .board(boardID: "2afee0", milestoneCardID: "m1")
            ))
        )

        XCTAssertEqual(projectBoard.sidebarDomain, .projects)
        XCTAssertEqual(projectBoard.contentKind, .projectBoard(boardID: "2afee0", milestoneCardID: "m1"))
        XCTAssertEqual(projectBoard.visibleItemScope, .projectBoard(boardID: "2afee0"))
        XCTAssertFalse(projectBoard.showsLibraryViewOptions)

        let libraryFiles = WorkspaceRoutePresentation.presentation(for: .library(.files))
        XCTAssertEqual(libraryFiles.sidebarDomain, .browse)
        XCTAssertEqual(libraryFiles.contentKind, .libraryFeed(entityTypes: [.vaultFile], onlyUnassigned: false))
        XCTAssertEqual(libraryFiles.visibleItemScope, .libraryFeed(entityTypes: [.vaultFile], onlyUnassigned: false))
        XCTAssertTrue(libraryFiles.showsLibraryViewOptions)
    }
}
