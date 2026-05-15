import Foundation
import Testing
@testable import Cider

struct KanbanCardTagTaxonomyTests {
    @Test("core tags stay small and stable for agent feature history")
    func coreTagsStaySmallAndStableForAgentFeatureHistory() {
        #expect(KanbanCardTagTaxonomy.coreTags == [
            "bug",
            "fix",
            "feature",
            "improvement",
            "qa",
            "docs",
            "design",
            "refactor",
            "spike",
            "agent-handoff",
            "blocked",
            "follow-up",
        ])
    }

    @Test("tag normalization handles spaces underscores case and comma lists")
    func tagNormalizationHandlesSpacesUnderscoresCaseAndCommaLists() {
        let tags = KanbanCardTagTaxonomy.normalizedTags(from: [
            " Agent Handoff ",
            "follow_up, QA",
            "qa",
            "feature   history",
        ])

        #expect(tags == ["agent-handoff", "follow-up", "qa", "feature-history"])
        #expect(KanbanCardTagTaxonomy.isCoreTag("Follow Up"))
        #expect(!KanbanCardTagTaxonomy.isCoreTag("feature-history"))
    }

    @Test("board tag filter keeps cards that match all requested tags")
    func boardTagFilterKeepsCardsThatMatchAllRequestedTags() {
        let board = KanbanBoard(
            id: "board",
            name: "Cider",
            columns: [
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    cards: [
                        KanbanCard(id: "archive-bug", title: "Archive bug", tags: ["kanban", "archive", "bug"]),
                        KanbanCard(id: "archive-feature", title: "Archive feature", tags: ["kanban", "archive", "feature"]),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "qa-card", title: "Archive QA", tags: ["archive", "qa", "follow-up"]),
                    ]
                ),
            ]
        )

        let filtered = board.filteredByTags(["archive", "bug"])

        #expect(filtered.columns[0].cards.map(\.id) == ["archive-bug"])
        #expect(filtered.columns[1].cards.isEmpty)
    }

    @Test("board tag filter normalizes comma-separated tags stored on cards")
    func boardTagFilterNormalizesCommaSeparatedTagsStoredOnCards() {
        let board = KanbanBoard(
            id: "board",
            name: "Cider",
            columns: [
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    cards: [
                        KanbanCard(id: "combined", title: "Combined tags", tags: ["kanban, qa", "Agent Handoff"]),
                        KanbanCard(id: "other", title: "Other tags", tags: ["kanban"]),
                    ]
                ),
            ]
        )

        let filtered = board.filteredByTags(["qa", "agent_handoff"])

        #expect(filtered.columns[0].cards.map(\.id) == ["combined"])
    }
}
