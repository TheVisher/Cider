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

    @Test("board finds cards that backlink a linked reference item")
    func boardFindsCardsThatBacklinkLinkedReferenceItem() {
        let ref = LibraryEntityRef(
            type: .bookmark,
            entityID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        )
        let otherRef = LibraryEntityRef(
            type: .note,
            entityID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        )
        let board = KanbanBoard(
            name: "References",
            columns: [
                KanbanColumn(
                    id: "active",
                    name: "Active",
                    cards: [
                        KanbanCard(id: "a", title: "Uses bookmark", linkedEntities: [ref]),
                        KanbanCard(id: "b", title: "Uses note", linkedEntities: [otherRef]),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "c", title: "Also uses bookmark", linkedEntities: [ref]),
                    ]
                ),
            ]
        )

        #expect(board.cards(linking: ref).map(\.id) == ["a", "c"])
        #expect(board.cards(linking: otherRef).map(\.id) == ["b"])
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

    @Test("card face hides body previews and uses semantic chips instead of priority text")
    func cardFaceHidesBodyPreviewsAndUsesSemanticChips() {
        let card = KanbanCard(
            id: "visual",
            title: "Visual polish",
            notes: "Problem:\n- Raw problem text belongs in the drawer.",
            aiSummary: "Generated summary should also stay off the card face.",
            priority: .high,
            agent: "Cody",
            tags: ["bug", "performance", "high"]
        )

        #expect(KanbanBoardLayout.cardFacePreviewText(for: card) == nil)
        #expect(KanbanBoardLayout.cardFaceSemanticChips(for: card) == ["Bug", "Performance"])
        #expect(!KanbanBoardLayout.cardFaceSemanticChips(for: card).contains("High"))
    }

    @Test("card face chips always expose tag editor affordance when tags are empty")
    func cardFaceChipsAlwaysExposeTagEditorAffordanceWhenTagsAreEmpty() {
        let card = KanbanCard(
            id: "empty-tags",
            title: "Empty tag card",
            tags: []
        )

        let chips = KanbanBoardLayout.cardFaceChips(for: card)

        #expect(chips.map(\.label) == ["…"])
        #expect(chips.map(\.role) == [.tagEdit])
        #expect(chips.first?.activation == .tagEditor)
    }

    @Test("card face chips expose all semantic tags so the footer can wrap rows")
    func cardFaceChipsExposeAllSemanticTagsSoFooterCanWrapRows() {
        let card = KanbanCard(
            id: "many-tags",
            title: "Many tag card",
            tags: ["sidebar", "cider-web", "cider-ios", "bug", "testing", "manual-qa", "blocked", "high"]
        )

        let chips = KanbanBoardLayout.cardFaceChips(for: card)

        #expect(chips.map(\.label) == ["…", "Interface", "Apps", "Bug", "Testing", "Manual QA", "Blocked"])
        #expect(chips.map(\.accessory) == [.none, .featureIcon, .featureIcon, .colorDot, .colorDot, .colorDot, .colorDot])
        #expect(!chips.map(\.label).contains("High"))
    }

    @Test("card face chips put feature or domain before type and expose emphasis roles")
    func cardFaceChipsPutFeatureDomainBeforeTypeWithEmphasisRoles() {
        let card = KanbanCard(
            id: "sidebar-bug",
            title: "Sidebar chip hierarchy",
            priority: .medium,
            tags: ["bug", "sidebar", "testing", "medium"]
        )

        let chips = KanbanBoardLayout.cardFaceChips(for: card)

        #expect(chips.map(\.label) == ["…", "Interface", "Bug", "Testing"])
        #expect(chips.map(\.role) == [.tagEdit, .featureDomain, .typeStatus, .typeStatus])
        #expect(chips.map(\.accessory) == [.none, .featureIcon, .colorDot, .colorDot])
        #expect(chips.map(\.surface) == [.muted, .muted, .muted, .muted])
        #expect(chips[0].showsDisclosureIndicator == false)
        #expect(chips[0].activation == .tagEditor)
        #expect(chips[1].iconSystemName == "cube.transparent")
        #expect(chips[2].iconSystemName == nil)
        #expect(KanbanBoardLayout.cardFaceSemanticChips(for: card) == ["Interface", "Bug", "Testing"])
    }

    @Test("card face overflow menu exposes a bounded semantic tag list")
    func cardFaceOverflowMenuExposesBoundedSemanticTagList() {
        let card = KanbanCard(
            id: "overflow-tags",
            title: "Overflow tag menu",
            priority: .high,
            tags: ["cider-web", "sidebar", "bug", "testing", "manual-qa", "blocked", "high", "cider-ios"]
        )

        let overflowTags = KanbanBoardLayout.cardFaceOverflowTags(for: card, limit: 5)

        #expect(overflowTags.map(\.label) == ["Apps", "Interface", "Bug", "Testing", "Manual QA"])
        #expect(overflowTags.map(\.accessory) == [.featureIcon, .featureIcon, .colorDot, .colorDot, .colorDot])
        #expect(overflowTags.map(\.activation) == [
            .featureDomainFilter("apps"),
            .featureDomainFilter("interface"),
            .none,
            .none,
            .none,
        ])
        #expect(!overflowTags.map(\.label).contains("High"))
    }

    @Test("feature domain filters use a curated canonical set and merge aliases")
    func featureDomainFiltersUseCuratedCanonicalSetAndMergeAliases() {
        let board = KanbanBoard(name: "Feature filters", columns: [
            KanbanColumn(id: "todo", name: "Todo", cards: [
                KanbanCard(id: "sidebar-bug", title: "Sidebar bug", tags: ["sidebar", "bug", "high"]),
                KanbanCard(id: "web-qa", title: "Web QA", tags: ["cider-web", "qa", "sidebar"]),
                KanbanCard(id: "idea-only", title: "Idea only", tags: ["idea", "performance"]),
            ]),
            KanbanColumn(id: "done", name: "Done", cards: [
                KanbanCard(id: "inbox", title: "Project Inbox", tags: ["project-inbox", "testing"]),
            ]),
        ])

        let filters = KanbanBoardLayout.featureDomainFilters(for: board)

        #expect(filters.map(\.id) == ["second-brain", "apps", "interface"])
        #expect(filters.map(\.label) == ["Second Brain", "Apps", "Interface"])
        #expect(filters.map(\.cardCount) == [1, 1, 2])
    }

    @Test("feature domain filter narrows cards and can be cleared")
    func featureDomainFilterNarrowsCardsAndCanBeCleared() {
        let cards = [
            KanbanCard(id: "sidebar-bug", title: "Sidebar bug", tags: ["sidebar", "bug"]),
            KanbanCard(id: "web-qa", title: "Web QA", tags: ["cider-web", "qa"]),
            KanbanCard(id: "untagged", title: "Untagged")
        ]

        #expect(KanbanBoardLayout.cards(cards, matchingFeatureDomainFilter: "interface").map(\.id) == ["sidebar-bug"])
        #expect(KanbanBoardLayout.cards(cards, matchingFeatureDomainFilter: "Sidebar").map(\.id) == ["sidebar-bug"])
        #expect(KanbanBoardLayout.cards(cards, matchingFeatureDomainFilter: "apps").map(\.id) == ["web-qa"])
        #expect(KanbanBoardLayout.cards(cards, matchingFeatureDomainFilter: nil).map(\.id) == ["sidebar-bug", "web-qa", "untagged"])
        #expect(KanbanBoardLayout.cards(cards, matchingFeatureDomainFilter: "bug").isEmpty)
    }

    @Test("plan indicator marks the first active child as next up")
    func planIndicatorMarksFirstActiveChildAsNextUp() {
        let completed = Date(timeIntervalSince1970: 1_777_737_600)
        let board = KanbanBoard(
            name: "Next Up",
            columns: [
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(id: "parent", title: "Plan", color: .green),
                        KanbanCard(id: "step-1", title: "Done step", parentCardID: "parent", completed: completed),
                    ]
                ),
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "step-2", title: "Next step", parentCardID: "parent"),
                        KanbanCard(id: "step-3", title: "Later step", parentCardID: "parent"),
                    ]
                ),
            ]
        )

        let nextIndicator = KanbanBoardLayout.planIndicator(for: board.columns[1].cards[0], in: board)
        let laterIndicator = KanbanBoardLayout.planIndicator(for: board.columns[1].cards[1], in: board)

        #expect(nextIndicator?.isNextUp == true)
        #expect(nextIndicator?.compactText == "Next Up · Step 2/3")
        #expect(laterIndicator?.isNextUp == false)
        #expect(laterIndicator?.compactText == "Step 3/3")
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
