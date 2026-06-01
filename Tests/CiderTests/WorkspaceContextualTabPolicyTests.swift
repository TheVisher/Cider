import XCTest
@testable import Cider

final class WorkspaceContextualTabPolicyTests: XCTestCase {
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
            allTabs: []
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
        let result = WorkspaceContextualTabPolicy.tabs(
            for: .projects,
            selectedProject: nil,
            allTabs: []
        )

        XCTAssertEqual(result.map(\.id), [
            CiderTab.domainDashboard(.projects).id
        ])
    }

    func testProjectsBrowseAllBoardsShowsOnlyAllBoardsContextTabByDefault() {
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
            allTabs: []
        )

        XCTAssertEqual(result.map(\.id), ["project-overview-browse-all-boards"])
        XCTAssertEqual(result.first?.displayName, "All Boards")
    }

    func testProjectsBrowseAllBoardsKeepsExplicitSelectedBoardTab() {
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
            selectedTab: .projectBoard(projectID: "browse-all-boards", boardID: "d4e5f6", name: "Cider Bugs"),
            allTabs: []
        )

        XCTAssertEqual(result.map(\.id), [
            "project-overview-browse-all-boards",
            "project-board-browse-all-boards-d4e5f6"
        ])
    }

    func testDomainDashboardTabMetadataIsStableAndNamedForDomain() {
        let tab = CiderTab.domainDashboard(.bookmarks)

        XCTAssertEqual(tab.id, "domain-dashboard-bookmarks")
        XCTAssertEqual(tab.displayName, "Bookmarks Dashboard")
        XCTAssertEqual(tab.systemImage, "bookmark")
    }

    func testBrowseDomainShowsExplicitDynamicTabsAsCatchAll() {
        let searchID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
        let tagID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!
        let tabs: [CiderTab] = [
            .search(id: searchID, query: "cider"),
            .tag(id: tagID),
            .aiAssistant
        ]

        let result = WorkspaceContextualTabPolicy.tabs(
            for: .browse,
            allTabs: tabs
        )

        XCTAssertEqual(result.map(\.id), [
            CiderTab.domainDashboard(.browse).id,
            "search-\(searchID.uuidString)",
            "tag-\(tagID.uuidString)"
        ])
    }

    func testAssistantDomainShowsDashboardBeforeChatSurface() {
        let result = WorkspaceContextualTabPolicy.tabs(
            for: .aiAssistant,
            selectedTab: .aiAssistant,
            allTabs: [.aiAssistant]
        )

        XCTAssertEqual(result, [.domainDashboard(.aiAssistant), .aiAssistant])
    }

    func testPinnedSpaceAndSpacesManagerTabsOwnContextWhenNoDomainIsSelected() {
        let mediaSpace = CiderTab.spaceOverview(id: "media-space", name: "Media")

        XCTAssertEqual(
            WorkspaceContextualTabPolicy.tabs(
                for: nil,
                selectedTab: mediaSpace,
                allTabs: [mediaSpace, .aiAssistant]
            ),
            [mediaSpace]
        )
        XCTAssertEqual(
            WorkspaceContextualTabPolicy.tabs(
                for: nil,
                selectedTab: .spacesManager,
                allTabs: [.spacesManager, .aiAssistant]
            ),
            [.spacesManager]
        )
    }
}
