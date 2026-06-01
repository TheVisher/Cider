import XCTest
@testable import Cider

final class WorkspaceDomainDashboardModelTests: XCTestCase {
    func testProviderBuildsReusableDashboardMetadataForExplicitProjectBoards() {
        let model = WorkspaceDomainDashboardProvider.model(
            for: .projects,
            allTabs: [.projectBoard(projectID: "cider", boardID: "2afee0", name: "Cider Board")]
        )

        XCTAssertEqual(model.domain, .projects)
        XCTAssertEqual(model.title, "Projects")
        XCTAssertEqual(model.primaryAction?.title, "Open Cider Board")
        XCTAssertEqual(model.sections.first?.items.first?.id, "project-board-cider-2afee0")
        XCTAssertEqual(model.sections.first?.items.first?.subtitle, "cider Kanban board")
    }

    func testProviderDoesNotBackfillDomainDashboardFromRetiredViews() {
        let model = WorkspaceDomainDashboardProvider.model(
            for: .bookmarks,
            allTabs: []
        )

        XCTAssertEqual(model.domain, .bookmarks)
        XCTAssertEqual(model.primaryAction?.title, "Open Library")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testProviderBuildsEmptyDashboardWithoutBorrowingGlobalTabs() {
        let model = WorkspaceDomainDashboardProvider.model(
            for: .people,
            allTabs: []
        )

        XCTAssertEqual(model.domain, .people)
        XCTAssertEqual(model.primaryAction?.title, "Open Library")
        XCTAssertEqual(model.emptyStateTitle, "No People dashboard items yet")
        XCTAssertTrue(model.sections.isEmpty)
    }

    func testLibraryDashboardIsCatchAll() {
        let searchID = UUID(uuidString: "00000000-0000-0000-0000-00000000D001")!

        let model = WorkspaceDomainDashboardProvider.model(
            for: .browse,
            allTabs: [.search(id: searchID, query: "cider")]
        )

        XCTAssertEqual(model.title, "Library")
        XCTAssertEqual(model.sections.first?.items.map(\.title), ["cider"])
    }

    func testBookmarksDashboardAddsRecentTriageAndMetadataSections() {
        let inboxID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!
        let inboxBookmarksID = UUID(uuidString: "00000000-0000-0000-0000-00000000F002")!
        let projectFolderID = UUID(uuidString: "00000000-0000-0000-0000-00000000F003")!
        let now = Date(timeIntervalSince1970: 1_800)
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
