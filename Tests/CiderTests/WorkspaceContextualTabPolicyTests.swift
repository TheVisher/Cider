import XCTest
@testable import Cider

final class WorkspaceContextualTabPolicyTests: XCTestCase {
    func testDashboardDomainShowsDashboardTabsAndKeepsAIAssistantCompatibility() {
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

        XCTAssertEqual(result.map(\.id), ["saved-\(dashboardID.uuidString)", "aiAssistant"])
    }

    func testProjectsDomainShowsKanbanTabsAndKeepsAIAssistantCompatibility() {
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

        XCTAssertEqual(result.map(\.id), ["saved-\(boardID.uuidString)", "aiAssistant"])
    }

    func testBookmarkDomainFiltersBookmarkSavedViewsButFallsBackToAllTabsWhenEmpty() {
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

        XCTAssertEqual(bookmarkTabs.map(\.id), ["saved-\(bookmarksID.uuidString)"])
        XCTAssertEqual(mediaTabs.map(\.id), tabs.map(\.id))
    }
}
