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

    @Test("group render id changes when same-column child membership changes")
    func groupRenderIDChangesWhenChildMembershipChanges() {
        let parent = KanbanCard(id: "parent", title: "Parent")
        let child = KanbanCard(id: "child", title: "Child", parentCardID: "parent")

        let parentOnlyColumn = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [parent]
        )
        let groupedColumn = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [parent, child]
        )

        let parentOnlyRenderID = KanbanBoardLayout
            .cardGroups(for: parentOnlyColumn, in: KanbanBoard(name: "Hierarchy", columns: [parentOnlyColumn]))
            .first?
            .renderID
        let groupedRenderID = KanbanBoardLayout
            .cardGroups(for: groupedColumn, in: KanbanBoard(name: "Hierarchy", columns: [groupedColumn]))
            .first?
            .renderID

        #expect(parentOnlyRenderID == "parent")
        #expect(groupedRenderID == "parent|child")
        #expect(parentOnlyRenderID != groupedRenderID)
    }

    @Test("collapsed parent groups hide same-column children without changing order")
    func collapsedParentGroupsHideSameColumnChildren() {
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

        let groups = KanbanBoardLayout.cardGroups(
            for: column,
            in: board,
            collapsedParentIDs: ["parent"]
        )

        #expect(groups.map(\.parent.card.id) == ["parent", "standalone"])
        #expect(groups.first?.children.isEmpty == true)
        #expect(groups.last?.parent.card.id == "standalone")
    }

    @Test("parent child summary counts children across columns")
    func parentChildSummaryCountsChildrenAcrossColumns() {
        let board = KanbanBoard(
            name: "Hierarchy",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "parent", title: "Parent"),
                        KanbanCard(id: "child-a", title: "Child A", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "child-b", title: "Child B", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(id: "child-c", title: "Child C", parentCardID: "parent"),
                    ]
                ),
            ]
        )

        let summary = KanbanBoardLayout.childSummary(for: "parent", in: board)

        #expect(summary?.totalCount == 3)
        #expect(summary?.doneCount == 1)
        #expect(summary?.columnCounts.map(\.columnName) == ["Backlog", "Testing", "Done"])
        #expect(summary?.columnCounts.map(\.count) == [1, 1, 1])
        #expect(summary?.compactText == "3 children · 1 Backlog · 1 Testing · 1 Done · 1/3 done")
    }

    @Test("cross-column child exposes parent badge and inherited accent")
    func crossColumnChildExposesParentBadgeAndInheritedAccent() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent Plan", color: .purple),
            ]
        )
        let testing = KanbanColumn(
            id: "testing",
            name: "Testing",
            cards: [
                KanbanCard(id: "child", title: "Child Step", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog, testing])

        let badge = KanbanBoardLayout.parentBadge(
            for: testing.cards[0],
            in: testing,
            board: board
        )

        #expect(badge?.parentID == "parent")
        #expect(badge?.title == "Parent Plan")
        #expect(badge?.accentColor == .purple)
        #expect(KanbanBoardLayout.inheritedParentAccentColor(for: testing.cards[0], in: board) == .purple)
    }

    @Test("same-column child inherits parent accent without parent badge")
    func sameColumnChildInheritsParentAccentWithoutParentBadge() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent Plan", color: .green),
                KanbanCard(id: "child", title: "Child Step", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog])

        let badge = KanbanBoardLayout.parentBadge(
            for: backlog.cards[1],
            in: backlog,
            board: board
        )

        #expect(badge == nil)
        #expect(KanbanBoardLayout.inheritedParentAccentColor(for: backlog.cards[1], in: board) == .green)
    }

    @Test("parent accent falls back to stable color when parent has no explicit color")
    func parentAccentFallsBackToStableColor() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent Plan"),
            ]
        )
        let testing = KanbanColumn(
            id: "testing",
            name: "Testing",
            cards: [
                KanbanCard(id: "child", title: "Child Step", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog, testing])

        let first = KanbanBoardLayout.inheritedParentAccentColor(for: testing.cards[0], in: board)
        let second = KanbanBoardLayout.inheritedParentAccentColor(for: testing.cards[0], in: board)

        #expect(first != nil)
        #expect(first == second)
        #expect(KanbanBoardLayout.parentBadge(for: testing.cards[0], in: testing, board: board)?.accentColor == first)
    }

    @Test("nested parent uses family root accent")
    func nestedParentUsesFamilyRootAccent() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "grandparent", title: "Grandparent"),
                KanbanCard(id: "parent", title: "Parent Plan", parentCardID: "grandparent"),
                KanbanCard(id: "child", title: "Child Step", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog])

        let parentAccent = KanbanBoardLayout.cardAccentColor(for: backlog.cards[1], in: board)
        let childAccent = KanbanBoardLayout.cardAccentColor(for: backlog.cards[2], in: board)
        let ancestorAccent = KanbanBoardLayout.inheritedParentAccentColor(for: backlog.cards[1], in: board)

        #expect(parentAccent != nil)
        #expect(parentAccent == childAccent)
        #expect(parentAccent == ancestorAccent)
    }

    @Test("descendant family accent uses explicit root color")
    func descendantFamilyAccentUsesExplicitRootColor() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "grandparent", title: "Grandparent", color: .orange),
                KanbanCard(id: "parent", title: "Parent Plan", color: .purple, parentCardID: "grandparent"),
                KanbanCard(id: "child", title: "Child Step", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog])

        #expect(KanbanBoardLayout.cardAccentColor(for: backlog.cards[0], in: board) == .orange)
        #expect(KanbanBoardLayout.cardAccentColor(for: backlog.cards[1], in: board) == .orange)
        #expect(KanbanBoardLayout.cardAccentColor(for: backlog.cards[2], in: board) == .orange)
    }
}
