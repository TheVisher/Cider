import XCTest
@testable import Cider

final class HomeOverviewDataProviderTests: XCTestCase {
    func testHomeOverviewReadModelDoesNotConsumeDashboardTopicStorage() throws {
        let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let homeSources = try [
            "Sources/Cider/Views/Home/HomeOverviewDataProvider.swift",
            "Sources/Cider/Views/Home/HomeOverviewModels.swift",
        ]
        .map { try String(contentsOf: repoRoot.appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")

        XCTAssertFalse(homeSources.contains("DashboardStorage"))
        XCTAssertFalse(homeSources.contains("DashboardTopic"))
        XCTAssertFalse(homeSources.contains("DashboardCard"))
    }

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
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.attentionMetrics.map(\.id), ["unfiled", "urgent", "dueToday", "untitledNotes"])
        XCTAssertEqual(snapshot.attentionMetrics.map(\.value), [1, 2, 1, 1])
        XCTAssertEqual(snapshot.overviewChips.map(\.id), ["recent", "unfiled", "dueToday", "resurfaced"])
    }

    func testAttentionMetricsPromoteReviewQueueCountFromSummary() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            reviewQueueSummary: CiderReviewQueueSummaryResult(
                command: "review.summary",
                generatedAt: now,
                totalCount: 144,
                countsByKind: ["low_confidence_routing": 94, "enrichment_failed": 50],
                countsByItemType: ["bookmark": 144],
                countsByReviewState: ["needs_review": 144],
                countsBySafeAction: ["approve": 94, "enrich": 50]
            ),
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.attentionMetrics.first?.id, "review")
        XCTAssertEqual(snapshot.attentionMetrics.first?.title, "Review")
        XCTAssertEqual(snapshot.attentionMetrics.first?.value, 144)
        XCTAssertEqual(snapshot.attentionMetrics.first?.target, .review)
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
        XCTAssertEqual(focusItem?.visibleWhyLine, "Why: Due today")
        XCTAssertEqual(focusItem?.visibleNextActionLine, "Next: open action URL")
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
        XCTAssertEqual(snapshot.recentCaptureItems[0].visibleWhyLine, "Why: Generic host-only bookmark title")
        XCTAssertEqual(snapshot.recentCaptureItems[0].visibleNextActionLine, "Next: Clean up title")
    }

    func testRecentCaptureResultAffordancesCoverMultiTypeCapture() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let folder = Folder(id: UUID(), name: "Research")
        let bookmark = Bookmark(
            id: UUID(),
            title: "Example.com",
            urlString: "https://example.com/article",
            createdAt: now.addingTimeInterval(-10),
            updatedAt: now.addingTimeInterval(-9),
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: nil,
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )
        let note = Note(
            id: UUID(),
            title: "Garden idea",
            createdAt: now.addingTimeInterval(-20),
            modifiedAt: now.addingTimeInterval(-19),
            relativePath: "Inbox/Notes/Garden idea.md",
            folderID: nil
        )
        let todo = TodoCard(
            title: "Call the dentist",
            folderID: folder.id,
            createdAt: now.addingTimeInterval(-30),
            updatedAt: now.addingTimeInterval(-29)
        )
        let image = VaultFile(
            id: UUID(),
            filename: "receipt.png",
            relativePath: "Inbox/Images/receipt.png",
            fileType: .image,
            fileSize: 42,
            createdAt: now.addingTimeInterval(-40),
            modifiedAt: now.addingTimeInterval(-39),
            folderID: nil
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark), .note(note), .todo(todo), .vaultFile(image)],
            recentItems: [.bookmark(bookmark), .note(note), .todo(todo), .vaultFile(image)],
            folders: [folder],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.recentCaptureItems.map(\.sourceTypeLabel), ["URL", "Text", "Todo", "Image"])
        XCTAssertEqual(snapshot.recentCaptureItems.map(\.itemTypeLabel), ["Bookmark", "Note", "Todo", "File"])
        XCTAssertEqual(snapshot.recentCaptureItems.map(\.destinationLabel), ["Inbox / Unfiled", "Inbox / Unfiled", "Research", "Inbox / Unfiled"])
        XCTAssertEqual(snapshot.recentCaptureItems.map(\.reviewState), ["needs_review", "ok", "pending", "ok"])
        XCTAssertEqual(snapshot.recentCaptureItems.map(\.reviewNeeded), [true, false, false, false])
        XCTAssertEqual(snapshot.recentCaptureItems[0].safeFollowUpActions, ["Review", "Check metadata", "Open item", "Defer"])
        XCTAssertEqual(snapshot.recentCaptureItems[1].safeFollowUpActions, ["Open item"])
        XCTAssertEqual(snapshot.recentCaptureItems[2].safeFollowUpActions, ["Review reminder", "Open item", "Defer"])
        XCTAssertEqual(snapshot.recentCaptureItems[3].safeFollowUpActions, ["Open item"])
        XCTAssertFalse(snapshot.recentCaptureItems[2].safeFollowUpActions.contains("Create reminder"))
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

        XCTAssertEqual(snapshot.reviewCockpitItems.map(\.title), ["Needs metadata"])
        XCTAssertEqual(snapshot.reviewCockpitItems[0].kindLabel, "Enrichment")
        XCTAssertNil(snapshot.reviewCockpitItems[0].confidenceLabel)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].targetLabel, "Inbox/Bookmarks/Needs metadata.webloc")
        XCTAssertFalse(snapshot.reviewCockpitItems[0].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canCorrect)
        XCTAssertFalse(snapshot.reviewCockpitItems[0].canDefer)
    }

    func testDashboardReviewCockpitSuppressesLegacyFolderRoutingNoise() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmarkID = UUID()
        let routingItem = CiderReviewQueueItem(
            id: "review-routing-\(UUID().uuidString)",
            kind: "low_confidence_routing",
            source: "routing_decision",
            itemID: bookmarkID,
            itemType: "bookmark",
            title: "Routine route",
            relativePath: "Inbox/Bookmarks/Routine route.webloc",
            reason: "Low confidence route.",
            suggestedAction: "Approve or correct route",
            reviewState: "needs_review",
            confidence: 0.62,
            routingDecisionID: UUID(),
            target: nil,
            createdAt: now,
            safeActions: ["approve", "correct", "defer"]
        )
        let inboxItem = CiderReviewQueueItem(
            id: "review-inbox-\(UUID().uuidString)",
            kind: "inbox_backlog",
            source: "inbox",
            itemID: UUID(),
            itemType: "note",
            title: "Routine inbox note",
            relativePath: "Inbox/Notes/Routine inbox note.md",
            reason: "Still in Inbox.",
            suggestedAction: "Route to folder",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["correct", "defer"]
        )
        let enrichmentItem = CiderReviewQueueItem(
            id: "review-enrichment-\(UUID().uuidString)",
            kind: "enrichment_failed",
            source: "enrichment",
            itemID: UUID(),
            itemType: "bookmark",
            title: "Needs metadata",
            relativePath: "Inbox/Bookmarks/Needs metadata.webloc",
            reason: "Metadata fetch failed.",
            suggestedAction: "Enrich before routing",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["enrich", "correct", "defer"]
        )
        let duplicateItem = CiderReviewQueueItem(
            id: "review-duplicate-\(UUID().uuidString)",
            kind: "duplicate_candidate",
            source: "duplicate",
            itemID: UUID(),
            itemType: "bookmark",
            title: "Possible duplicate",
            relativePath: "Inbox/Bookmarks/Possible duplicate.webloc",
            reason: "Possible duplicate URL.",
            suggestedAction: "Review duplicate",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["correct", "defer"]
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            reviewQueueItems: [routingItem, inboxItem, enrichmentItem, duplicateItem],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitItems.map(\.title), ["Needs metadata", "Possible duplicate"])
        XCTAssertEqual(
            snapshot.reviewCockpitSummary.badges,
            [
                HomeReviewCockpitBadge(id: "kind-duplicate_candidate", label: "Duplicate", value: 1),
                HomeReviewCockpitBadge(id: "kind-enrichment_failed", label: "Enrichment", value: 1),
            ]
        )
        XCTAssertEqual(snapshot.reviewCockpitSummary.totalCount, 2)
    }

    func testReviewCockpitLabelsMemoryCandidatesWithSourceEvidence() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let noteID = UUID()
        let note = Note(
            id: noteID,
            title: "Daily context",
            createdAt: now,
            modifiedAt: now,
            relativePath: "Daily/2026-06-10.md"
        )
        let reviewItem = CiderReviewQueueItem(
            id: "review-memory-candidate-\(UUID().uuidString)",
            kind: "memory_candidate",
            source: "memory_candidate",
            itemID: noteID,
            itemType: "note",
            title: "Jami likes pineapple coconut drinks.",
            relativePath: "Daily/2026-06-10.md",
            reason: "Review source-backed relationship context memory candidate before promotion.",
            suggestedAction: "Review memory candidate",
            reviewState: "needs_review",
            confidence: 0.83,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["inspect_source", "manual_review"],
            candidateID: "candidate-123",
            candidateRef: "memory_candidate:candidate-123",
            sourceQuote: "Corrected source says Jami likes pineapple coconut drinks.",
            memoryKind: "relationship_context",
            linkedOwnerRefs: ["contact:jami"]
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.note(note)],
            recentItems: [],
            folders: [],
            reviewQueueItems: [reviewItem],
            surfacingDays: 7,
            now: now
        )

        let cockpitItem = try! XCTUnwrap(snapshot.reviewCockpitItems.first)
        XCTAssertEqual(cockpitItem.kindLabel, "Memory Candidate")
        XCTAssertEqual(cockpitItem.sourceLabel, "Memory Candidate")
        XCTAssertEqual(cockpitItem.targetLabel, "Relationship Context • contact:jami")
        XCTAssertEqual(cockpitItem.candidateRef, "memory_candidate:candidate-123")
        XCTAssertEqual(cockpitItem.sourceQuote, "Corrected source says Jami likes pineapple coconut drinks.")
        XCTAssertEqual(cockpitItem.memoryKind, "relationship_context")
        XCTAssertEqual(cockpitItem.linkedOwnerRefs, ["contact:jami"])
        XCTAssertEqual(cockpitItem.confidenceLabel, "83% confidence")
        XCTAssertEqual(cockpitItem.reviewActions, [.openSource, .accept, .reject, .deferReview])
        XCTAssertTrue(cockpitItem.canApprove)
        XCTAssertTrue(cockpitItem.canCorrect)
        XCTAssertTrue(cockpitItem.canDefer)
    }

    func testReviewCockpitKeepsAmbiguousGraphCandidateAcceptUnavailable() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let noteID = UUID()
        let note = Note(
            id: noteID,
            title: "Movie journal",
            createdAt: now,
            modifiedAt: now,
            relativePath: "Daily/2026-06-10.md"
        )
        let reviewItem = CiderReviewQueueItem(
            id: "review-graph-candidate-\(UUID().uuidString)",
            kind: "graph_candidate",
            source: "graph_candidate",
            itemID: noteID,
            itemType: "note",
            title: "The Way Way Back",
            relativePath: "Daily/2026-06-10.md",
            reason: "Review extracted movie candidate from source quote; possible relation: watched.",
            suggestedAction: "Review graph candidate",
            reviewState: "suggested",
            confidence: 0.78,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["inspect_source", "link_existing", "create_object", "correct", "reject", "delegate_enrichment"],
            candidateID: "candidate-456",
            candidateRef: "graph_candidate:candidate-456",
            sourceQuote: "Watched The Way Way Back tonight.",
            possibleTypes: ["movie", "media"],
            possibleRelations: ["watched"]
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.note(note)],
            recentItems: [],
            folders: [],
            reviewQueueItems: [reviewItem],
            surfacingDays: 7,
            now: now
        )

        let cockpitItem = try! XCTUnwrap(snapshot.reviewCockpitItems.first)
        XCTAssertEqual(cockpitItem.kindLabel, "Graph Candidate")
        XCTAssertEqual(cockpitItem.candidateID, "candidate-456")
        XCTAssertEqual(cockpitItem.candidateRef, "graph_candidate:candidate-456")
        XCTAssertEqual(cockpitItem.sourceQuote, "Watched The Way Way Back tonight.")
        XCTAssertEqual(cockpitItem.targetLabel, "movie, media")
        XCTAssertEqual(cockpitItem.reviewActions, [.openSource, .reject])
        XCTAssertFalse(cockpitItem.canApprove)
        XCTAssertTrue(cockpitItem.canCorrect)
        XCTAssertFalse(cockpitItem.canDefer)
    }

    func testReviewCockpitToleratesDuplicateLibraryItemUUIDs() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmarkID = UUID()
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Duplicate-safe capture",
            urlString: "https://example.com/duplicate-safe",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let duplicateBookmark = Bookmark(
            id: bookmarkID,
            title: "Duplicate-safe capture copy",
            urlString: "https://example.com/duplicate-safe",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let reviewItem = CiderReviewQueueItem(
            id: "review-duplicate-\(UUID().uuidString)",
            kind: "duplicate_candidate",
            source: "duplicate",
            itemID: bookmarkID,
            itemType: "bookmark",
            title: "Duplicate-safe capture",
            relativePath: "Inbox/Bookmarks/Duplicate-safe capture.webloc",
            reason: "Possible duplicate bookmark.",
            suggestedAction: "Review duplicate",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["correct", "defer"]
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark), .bookmark(duplicateBookmark)],
            recentItems: [],
            folders: [],
            reviewQueueItems: [reviewItem],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitItems.count, 1)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].item?.id, "bookmark-\(bookmarkID.uuidString)")
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canCorrect)
    }

    func testReviewCockpitSummaryBuildsBadgesFromQueueSummary() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmarkID = UUID()
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            reviewQueueSummary: CiderReviewQueueSummaryResult(
                command: "review.summary",
                generatedAt: now,
                totalCount: 9,
                countsByKind: [
                    "enrichment_failed": 4,
                    "low_confidence_routing": 3,
                    "inbox_backlog": 2,
                ],
                countsByItemType: ["bookmark": 9],
                countsByReviewState: ["needs_review": 9],
                countsBySafeAction: [
                    "approve": 3,
                    "correct": 7,
                    "defer": 5,
                    "enrich": 4,
                ],
                groups: [
                    CiderReviewQueueGroup(
                        id: "enrichment:needs_review:enrich:bookmark",
                        kind: "enrichment",
                        reviewState: "needs_review",
                        requiredSafeAction: "enrich",
                        itemType: "bookmark",
                        count: 4,
                        sampleItems: [
                            CiderReviewQueueItem(
                                id: "review-enrichment-\(bookmarkID.uuidString)",
                                kind: "enrichment",
                                source: "bookmark",
                                itemID: bookmarkID,
                                itemType: "bookmark",
                                title: "Needs Metadata",
                                relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
                                reason: "Bookmark enrichment failed.",
                                suggestedAction: "Enrichment failed",
                                reviewState: "needs_review",
                                confidence: nil,
                                routingDecisionID: nil,
                                target: nil,
                                createdAt: now,
                                safeActions: ["enrich", "correct", "defer"]
                            ),
                        ]
                    ),
                ],
                batchEnrichmentPreview: CiderReviewQueueBatchEnrichmentPreview(
                    action: "review.enrich",
                    isMutating: false,
                    candidateCount: 4,
                    candidateSampleLimit: 3,
                    candidateSamples: [
                        CiderReviewQueueItem(
                            id: "review-enrichment-\(bookmarkID.uuidString)",
                            kind: "enrichment",
                            source: "bookmark",
                            itemID: bookmarkID,
                            itemType: "bookmark",
                            title: "Needs Metadata",
                            relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
                            reason: "Bookmark enrichment failed.",
                            suggestedAction: "Enrichment failed",
                            reviewState: "needs_review",
                            confidence: nil,
                            routingDecisionID: nil,
                            target: nil,
                            createdAt: now,
                            safeActions: ["enrich", "correct", "defer"]
                        ),
                    ],
                    excludedCount: 5,
                    exclusionsByReason: ["routing_requires_explicit_approval": 3, "manual_routing_required": 2]
                )
            ),
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitSummary.totalCount, 4)
        XCTAssertEqual(
            snapshot.reviewCockpitSummary.badges,
            [
                HomeReviewCockpitBadge(id: "kind-enrichment_failed", label: "Enrichment", value: 4),
            ]
        )
        XCTAssertEqual(snapshot.reviewCockpitSummary.safeActionCounts["enrich"], 4)
        XCTAssertEqual(
            snapshot.reviewCockpitSummary.groups,
            [
                HomeReviewCockpitGroup(
                    id: "enrichment:needs_review:enrich:bookmark",
                    label: "Enrichment",
                    reviewState: "needs_review",
                    requiredSafeAction: "enrich",
                    itemType: "bookmark",
                    count: 4,
                    sampleTitles: ["Needs Metadata"]
                ),
            ]
        )
        XCTAssertEqual(
            snapshot.reviewCockpitSummary.batchEnrichmentPreview,
            HomeReviewCockpitBatchEnrichmentPreview(
                action: "review.enrich",
                isMutating: false,
                candidateCount: 4,
                candidateSampleLimit: 3,
                candidateSampleTitles: ["Needs Metadata"],
                excludedCount: 5,
                exclusionsByReason: ["routing_requires_explicit_approval": 3, "manual_routing_required": 2]
            )
        )
        XCTAssertEqual(snapshot.reviewCockpitSummary.generatedAt, now)
    }

    func testReviewCockpitSummaryBuildsVisibleLanesAndExplicitBatchControl() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let enrichmentID = UUID()
        let enrichmentItem = CiderReviewQueueItem(
            id: "review-enrichment-\(enrichmentID.uuidString)",
            kind: "enrichment",
            source: "bookmark",
            itemID: enrichmentID,
            itemType: "bookmark",
            title: "Needs Metadata",
            relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
            reason: "Bookmark enrichment failed.",
            suggestedAction: "Enrichment failed",
            reviewState: "needs_review",
            confidence: nil,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["enrich", "correct", "defer"]
        )
        let summary = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            reviewQueueSummary: CiderReviewQueueSummaryResult(
                command: "review.summary",
                generatedAt: now,
                totalCount: 236,
                countsByKind: ["enrichment": 234, "low_confidence_routing": 2],
                countsByItemType: ["bookmark": 236],
                countsByReviewState: ["needs_review": 236],
                countsBySafeAction: ["enrich": 234, "approve": 2, "correct": 2, "defer": 2],
                groups: [
                    CiderReviewQueueGroup(
                        id: "enrichment:needs_review:enrich:bookmark",
                        kind: "enrichment",
                        reviewState: "needs_review",
                        requiredSafeAction: "enrich",
                        itemType: "bookmark",
                        count: 234,
                        sampleItems: [enrichmentItem]
                    ),
                ],
                batchEnrichmentPreview: CiderReviewQueueBatchEnrichmentPreview(
                    action: "review.enrich",
                    isMutating: false,
                    candidateCount: 234,
                    candidateSampleLimit: 10,
                    candidateSamples: [enrichmentItem],
                    excludedCount: 2,
                    exclusionsByReason: ["routing_requires_explicit_approval": 2]
                )
            ),
            surfacingDays: 7,
            now: now
        ).reviewCockpitSummary

        XCTAssertEqual(
            summary.visibleLanes,
            [
                HomeReviewCockpitLane(
                    id: "enrichment:needs_review:enrich:bookmark",
                    title: "Enrichment",
                    count: 234,
                    actionLabel: "Enrich",
                    sampleTitles: ["Needs Metadata"],
                    keepsRoutingSeparate: true
                ),
            ]
        )
        XCTAssertEqual(summary.batchEnrichmentPreview.primaryActionTitle, "Enrich 234 bookmarks")
        XCTAssertEqual(summary.batchEnrichmentPreview.previewDetailLine, "Preview sample: Needs Metadata")
        XCTAssertEqual(summary.batchEnrichmentPreview.exclusionDetailLine, "2 routing items require explicit approval")
        XCTAssertTrue(summary.batchEnrichmentPreview.canRunExplicitBatchAction)
        XCTAssertFalse(summary.batchEnrichmentPreview.isMutating)
    }

    func testBatchEnrichmentPreviewBuildsConfirmationAndResultPresentation() {
        let preview = HomeReviewCockpitBatchEnrichmentPreview(
            action: "review.enrich",
            isMutating: false,
            candidateCount: 234,
            candidateSampleLimit: 10,
            candidateSampleTitles: ["Needs Metadata", "Another Bookmark"],
            excludedCount: 2,
            exclusionsByReason: ["routing_requires_explicit_approval": 2]
        )

        XCTAssertEqual(
            preview.controlPresentation(isConfirming: false, scheduledCount: nil),
            HomeReviewCockpitBatchEnrichmentControlPresentation(
                accessibilityLabel: "Review 234 bookmark enrichments",
                help: "Review 234 bookmark enrichments before scheduling",
                statusLine: "Preview sample: Needs Metadata, Another Bookmark",
                systemImage: "sparkles",
                isEnabled: true
            )
        )
        XCTAssertEqual(
            preview.controlPresentation(isConfirming: true, scheduledCount: nil),
            HomeReviewCockpitBatchEnrichmentControlPresentation(
                accessibilityLabel: "Confirm enrichment for 234 bookmarks",
                help: "Confirm enrichment for 234 bookmarks. Routing items are excluded.",
                statusLine: "2 routing items require explicit approval",
                systemImage: "checkmark.circle",
                isEnabled: true
            )
        )
        XCTAssertEqual(
            preview.controlPresentation(isConfirming: false, scheduledCount: 234),
            HomeReviewCockpitBatchEnrichmentControlPresentation(
                accessibilityLabel: "Scheduled enrichment for 234 bookmarks",
                help: "Scheduled enrichment for 234 bookmarks",
                statusLine: "Scheduled enrichment for 234 bookmarks. Routing items were not changed.",
                systemImage: "checkmark.circle.fill",
                isEnabled: false
            )
        )
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
        XCTAssertEqual(snapshot.reviewCockpitItems[0].dateSuggestionApproval?.suggestionKey, deadlineSuggestion.suggestionKey)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].dateSuggestionApproval?.destination, .todo)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[0].canCorrect)
        XCTAssertFalse(snapshot.reviewCockpitItems[0].safeActions.contains("correct"))
        XCTAssertTrue(snapshot.reviewCockpitItems[0].safeActions.contains("open"))
        XCTAssertFalse(snapshot.reviewCockpitItems[0].canDefer)

        XCTAssertEqual(snapshot.reviewCockpitItems[1].suggestedAction, "Approve Date Card")
        XCTAssertEqual(snapshot.reviewCockpitItems[1].targetLabel, "Date card")
        XCTAssertEqual(snapshot.reviewCockpitItems[1].dateSuggestionApproval?.suggestionIndex, 0)
        XCTAssertEqual(snapshot.reviewCockpitItems[1].dateSuggestionApproval?.suggestionKey, releaseSuggestion.suggestionKey)
        XCTAssertEqual(snapshot.reviewCockpitItems[1].dateSuggestionApproval?.destination, .dateCard)
        XCTAssertTrue(snapshot.reviewCockpitItems[1].canApprove)
        XCTAssertTrue(snapshot.reviewCockpitItems[1].canCorrect)
        XCTAssertFalse(snapshot.reviewCockpitItems[1].safeActions.contains("correct"))
        XCTAssertTrue(snapshot.reviewCockpitItems[1].safeActions.contains("open"))
        XCTAssertFalse(snapshot.reviewCockpitItems[1].canDefer)
    }

    func testReviewCockpitCollapsesMultipleDateSuggestionsFromSameBookmark() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmark = Bookmark(
            id: UUID(),
            title: "Remindio giveaway",
            urlString: "https://example.com/remindio",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let lowConfidenceSuggestion = CiderBookmarkDateSuggestion(
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            kind: "event_date",
            confidence: 0.58,
            date: now.addingTimeInterval(60 * 60 * 24 * 4),
            sourceField: "ocrText",
            sourceSnippet: "Meeting tomorrow",
            nextSafeAction: "review_date_suggestion"
        )
        let preferredSuggestion = CiderBookmarkDateSuggestion(
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            kind: "deadline",
            confidence: 0.91,
            date: now.addingTimeInterval(60 * 60 * 24 * 8),
            sourceField: "ocrText",
            sourceSnippet: "Save by June 12, 2026",
            nextSafeAction: "review_date_suggestion"
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark)],
            recentItems: [],
            folders: [],
            bookmarkDateSuggestionResults: [
                CiderBookmarkDateSuggestionResult(
                    command: "bookmark.date-suggestions",
                    bookmarkID: bookmark.id,
                    bookmarkTitle: bookmark.title,
                    sourceURL: bookmark.urlString,
                    suggestions: [lowConfidenceSuggestion, preferredSuggestion]
                )
            ],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitItems.map(\.title), ["Remindio giveaway"])
        XCTAssertEqual(snapshot.reviewCockpitItems[0].dateSuggestionApproval?.suggestionIndex, 1)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].dateSuggestionApproval?.suggestionKey, preferredSuggestion.suggestionKey)
        XCTAssertEqual(snapshot.reviewCockpitItems[0].confidenceLabel, "91% confidence")
    }

    func testReviewCockpitBuildsFallbackNoteSourceForCandidateRows() throws {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let sourceNoteID = UUID()
        let reviewItem = CiderReviewQueueItem(
            id: "graph-candidate-cactus",
            kind: "graph_candidate",
            source: "second_brain",
            itemID: sourceNoteID,
            itemType: "note",
            title: "Cactus",
            relativePath: "Daily/2026-06-11.md",
            reason: "Source-backed graph candidate",
            suggestedAction: "Inspect Source",
            reviewState: "needs_review",
            confidence: 0.76,
            routingDecisionID: nil,
            target: nil,
            createdAt: now,
            safeActions: ["inspect_source", "reject"],
            candidateID: "graph-candidate-cactus",
            candidateRef: "graph_candidate:graph-candidate-cactus",
            sourceQuote: "Journal source mentions Cactus."
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            reviewQueueItems: [reviewItem],
            surfacingDays: 7,
            now: now
        )
        let cockpitItem = try XCTUnwrap(snapshot.reviewCockpitItems.first)
        let sourceItem = try XCTUnwrap(cockpitItem.item)

        XCTAssertEqual(sourceItem.id, "note-\(sourceNoteID.uuidString)")
        XCTAssertTrue(cockpitItem.reviewActions.contains(.openSource))
        XCTAssertTrue(cockpitItem.reviewActions.contains(.reject))
        XCTAssertEqual(cockpitItem.sourceQuote, "Journal source mentions Cactus.")
        guard case .note(let note) = sourceItem else {
            XCTFail("Expected fallback note source item")
            return
        }
        XCTAssertEqual(note.relativePath, "Daily/2026-06-11.md")
        XCTAssertEqual(note.title, "2026-06-11")
    }

    func testReviewCockpitReservesSlotForDateSuggestionWhenQueueIsFull() {
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let reviewBookmarks = (0..<6).map { index in
            Bookmark(
                id: UUID(),
                title: "Metadata review \(index)",
                urlString: "https://example.com/metadata-\(index)",
                createdAt: now.addingTimeInterval(TimeInterval(-index * 60)),
                updatedAt: now,
                folderID: nil
            )
        }
        let reviewItems = reviewBookmarks.enumerated().map { index, bookmark in
            CiderReviewQueueItem(
                id: "review-enrichment-\(index)",
                kind: "enrichment_failed",
                source: "enrichment",
                itemID: bookmark.id,
                itemType: "bookmark",
                title: bookmark.title,
                relativePath: "Inbox/Bookmarks/\(bookmark.title).webloc",
                reason: "Metadata fetch failed.",
                suggestedAction: "Enrich before routing",
                reviewState: "needs_review",
                confidence: nil,
                routingDecisionID: nil,
                target: nil,
                createdAt: now.addingTimeInterval(TimeInterval(-index)),
                safeActions: ["enrich", "correct", "defer"]
            )
        }
        let deadlineBookmark = Bookmark(
            id: UUID(),
            title: "Grant application",
            urlString: "https://example.com/grant",
            createdAt: now,
            updatedAt: now,
            folderID: nil
        )
        let suggestion = CiderBookmarkDateSuggestion(
            bookmarkID: deadlineBookmark.id,
            bookmarkTitle: deadlineBookmark.title,
            sourceURL: deadlineBookmark.urlString,
            kind: "deadline",
            confidence: 0.84,
            date: now.addingTimeInterval(60 * 60 * 24 * 10),
            sourceField: "title",
            sourceSnippet: "Apply by May 30, 2026",
            nextSafeAction: "review_date_suggestion"
        )

        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: reviewBookmarks.map(LibraryItemV2.bookmark) + [.bookmark(deadlineBookmark)],
            recentItems: [],
            folders: [],
            reviewQueueItems: reviewItems,
            bookmarkDateSuggestionResults: [
                CiderBookmarkDateSuggestionResult(
                    command: "bookmark.date-suggestions",
                    bookmarkID: deadlineBookmark.id,
                    bookmarkTitle: deadlineBookmark.title,
                    sourceURL: deadlineBookmark.urlString,
                    suggestions: [suggestion]
                )
            ],
            surfacingDays: 7,
            now: now
        )

        XCTAssertEqual(snapshot.reviewCockpitItems.count, 6)
        XCTAssertTrue(snapshot.reviewCockpitItems.contains { $0.kindLabel == "Date Suggestion" })
        XCTAssertEqual(snapshot.reviewCockpitItems.last?.title, "Grant application")
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

    func testReviewCandidateDetailPresentationLabelsCorrectionPaths() {
        let itemID = UUID()
        let memoryCandidate = HomeReviewCockpitItem(
            id: "memory-candidate",
            sourceReviewID: "review-memory",
            itemID: itemID,
            itemType: "note",
            item: nil,
            title: "Jami preference",
            kindLabel: "Memory Candidate",
            reason: "Candidate fact",
            suggestedAction: "Review",
            reviewStateLabel: "Needs review",
            confidenceLabel: "83% confidence",
            targetLabel: "Relationship Context • contact:jami",
            sourceLabel: "Memory Candidate",
            canApprove: true,
            canCorrect: true,
            canDefer: true,
            safeActions: ["approve", "correct", "defer"],
            dateSuggestionApproval: nil,
            reviewActions: [.openSource, .accept, .reject, .deferReview],
            candidateID: "candidate-123",
            candidateRef: "memory_candidate:candidate-123",
            sourceQuote: "Jami likes this.",
            memoryKind: "relationship_context",
            linkedOwnerRefs: ["contact:jami"]
        )
        let graphCandidate = HomeReviewCockpitItem(
            id: "graph-candidate",
            sourceReviewID: "review-graph",
            itemID: itemID,
            itemType: "note",
            item: nil,
            title: "Movie link",
            kindLabel: "Graph Candidate",
            reason: "Ambiguous relation",
            suggestedAction: "Inspect",
            reviewStateLabel: "Needs review",
            confidenceLabel: nil,
            targetLabel: "movie, media",
            sourceLabel: "Graph Candidate",
            canApprove: false,
            canCorrect: true,
            canDefer: false,
            safeActions: ["correct"],
            dateSuggestionApproval: nil,
            reviewActions: [.openSource, .reject],
            candidateID: "candidate-456",
            candidateRef: "graph_candidate:candidate-456",
            sourceQuote: "Watched The Way Way Back tonight.",
            linkedOwnerRefs: []
        )

        XCTAssertEqual(memoryCandidate.detailExtractedValueLabel, "Relationship Context • contact:jami")
        XCTAssertEqual(memoryCandidate.detailOwnerRefsLabel, "contact:jami")
        XCTAssertEqual(memoryCandidate.detailCorrectionActionLabel, "Edit value")
        XCTAssertEqual(memoryCandidate.detailCorrectionHelp, "Edit value from the source evidence")

        XCTAssertEqual(graphCandidate.detailExtractedValueLabel, "movie, media")
        XCTAssertNil(graphCandidate.detailOwnerRefsLabel)
        XCTAssertEqual(graphCandidate.detailCorrectionActionLabel, "Delegate / inspect")
        XCTAssertEqual(graphCandidate.detailCorrectionHelp, "Delegate / inspect before accepting this graph relation")
    }

}
