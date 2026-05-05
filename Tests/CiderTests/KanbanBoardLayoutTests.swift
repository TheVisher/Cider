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

    @Test("QA columns render as a lower project row")
    func qaColumnsRenderAsLowerProjectRow() {
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

        #expect(lanes.map(\.role) == [.workflow, .qa])
        #expect(lanes.first(where: { $0.role == .workflow })?.columns.map(\.id) == ["backlog", "in_progress", "done"])
        #expect(lanes.first(where: { $0.role == .qa })?.columns.map(\.id) == ["investigating", "qa", "ready_to_test", "verified"])
    }

    @Test("archive columns are kept out of active lanes and aligned to source lanes")
    func archiveColumnsAlignToSourceLanes() {
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

        #expect(lanes.first(where: { $0.role == .workflow })?.columns.map(\.id) == ["backlog", "testing", "done"])
        #expect(lanes.first(where: { $0.role == .qa })?.columns.map(\.id) == ["needs_fix", "verified"])
        #expect(KanbanBoardLayout.archiveColumns(for: .workflow, in: board).map(\.id) == ["workflow_archive"])
        #expect(KanbanBoardLayout.archiveColumns(for: .qa, in: board).map(\.id) == ["qa_archive"])
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
}
