import XCTest
@testable import Cider

final class HomeOverviewDataProviderTests: XCTestCase {
    func testTelemetryCountsUseMixedLibraryItems() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmark = Bookmark(
            id: UUID(),
            title: "Example",
            urlString: "https://example.com",
            createdAt: now,
            updatedAt: now,
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: nil
        )
        let note = Note(
            id: UUID(),
            title: "Spec",
            createdAt: now,
            modifiedAt: now
        )
        let todo = TodoCard(
            id: UUID(),
            title: "Ship dashboard",
            isCompleted: false,
            createdAt: now,
            updatedAt: now
        )
        let dateCard = DateCard(
            id: UUID(),
            title: "Review",
            startAt: now,
            endAt: now.addingTimeInterval(3600),
            createdAt: now,
            updatedAt: now
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark), .note(note), .todo(todo), .dateCard(dateCard)],
            recentItems: [.note(note)],
            folders: [],
            savedViews: [],
            tabOrder: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.telemetry.first(where: { $0.kind == .bookmarks })?.value, 1)
        XCTAssertEqual(snapshot.telemetry.first(where: { $0.kind == .notes })?.value, 1)
        XCTAssertEqual(snapshot.telemetry.first(where: { $0.kind == .todos })?.value, 1)
        XCTAssertEqual(snapshot.telemetry.first(where: { $0.kind == .events })?.value, 1)
    }

    func testResurfacePrefersStaleNonCompletedItems() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let staleNote = Note(
            id: UUID(),
            title: "Old note",
            createdAt: now.addingTimeInterval(-1000),
            modifiedAt: now.addingTimeInterval(-(60 * 60 * 24 * 20))
        )
        let freshNote = Note(
            id: UUID(),
            title: "Fresh note",
            createdAt: now,
            modifiedAt: now
        )
        let completedTodo = TodoCard(
            id: UUID(),
            title: "Done",
            isCompleted: true,
            createdAt: now,
            updatedAt: now.addingTimeInterval(-(60 * 60 * 24 * 40))
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.note(staleNote), .note(freshNote), .todo(completedTodo)],
            recentItems: [],
            folders: [],
            savedViews: [],
            tabOrder: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.resurfacedItems.map(\.title), ["Old note"])
    }

    func testAttentionMetricsHighlightActionableQueues() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let assignedFolderID = UUID()
        let untitledNote = Note(
            id: UUID(),
            title: "Untitled 2",
            createdAt: now.addingTimeInterval(-7200),
            modifiedAt: now.addingTimeInterval(-3600)
        )
        let dueTodayTodo = TodoCard(
            id: UUID(),
            title: "Call Maya",
            dueDate: now,
            folderID: assignedFolderID,
            createdAt: now.addingTimeInterval(-1800),
            updatedAt: now.addingTimeInterval(-1800)
        )
        let upcomingEvent = DateCard(
            id: UUID(),
            title: "Design review",
            startAt: now.addingTimeInterval(60 * 60 * 24 * 2),
            folderID: assignedFolderID,
            createdAt: now.addingTimeInterval(-5400),
            updatedAt: now.addingTimeInterval(-5400)
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.note(untitledNote), .todo(dueTodayTodo), .dateCard(upcomingEvent)],
            recentItems: [.note(untitledNote)],
            folders: [],
            savedViews: [],
            tabOrder: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.attentionMetrics.map(\.id), ["unfiled", "urgent", "dueToday", "untitledNotes"])
        XCTAssertEqual(snapshot.attentionMetrics.map(\.value), [1, 2, 1, 1])
        XCTAssertEqual(snapshot.overviewChips.map(\.id), ["recent", "unfiled", "dueToday", "resurfaced"])
    }

    func testDailyBriefFocusUsesAgendaReasonsFromRealItems() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let todo = TodoCard(
            id: UUID(),
            title: "Pay rent",
            dueDate: now,
            actionURLString: "https://rent.example.com",
            createdAt: now.addingTimeInterval(-3600),
            updatedAt: now.addingTimeInterval(-3600)
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.todo(todo)],
            recentItems: [],
            folders: [],
            savedViews: [],
            tabOrder: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.dailyBrief.focusItems.first?.title, "Pay rent")
        XCTAssertEqual(snapshot.dailyBrief.focusItems.first?.subtitle, "due today")
        XCTAssertEqual(snapshot.dailyBrief.focusItems.first?.systemImage, "checkmark.circle")
        if case .item(.todo(let focusedTodo)) = snapshot.dailyBrief.focusItems.first?.target {
            XCTAssertEqual(focusedTodo.id, todo.id)
        } else {
            XCTFail("Expected the Today brief focus item to open the real todo")
        }
    }

    func testDashboardBuildsTriageItemsWithReasonsAndActions() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let genericBookmark = Bookmark(
            id: UUID(),
            title: "example.com",
            urlString: "https://example.com/article",
            createdAt: now.addingTimeInterval(-300),
            updatedAt: now.addingTimeInterval(-300),
            folderID: nil,
            enrichmentStatus: "none",
            lastEnrichedAt: nil
        )
        let untitledNote = Note(
            id: UUID(),
            title: "Untitled 7",
            createdAt: now.addingTimeInterval(-200),
            modifiedAt: now.addingTimeInterval(-200),
            relativePath: "Inbox/Notes/Untitled 7.md",
            folderID: nil
        )
        let filedBookmark = Bookmark(
            id: UUID(),
            title: "Good title",
            urlString: "https://example.com/good-title",
            createdAt: now,
            updatedAt: now,
            folderID: UUID(),
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(genericBookmark), .note(untitledNote), .bookmark(filedBookmark)],
            recentItems: [],
            folders: [],
            savedViews: [],
            tabOrder: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.triageItems.map(\.item.id), ["bookmark-\(genericBookmark.id.uuidString)", "note-\(untitledNote.id.uuidString)"])
        XCTAssertEqual(snapshot.triageItems[0].reason, "Generic host-only bookmark title")
        XCTAssertEqual(snapshot.triageItems[0].suggestedAction, "Enrich and route")
        XCTAssertEqual(snapshot.triageItems[0].confidenceLabel, "Needs approval")
        XCTAssertEqual(snapshot.triageItems[1].reason, "Untitled inbox note")
        XCTAssertEqual(snapshot.triageItems[1].suggestedAction, "Ask Erik")
    }

    func testClosedTabsPreferRecentlyUpdatedViewsThatAreNotOpen() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let openView = SavedView(
            id: UUID(),
            name: "Inbox",
            kind: .library,
            updatedAt: now.addingTimeInterval(-100)
        )
        let closedNewer = SavedView(
            id: UUID(),
            name: "Bookmarks",
            kind: .library,
            updatedAt: now.addingTimeInterval(-50)
        )
        let closedOlder = SavedView(
            id: UUID(),
            name: "Board",
            kind: .kanban(boardID: "board-1"),
            updatedAt: now.addingTimeInterval(-500)
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            savedViews: [openView, closedOlder, closedNewer],
            tabOrder: [openView.id],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.closedTabs.map(\.name), ["Bookmarks", "Board"])
    }

    func testClosedTabsAreNotCappedAtSixItems() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let closedViews = (0..<9).map { index in
            SavedView(
                id: UUID(),
                name: "Closed \(index)",
                kind: .library,
                updatedAt: now.addingTimeInterval(TimeInterval(-index))
            )
        }

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            savedViews: closedViews,
            tabOrder: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.closedTabs.count, 9)
        XCTAssertEqual(snapshot.closedTabs.first?.name, "Closed 0")
        XCTAssertEqual(snapshot.closedTabs.last?.name, "Closed 8")
    }
}
