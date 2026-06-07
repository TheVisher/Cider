import XCTest
@testable import Cider

final class WorkspaceRouteIntentPolicyTests: XCTestCase {
    func testExternalOpenIntentsResolveRouteBeforeDetailSelection() {
        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forExternalTargetType: "board", targetID: "2afee0", boardID: nil),
            WorkspaceRouteIntent(
                route: .projects(.browseAllBoards(section: .board(boardID: "2afee0", milestoneCardID: nil))),
                detail: nil
            )
        )

        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forExternalTargetType: "card", targetID: "card-1", boardID: "2afee0"),
            WorkspaceRouteIntent(
                route: .projects(.browseAllBoards(section: .board(boardID: "2afee0", milestoneCardID: nil))),
                detail: .kanbanCard(boardID: "2afee0", cardID: "card-1")
            )
        )
    }

    func testDashboardAndQuickActionsResolveRouteableDestinations() {
        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forDashboardTarget: .inbox),
            WorkspaceRouteIntent(route: .library(.inbox), detail: nil)
        )

        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forDashboardTarget: .review),
            WorkspaceRouteIntent(route: .review, detail: nil)
        )

        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forQuickAction: .newLibraryView, selectedProjectID: nil, createdBoardID: nil),
            WorkspaceRouteIntent(route: .library(.overview), detail: nil)
        )

        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forQuickAction: .newTag, selectedProjectID: nil, createdBoardID: nil),
            WorkspaceRouteIntent(route: .library(.tags), detail: nil)
        )

        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forQuickAction: .newKanban, selectedProjectID: "cider", createdBoardID: "new-board"),
            WorkspaceRouteIntent(
                route: .projects(.workspace(projectID: "cider", section: .board(boardID: "new-board", milestoneCardID: nil))),
                detail: nil
            )
        )

        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forQuickAction: .newKanban, selectedProjectID: nil, createdBoardID: "new-board"),
            WorkspaceRouteIntent(
                route: .projects(.browseAllBoards(section: .board(boardID: "new-board", milestoneCardID: nil))),
                detail: nil
            )
        )
    }

    func testEntityTypeTabCreationResolvesLibraryRoutes() {
        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forLibraryEntityTypes: [.bookmark]),
            WorkspaceRouteIntent(route: .library(.bookmarks), detail: nil)
        )
        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forLibraryEntityTypes: [.note]),
            WorkspaceRouteIntent(route: .library(.notes), detail: nil)
        )
        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forLibraryEntityTypes: [.vaultFile]),
            WorkspaceRouteIntent(route: .library(.files), detail: nil)
        )
        XCTAssertEqual(
            WorkspaceRouteIntentPolicy.intent(forLibraryEntityTypes: LibraryEntityType.activeCases),
            WorkspaceRouteIntent(route: .library(.all), detail: nil)
        )
    }
}
