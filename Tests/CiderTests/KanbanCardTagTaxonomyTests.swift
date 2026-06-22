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

    @Test("board discovery filter matches attachment type and explains match")
    func boardDiscoveryFilterMatchesAttachmentTypeAndExplainsMatch() throws {
        let board = KanbanBoard(
            id: "board",
            name: "Cider",
            columns: [
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(
                            id: "research-card",
                            title: "Research card",
                            comments: [
                                KanbanCardComment(
                                    id: "research-comment",
                                    kind: .note,
                                    body: "Useful reference.",
                                    attachments: [
                                        KanbanCardCommentAttachment(
                                            id: "research-link",
                                            kind: .url,
                                            type: .research,
                                            title: "Research link",
                                            url: "https://example.com/research"
                                        )
                                    ]
                                )
                            ]
                        ),
                        KanbanCard(
                            id: "qa-card",
                            title: "QA card",
                            comments: [
                                KanbanCardComment(
                                    id: "qa-comment",
                                    kind: .qa,
                                    body: "QA evidence.",
                                    attachments: [
                                        KanbanCardCommentAttachment(
                                            id: "qa-file",
                                            kind: .file,
                                            type: .qa,
                                            title: "QA file",
                                            localPath: "Projects/Cider/QA/report.md"
                                        )
                                    ]
                                )
                            ]
                        ),
                        KanbanCard(id: "plain-card", title: "Plain card")
                    ]
                )
            ]
        )

        let result = try board.filteredForDiscovery(
            KanbanBoardDiscoveryFilter(attachmentTypes: [.research])
        )

        #expect(result.board.columns[0].cards.map(\.id) == ["research-card"])
        let match = try #require(result.matchesByCardID["research-card"])
        #expect(match.reasons == [.attachmentType])
        #expect(match.attachmentTypes == [.research])
        #expect(match.commentIDs == ["research-comment"])
        #expect(match.attachmentIDs == ["research-link"])
        #expect(result.matchesByCardID["qa-card"] == nil)
        #expect(result.matchesByCardID["plain-card"] == nil)
    }

    @Test("board discovery text query preserves title notes tags and comment matching")
    func boardDiscoveryTextQueryPreservesTitleNotesTagsAndCommentMatching() {
        let board = KanbanBoard(
            id: "board",
            name: "Cider",
            columns: [
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "title", title: "Reference polish"),
                        KanbanCard(id: "notes", title: "Other", notes: "Contains reference details"),
                        KanbanCard(id: "tag", title: "Other", tags: ["reference"]),
                        KanbanCard(
                            id: "comment",
                            title: "Other",
                            comments: [
                                KanbanCardComment(kind: .note, body: "Comment mentions reference")
                            ]
                        ),
                        KanbanCard(id: "miss", title: "Other")
                    ]
                )
            ]
        )

        let result = try? board.filteredForDiscovery(KanbanBoardDiscoveryFilter(query: "reference"))

        #expect(result?.board.columns[0].cards.map(\.id) == ["title", "notes", "tag", "comment"])
        #expect(result?.matchesByCardID["title"]?.reasons == [.title])
        #expect(result?.matchesByCardID["notes"]?.reasons == [.notes])
        #expect(result?.matchesByCardID["tag"]?.reasons == [.tag])
        #expect(result?.matchesByCardID["comment"]?.reasons == [.comment])
    }
}
