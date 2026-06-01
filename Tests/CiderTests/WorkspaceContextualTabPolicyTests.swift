import XCTest
@testable import Cider

final class WorkspaceContextualTabPolicyTests: XCTestCase {
    func testDashboardDomainDoesNotSurfaceLegacySavedViewTabs() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let libraryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let tabs: [CiderTab] = [
            .savedView(id: dashboardID, name: "Dashboard"),
            .savedView(id: libraryID, name: "Library"),
            .aiAssistant
        ]
        let savedViews = [
            SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard),
            SavedView(id: libraryID, name: "Library", kind: .library)
        ]

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .mainDashboard,
            allTabs: tabs,
            savedViews: savedViews
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testProjectsDomainDoesNotSurfaceLegacyKanbanSavedViewTabs() {
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let tabs: [CiderTab] = [
            .savedView(id: dashboardID, name: "Dashboard"),
            .savedView(id: boardID, name: "Cider"),
            .aiAssistant
        ]
        let savedViews = [
            SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard),
            SavedView(id: boardID, name: "Cider", kind: .kanban(boardID: "2afee0"))
        ]

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .projects,
            allTabs: tabs,
            savedViews: savedViews
        )

        XCTAssertEqual(result.map(\.id), [
            CiderTab.domainDashboard(.projects).id
        ])
    }

    func testProjectsDomainWithSelectedProjectGeneratesExplicitProjectScopedTabs() {
        let selectedProject = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider project",
            boardIDs: ["2afee0", "08c899", "2d3f69"],
            referenceSearchTerms: ["cider"]
        )

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .projects,
            selectedProject: selectedProject,
            allTabs: [],
            savedViews: []
        )

        XCTAssertEqual(result.map(\.id), [
            "project-overview-cider",
            "project-inbox-cider",
            "project-board-cider-2afee0",
            "project-board-cider-08c899",
            "project-board-cider-2d3f69",
            "project-surface-cider-notes",
            "project-surface-cider-decisions",
            "project-surface-cider-assets",
            "project-surface-cider-qa-audits",
            "project-surface-cider-plans-handoffs"
        ])
        XCTAssertEqual(result.first?.displayName, "Overview")
        XCTAssertEqual(result.last?.displayName, "Plans")
    }

    func testProjectsHomeUsesProjectsDashboardWhenNoProjectIsSelected() {
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let result = WorkspaceContextualTabPolicy.tabs(
            for: .projects,
            selectedProject: nil,
            allTabs: [.savedView(id: boardID, name: "Cider")],
            savedViews: [SavedView(id: boardID, name: "Cider", kind: .kanban(boardID: "2afee0"))]
        )

        XCTAssertEqual(result.map(\.id), [
            CiderTab.domainDashboard(.projects).id
        ])
    }

    func testProjectsBrowseAllBoardsShowsOnlyAllBoardsContextTabByDefault() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let libraryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let ciderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let urgentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let savedViews = [
            SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard),
            SavedView(id: libraryID, name: "Library", kind: .library),
            SavedView(id: ciderID, name: "Cider", kind: .kanban(boardID: "2afee0")),
            SavedView(id: urgentID, name: "Urgent", kind: .library)
        ]
        let workspace = ProjectWorkspace(
            id: "browse-all-boards",
            kind: .browseAllBoards,
            title: "Browse All Boards",
            subtitle: "Every Kanban board and project artifact",
            boardIDs: ["2afee0"],
            referenceSearchTerms: []
        )

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .projects,
            selectedProject: workspace,
            selectedTab: .projectOverview(projectID: "browse-all-boards", name: "All Boards"),
            allTabs: [
                .savedView(id: dashboardID, name: "Dashboard"),
                .savedView(id: libraryID, name: "Library"),
                .savedView(id: ciderID, name: "Cider"),
                .savedView(id: urgentID, name: "Urgent")
            ],
            savedViews: savedViews
        )

        XCTAssertEqual(result.map(\.id), ["project-overview-browse-all-boards"])
        XCTAssertEqual(result.first?.displayName, "All Boards")
    }

    func testProjectsBrowseAllBoardsIgnoresLegacySavedViewBoardDrillIn() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let ciderID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let bugsID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B6")!
        let urgentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!
        let savedViews = [
            SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard),
            SavedView(id: ciderID, name: "Cider", kind: .kanban(boardID: "2afee0")),
            SavedView(id: bugsID, name: "Cider Bugs", kind: .kanban(boardID: "d4e5f6")),
            SavedView(id: urgentID, name: "Urgent", kind: .library)
        ]
        let workspace = ProjectWorkspace(
            id: "browse-all-boards",
            kind: .browseAllBoards,
            title: "Browse All Boards",
            subtitle: "Every Kanban board and project artifact",
            boardIDs: ["2afee0", "d4e5f6"],
            referenceSearchTerms: []
        )

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .projects,
            selectedProject: workspace,
            selectedTab: .savedView(id: bugsID, name: "Cider Bugs"),
            allTabs: [
                .savedView(id: dashboardID, name: "Dashboard"),
                .savedView(id: ciderID, name: "Cider"),
                .savedView(id: bugsID, name: "Cider Bugs"),
                .savedView(id: urgentID, name: "Urgent")
            ],
            savedViews: savedViews
        )

        XCTAssertEqual(result.map(\.id), ["project-overview-browse-all-boards"])
    }

    func testBookmarkDomainDoesNotSurfaceLegacySavedViewTabs() {
        let bookmarksID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")!
        let notesID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C2")!
        let tabs: [CiderTab] = [
            .savedView(id: bookmarksID, name: "Bookmarks"),
            .savedView(id: notesID, name: "Notes")
        ]
        let savedViews = [
            SavedView(
                id: bookmarksID,
                name: "Bookmarks",
                filterSpec: SavedViewFilterSpec(entityTypes: [.bookmark])
            ),
            SavedView(
                id: notesID,
                name: "Notes",
                filterSpec: SavedViewFilterSpec(entityTypes: [.note])
            )
        ]

        let bookmarkTabs = WorkspaceContextualTabPolicy.tabs(
            for: .bookmarks,
            allTabs: tabs,
            savedViews: savedViews
        )
        let mediaTabs = WorkspaceContextualTabPolicy.tabs(
            for: .media,
            allTabs: tabs,
            savedViews: savedViews
        )

        XCTAssertEqual(bookmarkTabs.map(\.id), [
            CiderTab.domainDashboard(.bookmarks).id
        ])
        XCTAssertEqual(mediaTabs.map(\.id), [CiderTab.domainDashboard(.media).id])
    }

    func testDomainDashboardTabMetadataIsStableAndNamedForDomain() {
        let tab = CiderTab.domainDashboard(.bookmarks)

        XCTAssertEqual(tab.id, "domain-dashboard-bookmarks")
        XCTAssertEqual(tab.displayName, "Bookmarks Dashboard")
        XCTAssertEqual(tab.systemImage, "bookmark")
        XCTAssertNil(tab.savedViewID)
    }

    func testBrowseDomainShowsAllNonAssistantTabsAsCatchAll() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B1")!
        let libraryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let tabs: [CiderTab] = [
            .savedView(id: dashboardID, name: "Dashboard"),
            .savedView(id: libraryID, name: "Library"),
            .savedView(id: boardID, name: "Cider"),
            .aiAssistant
        ]
        let savedViews = [
            SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard),
            SavedView(id: libraryID, name: "Library", kind: .library),
            SavedView(id: boardID, name: "Cider", kind: .kanban(boardID: "2afee0"))
        ]

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .browse,
            allTabs: tabs,
            savedViews: savedViews
        )

        XCTAssertEqual(result.map(\.id), [
            CiderTab.domainDashboard(.browse).id,
            "saved-\(dashboardID.uuidString)",
            "saved-\(libraryID.uuidString)",
            "saved-\(boardID.uuidString)"
        ])
    }

    func testAssistantDomainShowsDashboardBeforeChatSurface() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let tabs: [CiderTab] = [
            .savedView(id: dashboardID, name: "Dashboard"),
            .aiAssistant
        ]
        let savedViews = [SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard)]

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .aiAssistant,
            selectedTab: .aiAssistant,
            allTabs: tabs,
            savedViews: savedViews
        )

        XCTAssertEqual(result, [.domainDashboard(.aiAssistant), .aiAssistant])
    }

    func testPinnedSpaceAndSpacesManagerTabsOwnContextWhenNoDomainIsSelected() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-0000000000D1")!
        let libraryID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let allTabs: [CiderTab] = [
            .savedView(id: dashboardID, name: "Dashboard"),
            .savedView(id: libraryID, name: "Library"),
            .aiAssistant
        ]
        let savedViews = [
            SavedView(id: dashboardID, name: "Dashboard", kind: .dashboard),
            SavedView(id: libraryID, name: "Library", kind: .library)
        ]
        let mediaSpace = CiderTab.spaceOverview(id: "media-space", name: "Media")

        XCTAssertEqual(
            WorkspaceContextualTabPolicy.tabs(
                for: nil,
                selectedTab: mediaSpace,
                allTabs: allTabs,
                savedViews: savedViews
            ),
            [mediaSpace]
        )
        XCTAssertEqual(
            WorkspaceContextualTabPolicy.tabs(
                for: nil,
                selectedTab: .spacesManager,
                allTabs: allTabs,
                savedViews: savedViews
            ),
            [.spacesManager]
        )
    }
}
