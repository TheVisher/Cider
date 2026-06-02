import XCTest
@testable import Cider

final class WorkspaceRouteTransitionPolicyTests: XCTestCase {
    func testWorkspaceRouteCodableIdentityRoundTripsNestedRoutes() throws {
        let routes: [WorkspaceRoute] = [
            .home,
            .library(.search("route policy")),
            .library(.folder(UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)),
            .projects(.workspace(
                projectID: "cider",
                section: .board(boardID: "2afee0", milestoneCardID: "67854e")
            )),
            .projects(.workspace(projectID: "cider", section: .qa)),
            .spaces(.overview(spaceID: "media-space")),
            .ai,
        ]

        let data = try JSONEncoder().encode(routes)
        let decoded = try JSONDecoder().decode([WorkspaceRoute].self, from: data)

        XCTAssertEqual(decoded, routes)
        XCTAssertEqual(Set(decoded).count, routes.count)
    }

    func testRoutePresentationExposesTitleAndIconMetadata() {
        let home = WorkspaceRoutePresentation.presentation(for: .home)
        XCTAssertEqual(home.title, "Home")
        XCTAssertEqual(home.systemImage, "house")

        let files = WorkspaceRoutePresentation.presentation(for: .library(.files))
        XCTAssertEqual(files.title, "Files")
        XCTAssertEqual(files.systemImage, "doc.text")

        let search = WorkspaceRoutePresentation.presentation(for: .library(.search("route")))
        XCTAssertEqual(search.title, "Search")
        XCTAssertEqual(search.systemImage, "magnifyingglass")

        let ai = WorkspaceRoutePresentation.presentation(for: .ai)
        XCTAssertEqual(ai.title, "AI Assistant")
        XCTAssertEqual(ai.systemImage, "sparkles")
    }

    func testProjectRoutesExposeSelectedLocalTabKind() {
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(
                for: .projects(.workspace(projectID: "cider", section: .overview))
            ).selectedProjectLocalTabKind,
            .overview
        )
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(
                for: .projects(.workspace(projectID: "cider", section: .board(boardID: "2afee0", milestoneCardID: nil)))
            ).selectedProjectLocalTabKind,
            .board("2afee0")
        )
        XCTAssertEqual(
            WorkspaceRoutePresentation.presentation(
                for: .projects(.workspace(projectID: "cider", section: .qa))
            ).selectedProjectLocalTabKind,
            .surface(.qaAudits)
        )
        XCTAssertNil(WorkspaceRoutePresentation.presentation(for: .library(.files)).selectedProjectLocalTabKind)
    }

    func testRoutePresentationCoversCanonicalRouteCases() {
        let folderID = UUID()
        let tagID = UUID()
        let expectations: [(WorkspaceRoute, WorkspaceNavigationDomain?, WorkspaceRouteContentKind)] = [
            (.home, nil, .home),
            (.library(.overview), .browse, .libraryDashboard),
            (.library(.inbox), .browse, .libraryFeed(entityTypes: LibraryEntityType.activeCases, onlyUnassigned: true)),
            (.library(.all), .browse, .libraryFeed(entityTypes: LibraryEntityType.activeCases, onlyUnassigned: false)),
            (.library(.bookmarks), .browse, .libraryFeed(entityTypes: [.bookmark], onlyUnassigned: false)),
            (.library(.notes), .browse, .libraryFeed(entityTypes: [.note], onlyUnassigned: false)),
            (.library(.files), .browse, .libraryFeed(entityTypes: [.vaultFile], onlyUnassigned: false)),
            (.library(.folders), .browse, .folder),
            (.library(.folder(folderID)), .browse, .folder),
            (.library(.tags), .browse, .tag),
            (.library(.tag(tagID)), .browse, .tag),
            (.library(.search("route")), .browse, .search),
            (.projects(.home), .projects, .projectsHome),
            (.projects(.workspace(projectID: "cider", section: .overview)), .projects, .projectOverview(projectID: "cider")),
            (.projects(.workspace(projectID: "cider", section: .inbox)), .projects, .projectInbox(projectID: "cider")),
            (
                .projects(.workspace(projectID: "cider", section: .board(boardID: "2afee0", milestoneCardID: "67854e"))),
                .projects,
                .projectBoard(boardID: "2afee0", milestoneCardID: "67854e")
            ),
            (.projects(.workspace(projectID: "cider", section: .milestones)), .projects, .projectSurface(projectID: "cider", surface: .milestones)),
            (.projects(.workspace(projectID: "cider", section: .docs)), .projects, .projectSurface(projectID: "cider", surface: .notes)),
            (.projects(.workspace(projectID: "cider", section: .decisions)), .projects, .projectSurface(projectID: "cider", surface: .decisions)),
            (.projects(.workspace(projectID: "cider", section: .assets)), .projects, .projectSurface(projectID: "cider", surface: .assets)),
            (.projects(.workspace(projectID: "cider", section: .qa)), .projects, .projectSurface(projectID: "cider", surface: .qaAudits)),
            (.projects(.workspace(projectID: "cider", section: .plans)), .projects, .projectSurface(projectID: "cider", surface: .plansHandoffs)),
            (.spaces(.overview(spaceID: "media-space")), .spaces, .spacesOverview(spaceID: "media-space")),
            (.spaces(.manager), .spaces, .spacesManager),
            (.ai, .aiAssistant, .aiAssistant),
        ]

        for (route, sidebarDomain, contentKind) in expectations {
            let presentation = WorkspaceRoutePresentation.presentation(for: route)
            XCTAssertEqual(presentation.sidebarDomain, sidebarDomain, "\(route)")
            XCTAssertEqual(presentation.contentKind, contentKind, "\(route)")
        }
    }

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
