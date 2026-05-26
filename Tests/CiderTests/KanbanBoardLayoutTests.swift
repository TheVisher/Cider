import Foundation
import Testing
@testable import Cider

struct KanbanBoardLayoutTests {
    @Test("Cider project boards use swimlane layout even before many columns exist")
    func ciderProjectBoardsUseProjectLayout() {
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
            ]
        )

        #expect(KanbanBoardLayout.usesProjectLayout(for: board))
    }

    @Test("active project columns stay together in one workflow row")
    func activeColumnsStayTogetherInWorkflowRow() {
        let board = KanbanBoard(
            name: "Cider",
            columns: [
                KanbanColumn(id: "ideas", name: "Ideas"),
                KanbanColumn(id: "next_up", name: "Next Up"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "testing", name: "Testing / QA"),
                KanbanColumn(id: "completed", name: "Completed"),
            ]
        )

        let lanes = KanbanBoardLayout.lanes(for: board)

        #expect(lanes.map(\.role) == [.workflow])
        #expect(lanes.first?.columns.map(\.id) == ["ideas", "next_up", "in_progress", "testing", "completed"])
    }

    @Test("QA columns stay inline on the project board row")
    func qaColumnsStayInlineOnProjectBoardRow() {
        let board = KanbanBoard(
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
                KanbanColumn(id: "investigating", name: "Investigating"),
                KanbanColumn(id: "qa", name: "QA"),
                KanbanColumn(id: "ready_to_test", name: "Ready to Test"),
                KanbanColumn(id: "verified", name: "Verified"),
            ]
        )

        let lanes = KanbanBoardLayout.lanes(for: board)

        #expect(lanes.map(\.role) == [.workflow])
        #expect(lanes.first?.columns.map(\.id) == [
            "backlog",
            "in_progress",
            "done",
            "investigating",
            "qa",
            "ready_to_test",
            "verified",
        ])
    }

    @Test("archive columns are kept out of active project rows and revealed together")
    func archiveColumnsRevealTogether() {
        let board = KanbanBoard(
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "testing", name: "Testing"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
                KanbanColumn(id: "workflow_archive", name: "Workflow Archive", isDoneColumn: true),
                KanbanColumn(id: "needs_fix", name: "Needs Fix"),
                KanbanColumn(id: "verified", name: "Verified"),
                KanbanColumn(id: "qa_archive", name: "QA Archive", isDoneColumn: true),
            ]
        )

        let lanes = KanbanBoardLayout.lanes(for: board)

        #expect(lanes.map(\.role) == [.workflow])
        #expect(lanes.first?.columns.map(\.id) == ["backlog", "testing", "done", "needs_fix", "verified"])
        #expect(KanbanBoardLayout.archiveColumns(for: .workflow, in: board).map(\.id) == ["workflow_archive", "qa_archive"])
        #expect(KanbanBoardLayout.archiveColumns(for: .qa, in: board).isEmpty)
    }

    @Test("hidden columns stay out of active project rows and appear in the hidden rail")
    func hiddenColumnsStayOutOfActiveProjectRows() {
        let board = KanbanBoard(
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
                KanbanColumn(id: "canceled", name: "Canceled", isHiddenColumn: true),
                KanbanColumn(id: "duplicate", name: "Duplicate", isHiddenColumn: true),
            ]
        )

        let lanes = KanbanBoardLayout.lanes(for: board)

        #expect(lanes.first?.columns.map(\.id) == ["backlog", "in_progress", "done"])
        #expect(KanbanBoardLayout.hiddenColumns(in: board).map(\.id) == ["canceled", "duplicate"])
    }

    @Test("hidden columns rail counts as one final horizontal scroll item")
    func hiddenColumnsRailCountsAsFinalScrollItem() {
        #expect(KanbanBoardLayout.projectScrollableItemCount(activeColumnCount: 5, hiddenColumnCount: 0) == 5)
        #expect(KanbanBoardLayout.projectScrollableItemCount(activeColumnCount: 5, hiddenColumnCount: 3) == 6)
    }

    @Test("legacy archive columns are treated as hidden columns")
    func archiveColumnsAreHiddenCompatible() {
        let board = KanbanBoard(
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
                KanbanColumn(id: "workflow_archive", name: "Workflow Archive", isDoneColumn: true),
            ]
        )

        #expect(KanbanBoardLayout.lanes(for: board).first?.columns.map(\.id) == ["backlog", "done"])
        #expect(KanbanBoardLayout.hiddenColumns(in: board).map(\.id) == ["workflow_archive"])
    }

    @Test("small generic boards keep the existing flat column layout")
    func smallGenericBoardsUseFlatLayout() {
        let board = KanbanBoard(
            name: "Personal Errands",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog"),
                KanbanColumn(id: "in_progress", name: "In Progress"),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true),
            ]
        )

        #expect(!KanbanBoardLayout.usesProjectLayout(for: board))
    }

    @Test("archive reveal only pushes active columns when the combined lane overflows")
    func archiveRevealPushesOnlyWhenNeeded() {
        let columnWidth: CGFloat = 280
        let spacing: CGFloat = 12
        let activeWidth = KanbanBoardLayout.columnGroupWidth(
            columnCount: 4,
            columnWidth: columnWidth,
            spacing: spacing
        )
        let archiveWidth = KanbanBoardLayout.archiveRevealWidth(
            columnCount: 1,
            columnWidth: columnWidth,
            spacing: spacing
        )
        let combinedWidth = activeWidth + spacing + archiveWidth

        #expect(!KanbanBoardLayout.shouldPushArchive(
            activeColumnCount: 4,
            archiveColumnCount: 1,
            availableWidth: combinedWidth + 120,
            columnWidth: columnWidth,
            spacing: spacing,
            archiveExpanded: true
        ))

        #expect(KanbanBoardLayout.shouldPushArchive(
            activeColumnCount: 4,
            archiveColumnCount: 1,
            availableWidth: combinedWidth - 1,
            columnWidth: columnWidth,
            spacing: spacing,
            archiveExpanded: true
        ))

        #expect(!KanbanBoardLayout.shouldPushArchive(
            activeColumnCount: 4,
            archiveColumnCount: 1,
            availableWidth: combinedWidth - 1,
            columnWidth: columnWidth,
            spacing: spacing,
            archiveExpanded: false
        ))
    }

    @Test("project board design tokens favor readable card scanning")
    func projectBoardDesignTokensFavorReadableCardScanning() {
        #expect(KanbanDesign.projectColumnWidth >= 368)
        #expect(KanbanDesign.projectMinimumColumnHeight >= 360)
        #expect(KanbanDesign.columnWidth >= 320)
    }

    @Test("project column height fits inside the board viewport")
    func projectColumnHeightFitsInsideBoardViewport() {
        let availableHeight: CGFloat = 760
        let columnHeight = KanbanBoardLayout.projectColumnHeight(
            availableBoardHeight: availableHeight,
            showsScrollControls: true
        )

        #expect(columnHeight < availableHeight)
        #expect(columnHeight >= KanbanDesign.projectMinimumColumnHeight)
    }

    @Test("project column height shrinks for short board viewports")
    func projectColumnHeightShrinksForShortBoardViewports() {
        let availableHeight: CGFloat = 280
        let columnHeight = KanbanBoardLayout.projectColumnHeight(
            availableBoardHeight: availableHeight,
            showsScrollControls: true
        )

        #expect(columnHeight < availableHeight)
        #expect(columnHeight < KanbanDesign.projectMinimumColumnHeight)
    }

    @Test("card preview design tokens separate header body and footer")
    func cardPreviewDesignTokensSeparateHeaderBodyAndFooter() {
        #expect(KanbanDesign.cardPreviewSectionSpacing >= Spacing.sm)
        #expect(KanbanDesign.cardPreviewFooterTopSpacing >= Spacing.sm)
        #expect(KanbanDesign.cardPreviewContextFooterSpacing >= Spacing.sm)
    }

    @Test("blue and purple Kanban accent tokens are visually separated")
    func blueAndPurpleKanbanAccentTokensAreVisuallySeparated() {
        #expect(KanbanDesign.kanbanBlueAccentHueDegrees < KanbanDesign.kanbanPurpleAccentHueDegrees)
        #expect(KanbanDesign.kanbanPurpleAccentHueDegrees - KanbanDesign.kanbanBlueAccentHueDegrees >= 45)
    }

    @Test("Kanban display keys use board prefix and preserve internal ids")
    func kanbanDisplayKeysUseBoardPrefixAndPreserveInternalIDs() {
        let first = KanbanCard(id: "abc123", title: "First card", displayKey: "CID-7")
        let second = KanbanCard(id: "def456", title: "Second card")
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [first, second]),
            ]
        )

        #expect(board.displayKeyPrefix == "CID")
        #expect(board.displayKey(for: first) == "CID-7")
        #expect(board.displayKey(for: second) == "CID-2")
        #expect(board.card(matching: "CID-7")?.id == "abc123")
        #expect(board.card(matching: "def456")?.title == "Second card")
    }

    @Test("Kanban next display key skips existing stored and fallback keys")
    func kanbanNextDisplayKeySkipsExistingStoredAndFallbackKeys() {
        let board = KanbanBoard(
            name: "Cider Web",
            columns: [
                KanbanColumn(id: "todo", name: "Todo", cards: [
                    KanbanCard(id: "a", title: "Stored", displayKey: "CW-10"),
                    KanbanCard(id: "b", title: "Fallback"),
                ]),
            ]
        )

        #expect(board.displayKeyPrefix == "CW")
        #expect(board.nextDisplayKey() == "CW-11")
    }

    @Test("Kanban missing display keys are assigned once before persistence")
    func kanbanMissingDisplayKeysAreAssignedOnceBeforePersistence() {
        var board = KanbanBoard(
            name: "Cider",
            columns: [
                KanbanColumn(id: "todo", name: "Todo", cards: [
                    KanbanCard(id: "a", title: "Existing", displayKey: "CID-3"),
                    KanbanCard(id: "b", title: "Missing"),
                    KanbanCard(id: "c", title: "Also missing"),
                ]),
            ]
        )

        board.assignMissingDisplayKeys()

        #expect(board.card(id: "a")?.displayKey == "CID-3")
        #expect(board.card(id: "b")?.displayKey == "CID-1")
        #expect(board.card(id: "c")?.displayKey == "CID-2")
        #expect(board.nextDisplayKey() == "CID-4")
    }

    @Test("testing owner badge is derived from card tags")
    func testingOwnerBadgeIsDerivedFromCardTags() {
        let erikCard = KanbanCard(
            title: "Manual QA",
            tags: ["kanban", "needs-erik", "ui"]
        )
        let agentCard = KanbanCard(
            title: "Automated QA",
            tags: ["qa", "agent-can-verify"]
        )
        let untaggedCard = KanbanCard(
            title: "No owner yet",
            tags: ["qa"]
        )

        #expect(KanbanBoardLayout.testingOwnerBadge(for: erikCard)?.text == "Needs Erik")
        #expect(KanbanBoardLayout.testingOwnerBadge(for: agentCard)?.text == "Agent can verify")
        #expect(KanbanBoardLayout.testingOwnerBadge(for: untaggedCard) == nil)
    }
}
