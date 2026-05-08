import XCTest
@testable import Cider

final class WorkspaceDomainDashboardModelTests: XCTestCase {
    func testProviderBuildsReusableDashboardMetadataForProjects() {
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let savedViews = [
            SavedView(id: boardID, name: "Cider Board", kind: .kanban(boardID: "2afee0")),
            SavedView(id: UUID(), name: "Main Dashboard", kind: .dashboard)
        ]

        let model = WorkspaceDomainDashboardProvider.model(
            for: .projects,
            savedViews: savedViews,
            allTabs: [.savedView(id: boardID, name: "Cider Board")]
        )

        XCTAssertEqual(model.domain, .projects)
        XCTAssertEqual(model.title, "Projects")
        XCTAssertEqual(model.primaryAction?.title, "Open Cider Board")
        XCTAssertEqual(model.primaryAction?.target, .savedView(id: boardID, name: "Cider Board"))
        XCTAssertEqual(model.sections.map(\.title), ["Project boards"])
        XCTAssertEqual(model.sections.first?.items.map(\.title), ["Cider Board"])
    }

    func testProviderBuildsDomainDashboardFromSavedViewsEvenWhenTabsAreClosed() {
        let bookmarkID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
        let noteID = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
        let savedViews = [
            SavedView(
                id: bookmarkID,
                name: "Bookmark Triage",
                filterSpec: SavedViewFilterSpec(entityTypes: [.bookmark]),
                kind: .library
            ),
            SavedView(
                id: noteID,
                name: "Notes Follow-up",
                filterSpec: SavedViewFilterSpec(entityTypes: [.note]),
                kind: .library
            )
        ]

        let model = WorkspaceDomainDashboardProvider.model(
            for: .bookmarks,
            savedViews: savedViews,
            allTabs: []
        )

        XCTAssertEqual(model.domain, .bookmarks)
        XCTAssertEqual(model.primaryAction?.title, "Open Bookmark Triage")
        XCTAssertEqual(model.primaryAction?.target, .savedView(id: bookmarkID, name: "Bookmark Triage"))
        XCTAssertEqual(model.sections.map(\.title), ["Bookmark views"])
        XCTAssertEqual(model.sections.first?.items.map(\.title), ["Bookmark Triage"])
    }

    func testProviderBuildsEmptyDashboardWithoutBorrowingGlobalTabs() {
        let model = WorkspaceDomainDashboardProvider.model(
            for: .people,
            savedViews: [SavedView(id: UUID(), name: "Main Dashboard", kind: .dashboard)],
            allTabs: []
        )

        XCTAssertEqual(model.domain, .people)
        XCTAssertEqual(model.primaryAction?.title, "Browse all Cider")
        XCTAssertEqual(model.emptyStateTitle, "No People dashboard items yet")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testBrowseDashboardIsCatchAll() {
        let dashboardID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!
        let boardID = UUID(uuidString: "00000000-0000-0000-0000-00000000B001")!
        let savedViews = [
            SavedView(id: dashboardID, name: "Main Dashboard", kind: .dashboard),
            SavedView(id: boardID, name: "Cider Board", kind: .kanban(boardID: "2afee0"))
        ]

        let model = WorkspaceDomainDashboardProvider.model(
            for: .browse,
            savedViews: savedViews,
            allTabs: [.savedView(id: dashboardID, name: "Main Dashboard"), .savedView(id: boardID, name: "Cider Board")]
        )

        XCTAssertEqual(model.title, "Browse")
        XCTAssertEqual(model.sections.first?.items.map(\.title), ["Main Dashboard", "Cider Board"])
    }
}
