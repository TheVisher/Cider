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

    func testDailyBriefAgendaFocusUsesSharedReminderSurfacingExplanation() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let todo = TodoCard(
            id: UUID(),
            title: "Pay rent",
            dueDate: now,
            priority: .high,
            actionURLString: "https://rent.example.com",
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now.addingTimeInterval(-3_600)
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.todo(todo)],
            recentItems: [],
            folders: [],
            surfacingDays: 7,
            now: now
        )

        let focusItem = snapshot.dailyBrief.focusItems.first
        XCTAssertEqual(focusItem?.title, "Pay rent")
        XCTAssertEqual(focusItem?.subtitle, "due today")
        XCTAssertEqual(focusItem?.surfacingExplanation?.sourceSignal, "reminder_relevance")
        XCTAssertEqual(focusItem?.surfacingExplanation?.suggestedAction, "open action URL")
        XCTAssertEqual(focusItem?.surfacingExplanation?.actionURLString, "https://rent.example.com")
    }

    func testRecentCaptureSummariesIncludeVerifiedPathTypeAndNextAction() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let folderID = UUID()
        let folder = Folder(id: folderID, name: "Research")
        let bookmark = Bookmark(
            id: UUID(),
            title: "https://example.com/article",
            urlString: "https://example.com/article",
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-60),
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: folderID,
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )
        let note = Note(
            id: UUID(),
            title: "Untitled capture",
            createdAt: now.addingTimeInterval(-240),
            modifiedAt: now.addingTimeInterval(-180)
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark), .note(note)],
            recentItems: [.bookmark(bookmark), .note(note)],
            folders: [folder],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.recentCaptureItems.map(\.title), ["https://example.com/article", "Untitled capture"])
        XCTAssertEqual(snapshot.recentCaptureItems[0].typeLabel, "Bookmark")
        XCTAssertEqual(snapshot.recentCaptureItems[0].locationLabel, "Research")
        XCTAssertEqual(snapshot.recentCaptureItems[0].suggestedAction, "Clean up title")
        XCTAssertEqual(snapshot.recentCaptureItems[1].locationLabel, "Inbox / Unfiled")
        XCTAssertEqual(snapshot.recentCaptureItems[1].suggestedAction, "Ask Erik")
    }

    func testRecentCaptureSummariesExposeWhySurfacedExplanation() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmark = Bookmark(
            id: UUID(),
            title: "Example.com",
            urlString: "https://example.com/article",
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-60),
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: nil,
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark)],
            recentItems: [.bookmark(bookmark)],
            folders: [],
            surfacingDays: 7,
            now: now
        )

        let explanation = snapshot.recentCaptureItems[0].surfacingExplanation
        XCTAssertEqual(explanation.reason, "Generic host-only bookmark title")
        XCTAssertEqual(explanation.urgency, "review")
        XCTAssertEqual(explanation.sourceSignal, "recent_capture")
        XCTAssertEqual(explanation.reviewState, "needs_review")
        XCTAssertEqual(explanation.actionURLString, "https://example.com/article")
        XCTAssertEqual(snapshot.recentCaptureItems[0].suggestedAction, explanation.suggestedAction)
    }

    func testRecentTimelineKeepsSixRecentItemsForDashboardRail() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let recentItems: [LibraryItemV2] = (0..<8).map { index in
            .note(Note(
                id: UUID(),
                title: "Recent \(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                modifiedAt: now.addingTimeInterval(TimeInterval(-index))
            ))
        }

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: recentItems,
            recentItems: recentItems,
            folders: [],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.recentItems.map(\.title), [
            "Recent 0",
            "Recent 1",
            "Recent 2",
            "Recent 3",
            "Recent 4",
            "Recent 5"
        ])
    }

    func testDashboardBuildsKanbanPulseFromCiderBoardState() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let parent = KanbanCard(
            id: "parent",
            title: "Second-brain Dashboard command center MVP",
            created: now.addingTimeInterval(-86_400 * 7)
        )
        let queued = KanbanCard(
            id: "queued-child",
            title: "Dashboard recent captures with next action",
            parentCardID: "parent",
            created: now.addingTimeInterval(-86_400 * 2)
        )
        let active = KanbanCard(
            id: "active-child",
            title: "Dashboard active work and Kanban pulse lane",
            parentCardID: "parent",
            created: now.addingTimeInterval(-86_400)
        )
        let testing = KanbanCard(
            id: "testing-child",
            title: "Dashboard Inbox and triage health lane",
            parentCardID: "parent",
            created: now.addingTimeInterval(-86_400 * 3)
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            created: now.addingTimeInterval(-86_400 * 30),
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [parent, queued]),
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [active]),
                KanbanColumn(id: "testing", name: "Testing", cards: [testing])
            ]
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            kanbanBoards: [board],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.kanbanPulseItems.map(\.cardID), ["active-child", "testing-child", "parent", "queued-child"])
        XCTAssertEqual(snapshot.kanbanPulseItems.first?.statusLabel, "In Progress")
        XCTAssertEqual(snapshot.kanbanPulseItems.first?.parentTitle, "Second-brain Dashboard command center MVP")
        XCTAssertEqual(snapshot.kanbanPulseItems.first?.suggestedAction, "Keep moving")
        XCTAssertEqual(snapshot.kanbanPulseItems[1].suggestedAction, "Needs Erik QA")
        XCTAssertEqual(snapshot.kanbanPulseItems[2].statusLabel, "Queued plan")
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
        XCTAssertEqual(snapshot.triageItems[0].suggestedAction, "Needs enrichment")
        XCTAssertEqual(snapshot.triageItems[0].confidenceLabel, "Needs approval")
        XCTAssertEqual(snapshot.triageItems[1].reason, "Untitled inbox note")
        XCTAssertEqual(snapshot.triageItems[1].suggestedAction, "Ask Erik")
    }

    func testDashboardBuildsReviewCockpitFromSharedReviewQueue() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmark = Bookmark(
            id: UUID(),
            title: "Routed capture",
            urlString: "https://example.com/routed",
            createdAt: now.addingTimeInterval(-300),
            updatedAt: now.addingTimeInterval(-240),
            folderID: nil,
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )
        let enrichmentBookmark = Bookmark(
            id: UUID(),
            title: "Needs metadata",
            urlString: "https://example.com/metadata",
            createdAt: now.addingTimeInterval(-200),
            updatedAt: now.addingTimeInterval(-180),
            folderID: nil,
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let routingItem = CiderReviewQueueItem(
            id: "review-routing-\(UUID().uuidString)",
            kind: "low_confidence_routing",
            source: "routing_decision",
            itemID: bookmark.id,
            itemType: "bookmark",
            title: "Routed capture",
            relativePath: "Inbox/Bookmarks/Routed capture.webloc",
            reason: "Low confidence route.",
            suggestedAction: "Approve or correct route",
            reviewState: "needs_review",
            confidence: 0.62,
            routingDecisionID: UUID(),
            target: CiderRoutingDecisionTarget(
                kind: "folder",
                name: "Research",
                relativePath: "Spaces/Research",
                folderID: nil
            ),
            createdAt: now.addingTimeInterval(-100),
            safeActions: ["approve", "correct", "defer"]
        )
        let enrichmentItem = CiderReviewQueueItem(
            id: "review-enrichment-\(UUID().uuidString)",
            kind: "enrichment_failed",
            source: "enrichment",
            itemID: enrichmentBookmark.id,
            itemType: "bookmark",
            title: "Needs metadata",
            relativePath: "Inbox/Bookmarks/Needs metadata.webloc",
            reason: "Metadata fetch failed.",
            suggestedAction: "Enrich before routing",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now.addingTimeInterval(-90),
            safeActions: ["enrich", "correct", "defer"]
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark), .bookmark(enrichmentBookmark)],
            recentItems: [],
            folders: [],
            reviewQueueItems: [routingItem, enrichmentItem],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitItems.map(\.title), ["Routed capture", "Needs metadata"])
        XCTAssertEqual(snapshot.reviewCockpitItems[0].kindLabel, "Routing")
        XCTAssertEqual(snapshot.reviewCockpitItems[0].reason, "Low confidence route.")
        XCTAssertEqual(snapshot.reviewCockpitItems[0].confidenceLabel, "62% confidence")
        XCTAssertEqual(snapshot.reviewCockpitItems[0].targetLabel, "Spaces/Research")
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canCorrect)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canDefer)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].item?.id, "bookmark-\(bookmark.id.uuidString)")

        XCTAssertEqual(snapshot.reviewCockpitItems[1].kindLabel, "Enrichment")
        XCTAssertNil(snapshot.reviewCockpitItems[1].confidenceLabel)
        XCTAssertEqual(snapshot.reviewCockpitItems[1].targetLabel, "Inbox/Bookmarks/Needs metadata.webloc")
        XCTAssertFalse(snapshot.reviewCockpitItems[1].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[1].canCorrect)
        XCTAssertFalse(snapshot.reviewCockpitItems[1].canDefer)
    }

    func testReviewCockpitItemsExposeDateSuggestionApprovalDestinations() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let deadlineDate = now.addingTimeInterval(60 * 60 * 24 * 10)
        let releaseDate = now.addingTimeInterval(60 * 60 * 24 * 20)
        let deadlineBookmark = Bookmark(
            id: UUID(),
            title: "Grant application",
            urlString: "https://example.com/grant",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let releaseBookmark = Bookmark(
            id: UUID(),
            title: "Album preorder",
            urlString: "https://example.com/album",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let deadlineSuggestion = CiderBookmarkDateSuggestion(
            bookmarkID: deadlineBookmark.id,
            bookmarkTitle: deadlineBookmark.title,
            sourceURL: deadlineBookmark.urlString,
            kind: "deadline",
            confidence: 0.84,
            date: deadlineDate,
            sourceField: "title",
            sourceSnippet: "Apply by May 30, 2026",
            nextSafeAction: "review_date_suggestion"
        )
        let releaseSuggestion = CiderBookmarkDateSuggestion(
            bookmarkID: releaseBookmark.id,
            bookmarkTitle: releaseBookmark.title,
            sourceURL: releaseBookmark.urlString,
            kind: "release_date",
            confidence: 0.9,
            date: releaseDate,
            sourceField: "notes",
            sourceSnippet: "Release date is June 9, 2026",
            nextSafeAction: "review_date_suggestion"
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(deadlineBookmark), .bookmark(releaseBookmark)],
            recentItems: [],
            folders: [],
            bookmarkDateSuggestionResults: [
                CiderBookmarkDateSuggestionResult(
                    command: "bookmark.date-suggestions",
                    bookmarkID: deadlineBookmark.id,
                    bookmarkTitle: deadlineBookmark.title,
                    sourceURL: deadlineBookmark.urlString,
                    suggestions: [deadlineSuggestion]
                ),
                CiderBookmarkDateSuggestionResult(
                    command: "bookmark.date-suggestions",
                    bookmarkID: releaseBookmark.id,
                    bookmarkTitle: releaseBookmark.title,
                    sourceURL: releaseBookmark.urlString,
                    suggestions: [releaseSuggestion]
                ),
            ],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitItems.map(\.title), ["Grant application", "Album preorder"])
        XCTAssertEqual(snapshot.reviewCockpitItems.map(\.kindLabel), ["Date Suggestion", "Date Suggestion"])
        XCTAssertEqual(snapshot.reviewCockpitItems[0].suggestedAction, "Approve Todo")
        XCTAssertEqual(snapshot.reviewCockpitItems[0].targetLabel, "Todo due date")
        XCTAssertEqual(snapshot.reviewCockpitItems[0].confidenceLabel, "84% confidence")
        XCTAssertEqual(snapshot.reviewCockpitItems[0].dateSuggestionApproval?.suggestionIndex, 0)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].dateSuggestionApproval?.destination, .todo)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canCorrect)
        XCTAssertFalse(snapshot.reviewCockpitItems[0].canDefer)

        XCTAssertEqual(snapshot.reviewCockpitItems[1].suggestedAction, "Approve Date Card")
        XCTAssertEqual(snapshot.reviewCockpitItems[1].targetLabel, "Date card")
        XCTAssertEqual(snapshot.reviewCockpitItems[1].dateSuggestionApproval?.suggestionIndex, 0)
        XCTAssertEqual(snapshot.reviewCockpitItems[1].dateSuggestionApproval?.destination, .dateCard)
        XCTAssertTrue(snapshot.reviewCockpitItems[1].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[1].canCorrect)
        XCTAssertFalse(snapshot.reviewCockpitItems[1].canDefer)
    }

    func testReviewCockpitSkipsDateSuggestionsAlreadyApprovedIntoLinkedItems() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let deadlineDate = now.addingTimeInterval(60 * 60 * 24 * 10)
        let bookmark = Bookmark(
            id: UUID(),
            title: "Grant application",
            urlString: "https://example.com/grant",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let suggestion = CiderBookmarkDateSuggestion(
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            kind: "deadline",
            confidence: 0.84,
            date: deadlineDate,
            sourceField: "title",
            sourceSnippet: "Apply by May 30, 2026",
            nextSafeAction: "review_date_suggestion"
        )
        let linkedTodo = TodoCard(
            title: "Grant application",
            details: "Date suggestion kind: deadline\nEvidence: Apply by May 30, 2026",
            dueDate: deadlineDate,
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: bookmark.id)],
            createdAt: now,
            updatedAt: now
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark), .todo(linkedTodo)],
            recentItems: [],
            folders: [],
            bookmarkDateSuggestionResults: [
                CiderBookmarkDateSuggestionResult(
                    command: "bookmark.date-suggestions",
                    bookmarkID: bookmark.id,
                    bookmarkTitle: bookmark.title,
                    sourceURL: bookmark.urlString,
                    suggestions: [suggestion]
                )
            ],
            surfacingDays: 7,
            now: now
        )

        XCTAssertTrue(snapshot.reviewCockpitItems.isEmpty)
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
