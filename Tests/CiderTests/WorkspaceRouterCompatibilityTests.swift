import XCTest
@testable import Cider

final class WorkspaceRouterCompatibilityTests: XCTestCase {
    func testCompatibilityMapsLibraryDomainRoutesAndStaleStatePriority() {
        let folderID = UUID()
        let tagID = UUID()

        XCTAssertEqual(
            WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                legacyTab: .domainDashboard(.browse),
                selectedNavigationDomain: .browse,
                selectedDomainRouteKind: .files
            )),
            .library(.files)
        )

        XCTAssertEqual(
            WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                legacyTab: .search(id: UUID(), query: "route"),
                selectedNavigationDomain: .browse,
                selectedDomainRouteKind: .all,
                selectedFolderID: folderID
            )),
            .library(.folder(folderID))
        )

        XCTAssertEqual(
            WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                legacyTab: .domainDashboard(.browse),
                selectedNavigationDomain: .browse,
                selectedDomainRouteKind: .all,
                selectedTagIDs: [tagID]
            )),
            .library(.tag(tagID))
        )
    }

    func testCompatibilityMapsExistingTabsIntoWorkspaceRoutes() {
        let searchID = UUID()

        let expectations: [(CiderTab, WorkspaceRoute)] = [
            (.domainDashboard(.mainDashboard), .home),
            (.domainDashboard(.browse), .library(.overview)),
            (.domainDashboard(.projects), .projects(.home)),
            (.projectOverview(projectID: "cider", name: "Overview"), .projects(.workspace(projectID: "cider", section: .overview))),
            (.projectInbox(projectID: "cider", name: "Inbox"), .projects(.workspace(projectID: "cider", section: .inbox))),
            (.projectBoard(projectID: "cider", boardID: "2afee0", name: "Cider"), .projects(.workspace(projectID: "cider", section: .board(boardID: "2afee0", milestoneCardID: nil)))),
            (.projectSurface(projectID: "cider", surface: .qaAudits, name: "QA"), .projects(.workspace(projectID: "cider", section: .qa))),
            (.projectReferences(projectID: "cider", name: "References"), .projects(.workspace(projectID: "cider", section: .assets))),
            (.spaceOverview(id: "media-space", name: "Media"), .spaces(.overview(spaceID: "media-space"))),
            (.spacesManager, .spaces(.manager)),
            (.aiAssistant, .ai),
            (.search(id: searchID, query: "route"), .library(.search("route"))),
            (.tag(id: searchID), .library(.tags)),
        ]

        for (tab, route) in expectations {
            XCTAssertEqual(
                WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(legacyTab: tab)),
                route,
                "\(tab)"
            )
        }
    }

    func testCompatibilityKeepsLegacyDomainDeepLinksAfterPrimaryRootSimplification() {
        let expectations: [(WorkspaceNavigationDomain, WorkspaceRoute)] = [
            (.projects, .projects(.home)),
            (.tasksEvents, .library(.overview)),
            (.people, .library(.overview)),
            (.media, .library(.overview)),
            (.bookmarks, .library(.bookmarks)),
            (.notes, .library(.notes)),
            (.files, .library(.files)),
            (.review, .review)
        ]

        for (domain, expectedRoute) in expectations {
            XCTAssertTrue(domain.isDomainSpaceSurface, "\(domain.title) should be classified as a domain surface")
            XCTAssertEqual(
                WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                    selectedNavigationDomain: domain,
                    selectedDomainRouteKind: .overview
                )),
                expectedRoute,
                "\(domain.title) legacy route should stay compatibility-mapped"
            )
        }
    }

    func testCompatibilityPrioritizesAllCiderHomeOverStaleDomainState() {
        let folderID = UUID()
        let tagID = UUID()

        let staleStates: [WorkspaceRouterCompatibilityState] = [
            WorkspaceRouterCompatibilityState(
                legacyTab: .domainDashboard(.mainDashboard),
                selectedNavigationDomain: .browse,
                selectedDomainRouteKind: .bookmarks,
                selectedFolderID: folderID,
                selectedTagIDs: [tagID],
                selectedProjectWorkspaceID: "cider"
            ),
            WorkspaceRouterCompatibilityState(
                legacyTab: .domainDashboard(.mainDashboard),
                selectedNavigationDomain: .projects,
                selectedDomainRouteKind: .all,
                selectedProjectWorkspaceID: "browse-all-boards"
            ),
            WorkspaceRouterCompatibilityState(
                legacyTab: .domainDashboard(.mainDashboard),
                selectedNavigationDomain: .aiAssistant,
                selectedDomainRouteKind: .chats,
                selectedProjectWorkspaceID: "cider"
            ),
            WorkspaceRouterCompatibilityState(
                selectedNavigationDomain: nil,
                selectedDomainRouteKind: .bookmarks,
                selectedFolderID: folderID,
                selectedTagIDs: [tagID],
                selectedProjectWorkspaceID: "browse-all-boards"
            ),
        ]

        for state in staleStates {
            XCTAssertEqual(
                WorkspaceRouterCompatibility.route(from: state),
                .home,
                "All Cider/Home must be a real global route, not stale domain content for \(state)"
            )
        }
    }

    func testCompatibilityMapsProjectAndBrowseAllBoardsStateWithoutSelectedTab() {
        XCTAssertEqual(
            WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                selectedNavigationDomain: .projects,
                selectedDomainRouteKind: .overview
            )),
            .projects(.home)
        )

        XCTAssertEqual(
            WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                selectedNavigationDomain: .projects,
                selectedDomainRouteKind: .overview,
                selectedProjectWorkspaceID: "cider"
            )),
            .projects(.workspace(projectID: "cider", section: .overview))
        )

        XCTAssertEqual(
            WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                selectedNavigationDomain: .projects,
                selectedDomainRouteKind: .overview,
                selectedProjectWorkspaceID: "browse-all-boards"
            )),
            .projects(.browseAllBoards(section: .overview))
        )
    }

    func testCompatibilityMapsBrowseRouteKindsWithoutSelectedTab() {
        let cases: [(WorkspaceDomainRouteKind, WorkspaceRoute)] = [
            (.overview, .library(.overview)),
            (.inbox, .library(.inbox)),
            (.all, .library(.all)),
            (.bookmarks, .library(.bookmarks)),
            (.notes, .library(.notes)),
            (.files, .library(.files)),
            (.folders, .library(.folders)),
            (.tags, .library(.tags))
        ]

        for (routeKind, expectedRoute) in cases {
            XCTAssertEqual(
                WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: routeKind
                )),
                expectedRoute,
                "\(routeKind)"
            )
        }
    }

    func testWorkspaceRouterNavigateUpdatesCurrentRouteAndAppliesTransitionPolicy() {
        var router = WorkspaceRouter(
            currentRoute: .library(.folder(UUID())),
            companionState: WorkspaceRouteCompanionState(
                selectedItemIDs: ["item-1"],
                focusedItemID: "item-1",
                sidebarSearchText: "old",
                hasOpenDetail: true,
                displayMode: .grid
            )
        )

        router.navigate(to: .library(.files))

        XCTAssertEqual(router.currentRoute, .library(.files))
        XCTAssertTrue(router.companionState.selectedItemIDs.isEmpty)
        XCTAssertNil(router.companionState.focusedItemID)
        XCTAssertEqual(router.companionState.sidebarSearchText, "")
        XCTAssertFalse(router.companionState.hasOpenDetail)
        XCTAssertEqual(router.companionState.displayMode, .grid)
        XCTAssertEqual(router.presentation, WorkspaceRoutePresentation.presentation(for: .library(.files)))
    }
}
