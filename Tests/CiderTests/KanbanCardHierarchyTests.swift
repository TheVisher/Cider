import Foundation
import Testing
@testable import Cider

struct KanbanCardHierarchyTests {
    @Test("board finds parent and child cards across columns")
    func boardFindsParentAndChildCardsAcrossColumns() {
        let board = KanbanBoard(
            name: "Hierarchy",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "parent", title: "Parent"),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "child-a", title: "Child A", parentCardID: "parent"),
                        KanbanCard(id: "child-b", title: "Child B", parentCardID: "parent"),
                    ]
                ),
            ]
        )

        #expect(board.parentCard(for: "child-a")?.id == "parent")
        #expect(board.childCards(of: "parent").map(\.id) == ["child-a", "child-b"])
    }

    @Test("board rejects parent assignments that create self links or cycles")
    func boardRejectsInvalidParentAssignments() {
        let board = KanbanBoard(
            name: "Hierarchy",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "parent", title: "Parent"),
                        KanbanCard(id: "child", title: "Child", parentCardID: "parent"),
                        KanbanCard(id: "grandchild", title: "Grandchild", parentCardID: "child"),
                    ]
                ),
            ]
        )

        #expect(!board.canAssignParent(cardID: "child", parentCardID: "child"))
        #expect(!board.canAssignParent(cardID: "parent", parentCardID: "grandchild"))
        #expect(!board.canAssignParent(cardID: "missing", parentCardID: "parent"))
        #expect(!board.canAssignParent(cardID: "child", parentCardID: "missing"))
        #expect(board.canAssignParent(cardID: "grandchild", parentCardID: "parent"))
        #expect(board.canAssignParent(cardID: "child", parentCardID: nil))
    }

    @Test("removing parent relationship from board clears only matching children")
    func clearingDeletedParentLeavesUnrelatedCardsAlone() {
        var board = KanbanBoard(
            name: "Hierarchy",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "child-a", title: "Child A", parentCardID: "parent"),
                        KanbanCard(id: "child-b", title: "Child B", parentCardID: "other-parent"),
                    ]
                ),
            ]
        )

        board.clearParentReferences(to: "parent")

        #expect(board.card(id: "child-a")?.parentCardID == nil)
        #expect(board.card(id: "child-b")?.parentCardID == "other-parent")
    }
}
