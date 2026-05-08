import Foundation
import Testing
@testable import Cider

struct KanbanCardMarkdownExporterTests {
    @Test("markdown export includes metadata and full notes")
    func markdownExportIncludesMetadataAndFullNotes() {
        let notes = """
        ## Context

        We discussed making Kanban a first-class planning surface.

        ## Acceptance Criteria

        - Card opens in slide-out
        - Long notes stay on the card
        - Export is explicit
        """

        let card = KanbanCard(
            id: "abc123",
            title: "Kanban detail panel",
            notes: notes,
            color: .green,
            priority: .high,
            agent: "Hermes",
            tags: ["kanban", "product"],
            created: Date(timeIntervalSince1970: 0),
            completed: nil
        )

        let markdown = KanbanCardMarkdownExporter.markdown(
            for: card,
            boardName: "Cider Roadmap",
            columnName: "In Progress"
        )

        #expect(markdown.contains("# Kanban detail panel"))
        #expect(markdown.contains("- Board: Cider Roadmap"))
        #expect(markdown.contains("- Status: In Progress"))
        #expect(markdown.contains("- Priority: high"))
        #expect(markdown.contains("- Color: green"))
        #expect(markdown.contains("- Agent: Hermes"))
        #expect(markdown.contains("- Tags: kanban, product"))
        #expect(markdown.contains(notes))
    }

    @Test("markdown filename is safe and ends in md")
    func markdownFilenameIsSafe() {
        let card = KanbanCard(id: "abc123", title: "Refactor: capture / save pipeline?")

        #expect(KanbanCardMarkdownExporter.suggestedFileName(for: card) == "Refactor capture save pipeline.md")
    }

    @Test("markdown export can render current unsaved draft")
    func markdownExportCanRenderCurrentUnsavedDraft() {
        let card = KanbanCard(
            id: "abc123",
            title: "Stored title",
            notes: "Stored notes",
            priority: .low
        )
        var draft = KanbanCardDraft(card: card)
        draft.title = "Draft title"
        draft.notes = "Draft notes that have not been saved yet"
        draft.priority = .high

        let markdown = KanbanCardMarkdownExporter.markdown(
            for: draft,
            baseCard: card,
            boardName: "Roadmap",
            columnName: "Refining"
        )

        #expect(markdown.contains("# Draft title"))
        #expect(markdown.contains("Draft notes that have not been saved yet"))
        #expect(markdown.contains("- Priority: high"))
        #expect(!markdown.contains("Stored notes"))
    }

    @Test("markdown export includes linked reference context for agent handoff")
    func markdownExportIncludesLinkedReferenceContextForAgentHandoff() {
        let refID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let ref = LibraryEntityRef(type: .bookmark, entityID: refID)
        let card = KanbanCard(
            id: "ref-card",
            title: "Build references",
            notes: "Use the inspiration.",
            linkedEntities: [ref]
        )
        let summary = ItemLinkSummary(
            ref: ref,
            title: "Linear inspiration",
            subtitle: "https://linear.app",
            symbol: "bookmark"
        )

        let markdown = KanbanCardMarkdownExporter.markdown(
            for: card,
            boardName: "Cider",
            columnName: "In Progress",
            linkedReferenceSummaries: [summary]
        )

        #expect(markdown.contains("## Linked References"))
        #expect(markdown.contains("- Bookmark: Linear inspiration — https://linear.app [11111111-1111-1111-1111-111111111111]"))
    }
}
