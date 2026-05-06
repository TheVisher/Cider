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

    @Test("board returns card lineage from root to selected card")
    func boardReturnsCardLineageFromRootToSelectedCard() {
        let board = KanbanBoard(
            name: "Hierarchy",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "root", title: "Root"),
                        KanbanCard(id: "child", title: "Child", parentCardID: "root"),
                        KanbanCard(id: "grandchild", title: "Grandchild", parentCardID: "child"),
                    ]
                ),
            ]
        )

        #expect(board.ancestorCards(for: "grandchild").map(\.id) == ["root", "child"])
        #expect(board.lineageCards(for: "grandchild").map(\.id) == ["root", "child", "grandchild"])
        #expect(board.lineageCards(for: "missing").isEmpty)
    }

    @Test("board resolves related card references without affecting hierarchy")
    func boardResolvesRelatedCardReferencesWithoutAffectingHierarchy() {
        let board = KanbanBoard(
            name: "References",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "parent", title: "Current Plan"),
                        KanbanCard(
                            id: "active",
                            title: "Follow-up",
                            relatedCardIDs: ["old-card", "missing", "active"],
                            parentCardID: "parent"
                        ),
                        KanbanCard(id: "old-card", title: "Archived Implementation"),
                    ]
                ),
            ]
        )

        #expect(board.relatedCards(for: "active").map(\.id) == ["old-card"])
        #expect(board.parentCard(for: "active")?.id == "parent")
        #expect(board.childCards(of: "parent").map(\.id) == ["active"])
    }

    @Test("related card candidates search by id and title and omit current references")
    func relatedCardCandidatesSearchByIDAndTitle() {
        let board = KanbanBoard(
            name: "References",
            columns: [
                KanbanColumn(
                    id: "active",
                    name: "Active",
                    cards: [
                        KanbanCard(
                            id: "current",
                            title: "Current Follow-up",
                            relatedCardIDs: ["done-card"]
                        ),
                        KanbanCard(id: "done-card", title: "Already Linked"),
                        KanbanCard(id: "arch-123", title: "Archived Collapse Polish"),
                    ]
                ),
                KanbanColumn(
                    id: "archive",
                    name: "Archive",
                    cards: [
                        KanbanCard(id: "bf3c18", title: "Kanban parent collapse and progress summary"),
                    ]
                ),
            ]
        )

        #expect(board.relatedCardCandidates(for: "current", matching: "bf3").map(\.id) == ["bf3c18"])
        #expect(board.relatedCardCandidates(for: "current", matching: "collapse").map(\.id) == ["arch-123", "bf3c18"])
        #expect(board.relatedCardCandidates(for: "current", matching: "linked").isEmpty)
        #expect(board.relatedCardCandidates(for: "current", matching: "current").isEmpty)
        #expect(board.relatedCardCandidates(for: "current", matching: "").isEmpty)
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

    @Test("same-column grandchildren render under their parent group")
    func sameColumnGrandchildrenRenderUnderParentGroup() {
        let column = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent"),
                KanbanCard(id: "child", title: "Child", parentCardID: "parent"),
                KanbanCard(id: "grandchild", title: "Grandchild", parentCardID: "child"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [column])

        let nodes = KanbanBoardLayout.cardNodes(for: column, in: board)
        let groups = KanbanBoardLayout.cardGroups(for: column, in: board)

        #expect(nodes.map(\.card.id) == ["parent", "child", "grandchild"])
        #expect(nodes.map(\.depth) == [0, 1, 2])
        #expect(nodes.map(\.sameColumnParentID) == [nil, "parent", "child"])
        #expect(groups.map(\.parent.card.id) == ["parent"])
        #expect(groups.first?.children.map(\.card.id) == ["child", "grandchild"])
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

    @Test("collapsed parent groups hide all same-column descendants")
    func collapsedParentGroupsHideAllSameColumnDescendants() {
        let column = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "parent", title: "Parent"),
                KanbanCard(id: "child", title: "Child", parentCardID: "parent"),
                KanbanCard(id: "grandchild", title: "Grandchild", parentCardID: "child"),
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
        #expect(groups.first?.sameColumnChildCount == 2)
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

    @Test("child card exposes a quiet plan indicator with sibling order")
    func childCardExposesPlanIndicatorWithSiblingOrder() {
        let board = KanbanBoard(
            name: "Hierarchy",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "parent", title: "Kanban hierarchy plan", color: .green),
                        KanbanCard(id: "child-a", title: "First step", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "child-b", title: "Second step", parentCardID: "parent"),
                    ]
                ),
            ]
        )

        let indicator = KanbanBoardLayout.planIndicator(for: board.columns[1].cards[0], in: board)

        #expect(indicator?.parentID == "parent")
        #expect(indicator?.title == "Kanban hierarchy plan")
        #expect(indicator?.stepNumber == 2)
        #expect(indicator?.stepCount == 2)
        #expect(indicator?.compactText == "Step 2/2")
        #expect(indicator?.accentColor == .green)
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

    @Test("nested group accent uses explicit parent color when ancestors have no color")
    func nestedGroupAccentUsesExplicitParentColorWhenAncestorsHaveNoColor() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "grandparent", title: "Grandparent"),
                KanbanCard(id: "parent", title: "Parent Plan", color: .red, parentCardID: "grandparent"),
                KanbanCard(id: "child", title: "Child Step", color: .green, parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog])

        #expect(KanbanBoardLayout.cardAccentColor(for: backlog.cards[1], in: board) == .red)
        #expect(KanbanBoardLayout.cardAccentColor(for: backlog.cards[2], in: board) == .red)
    }

    @Test("hierarchy connector accent matches parent card accent")
    func hierarchyConnectorAccentMatchesParentCardAccent() {
        let backlog = KanbanColumn(
            id: "backlog",
            name: "Backlog",
            cards: [
                KanbanCard(id: "grandparent", title: "Grandparent"),
                KanbanCard(id: "parent", title: "Parent Plan", color: .red, parentCardID: "grandparent"),
                KanbanCard(id: "child", title: "Child Step", parentCardID: "parent"),
            ]
        )
        let board = KanbanBoard(name: "Hierarchy", columns: [backlog])

        #expect(KanbanBoardLayout.hierarchyConnectorAccentColor(for: backlog.cards[1], in: board) == .red)
        #expect(KanbanBoardLayout.hierarchyConnectorAccentColor(for: backlog.cards[1], in: board) == KanbanBoardLayout.cardAccentColor(for: backlog.cards[1], in: board))
    }
}
