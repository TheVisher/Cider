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

    @Test("same-column children render directly under their parent")
    func sameColumnChildrenRenderUnderParent() {
        let column = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "standalone", title: "Standalone"),
                KanbanCard(id: "child-a", title: "Child A", parentCardID: "parent"),
                KanbanCard(id: "parent", title: "Parent"),
                KanbanCard(id: "child-b", title: "Child B", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [column])

        let nodes = KanbanBoardLayout.cardNodes(for: column, in: board)

        #expect(nodes.map(\.card.id) == ["standalone", "parent", "child-a", "child-b"])
        #expect(nodes.map(\.depth) == [0, 0, 1, 1])
        #expect(nodes.map(\.sameColumnParentID) == [nil, nil, "parent", "parent"])
        #expect(nodes.map(\.visualIndex) == [0, 1, 2, 3])
    }

    @Test("cross-column children stay top-level in their own column")
    func crossColumnChildrenStayTopLevel() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent"),
            ]
        )
        let testing = KanbanColumn(
            id: "testing",
            name: "Testing",
            cards: [
                KanbanCard(id: "child", title: "Child", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog, testing])

        let nodes = KanbanBoardLayout.cardNodes(for: testing, in: board)

        #expect(nodes.map(\.card.id) == ["child"])
        #expect(nodes.map(\.depth) == [0])
        #expect(nodes.map(\.sameColumnParentID) == [nil])
    }

    @Test("same-column children are available as a parent group")
    func sameColumnChildrenAreAvailableAsParentGroup() {
        let column = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent"),
                KanbanCard(id: "child-a", title: "Child A", parentCardID: "parent"),
                KanbanCard(id: "child-b", title: "Child B", parentCardID: "parent"),
                KanbanCard(id: "standalone", title: "Standalone"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [column])

        let groups = KanbanBoardLayout.cardGroups(for: column, in: board)

        #expect(groups.map(\.parent.card.id) == ["parent", "standalone"])
        #expect(groups.first?.children.map(\.card.id) == ["child-a", "child-b"])
        #expect(groups.first?.children.map(\.visualIndex) == [1, 2])
        #expect(groups.last?.children.isEmpty == true)
    }
}
