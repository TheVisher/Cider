import XCTest
@testable import Cider

final class WorkspaceDomainDashboardModelTests: XCTestCase {
    func testProviderBuildsReusableDashboardMetadataForProjectsWithoutLegacySavedViews() {
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
        XCTAssertEqual(model.primaryAction?.title, "Open Library")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testProviderDoesNotBackfillDomainDashboardFromLegacySavedViews() {
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
        XCTAssertEqual(model.primaryAction?.title, "Open Library")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testProviderBuildsEmptyDashboardWithoutBorrowingGlobalTabs() {
        let model = WorkspaceDomainDashboardProvider.model(
            for: .people,
            savedViews: [SavedView(id: UUID(), name: "Main Dashboard", kind: .dashboard)],
            allTabs: []
        )

        XCTAssertEqual(model.domain, .people)
        XCTAssertEqual(model.primaryAction?.title, "Open Library")
        XCTAssertEqual(model.emptyStateTitle, "No People dashboard items yet")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testLibraryDashboardIsCatchAll() {
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

        XCTAssertEqual(model.title, "Library")
        XCTAssertNil(model.sections.first?.items.map(\.title))
    }

    func testBookmarksDashboardAddsRecentTriageAndMetadataSections() {
        let inboxID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
        let inboxBookmarksID = UUID(uuidString: "00000000-0000-0000-0000-00000000F002")!
        let projectFolderID = UUID(uuidString: "00000000-0000-0000-0000-00000000F003")!
        let now = Date(timeIntervalSince1970: 1_800)
        let savedViews = [
            SavedView(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!,
                name: "Bookmarks",
                filterSpec: SavedViewFilterSpec(entityTypes: [.bookmark]),
                kind: .library
            )
        ]
        let folders = [
            Folder(id: inboxID, name: "Inbox"),
            Folder(id: inboxBookmarksID, name: "Bookmarks", parentID: inboxID),
            Folder(id: projectFolderID, name: "Projects")
        ]
        let bookmarks = [
            Bookmark(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!,
                title: "Fresh Cider Link",
                urlString: "https://cider.example/fresh",
                createdAt: now,
                updatedAt: now,
                folderID: projectFolderID,
                metadataUpdatedAt: now,
                aiSummary: "A complete bookmark.",
                enrichmentStatus: "complete",
                lastEnrichedAt: now
            ),
            Bookmark(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!,
                title: "Inbox Link",
                urlString: "https://triage.example/link",
                createdAt: now.addingTimeInterval(-20),
                updatedAt: now.addingTimeInterval(-20),
                folderID: inboxBookmarksID,
                relativePath: "Inbox/Bookmarks/Inbox Link.webloc"
            ),
            Bookmark(
                id: UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!,
                title: "Missing Metadata",
                urlString: "https://metadata.example/link",
                createdAt: now.addingTimeInterval(-40),
                updatedAt: now.addingTimeInterval(-5),
                folderID: projectFolderID,
                enrichmentStatus: "partial"
            )
        ]

        let model = WorkspaceDomainDashboardProvider.model(
            for: .bookmarks,
            savedViews: savedViews,
            allTabs: [],
            bookmarks: bookmarks,
            bookmarkFolders: folders
        )

        XCTAssertEqual(model.sections.map(\.title), [
            "Recent bookmarks",
            "Needs triage",
            "Needs metadata"
        ])
        XCTAssertEqual(model.sections.first(where: { $0.id == "bookmarks-recent" })?.items.first?.title, "Fresh Cider Link")
        XCTAssertEqual(model.sections.first(where: { $0.id == "bookmarks-triage" })?.items.map(\.title), ["Inbox Link"])
        XCTAssertEqual(model.sections.first(where: { $0.id == "bookmarks-metadata" })?.items.map(\.title), ["Missing Metadata", "Inbox Link"])
    }
}
