import Foundation
import Testing
@testable import Cider

struct KanbanCardDraftTests {
    @Test("draft preserves very long product refinement notes")
    func draftPreservesVeryLongProductRefinementNotes() {
        let longNotes = (1...300)
            .map { "Refactor note \($0): preserve this paragraph exactly enough for product refinement." }
            .joined(separator: "\n\n")
        let card = KanbanCard(
            id: "card-1",
            title: "Refactor capture pipeline",
            notes: longNotes,
            color: .blue,
            priority: .high,
            agent: "Codex",
            tags: ["refactor", "capture"],
            created: Date(timeIntervalSince1970: 100),
            completed: nil
        )

        let draft = KanbanCardDraft(card: card)
        let updated = draft.updatedCard(from: card)

        #expect(updated.notes == longNotes)
        #expect(updated.title == "Refactor capture pipeline")
        #expect(updated.tags == ["refactor", "capture"])
    }

    @Test("draft normalizes empty title, blank notes, blank agent, and comma tags")
    func draftNormalizesEditableFields() {
        var draft = KanbanCardDraft(card: KanbanCard(id: "card-2", title: "Original"))
        draft.title = "   "
        draft.notes = "   \n  "
        draft.agent = "   "
        draft.tagsText = " roadmap,  refinement, roadmap ,  "

        let updated = draft.updatedCard(from: KanbanCard(id: "card-2", title: "Original"))

        #expect(updated.title == "Untitled Card")
        #expect(updated.notes == nil)
        #expect(updated.agent == nil)
        #expect(updated.tags == ["roadmap", "refinement", "roadmap"])
    }

    @Test("draft merges notes and priority without losing completed date")
    func draftMergesNotesAndPriorityWithoutLosingCompletedDate() {
        let completed = Date(timeIntervalSince1970: 1_700_000_000)
        let movedCard = KanbanCard(
            id: "card-3",
            title: "Ship detail panel",
            notes: "Old notes",
            priority: .medium,
            completed: completed
        )
        var draft = KanbanCardDraft(card: movedCard)
        draft.notes = "Fresh product refinement notes"
        draft.priority = .high

        let updated = draft.updatedCard(from: movedCard)

        #expect(updated.notes == "Fresh product refinement notes")
        #expect(updated.priority == .high)
        #expect(updated.completed == completed)
    }

    @Test("draft preserves linked specs and applies linked item edits")
    func draftPreservesLinkedSpecsAndAppliesLinkedItemEdits() {
        let existingRef = LibraryEntityRef(type: .note, entityID: UUID())
        let addedRef = LibraryEntityRef(type: .vaultFile, entityID: UUID())
        let card = KanbanCard(
            id: "card-4",
            title: "Refactor mini spec",
            linkedEntities: [existingRef]
        )

        var draft = KanbanCardDraft(card: card)
        draft.notes = "Keep the implementation notes on the card."
        draft.linkedEntities.append(addedRef)

        let updated = draft.updatedCard(from: card)

        #expect(updated.notes == "Keep the implementation notes on the card.")
        #expect(updated.linkedEntities == [existingRef, addedRef])
    }

    @Test("draft preserves parent card relationship")
    func draftPreservesParentCardRelationship() {
        let card = KanbanCard(
            id: "child-card",
            title: "Child Card",
            parentCardID: "parent-card"
        )

        var draft = KanbanCardDraft(card: card)
        draft.notes = "Edited child notes"

        let updated = draft.updatedCard(from: card)

        #expect(updated.parentCardID == "parent-card")
        #expect(updated.notes == "Edited child notes")
    }

    @Test("draft preserves related card references separately from parent")
    func draftPreservesRelatedCardReferencesSeparatelyFromParent() {
        let card = KanbanCard(
            id: "active-card",
            title: "New tweak",
            relatedCardIDs: ["old-card"],
            parentCardID: "current-plan"
        )

        var draft = KanbanCardDraft(card: card)
        draft.relatedCardIDs.append("historical-bug")

        let updated = draft.updatedCard(from: card)

        #expect(updated.parentCardID == "current-plan")
        #expect(updated.relatedCardIDs == ["old-card", "historical-bug"])
    }

    @Test("draft preserves and edits structured history entries")
    func draftPreservesAndEditsStructuredHistoryEntries() {
        let existing = KanbanCardHistoryEntry(
            id: "entry-1",
            type: .testEvidence,
            body: "Initial test evidence",
            author: "Hermes",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let card = KanbanCard(
            id: "history-card",
            title: "History Card",
            historyEntries: [existing]
        )

        var draft = KanbanCardDraft(card: card)
        draft.historyEntries.append(
            KanbanCardHistoryEntry(
                id: "entry-2",
                type: .finalSummary,
                body: "Final implementation summary",
                author: "Codex",
                createdAt: Date(timeIntervalSince1970: 1_700_100_000)
            )
        )

        let updated = draft.updatedCard(from: card)

        #expect(updated.historyEntries.map(\.id) == ["entry-1", "entry-2"])
        #expect(updated.historyEntries.last?.type == .finalSummary)
        #expect(updated.historyEntries.last?.body == "Final implementation summary")
    }

    @Test("draft preserves and appends threaded comments separately from notes")
    func draftPreservesAndAppendsThreadedCommentsSeparatelyFromNotes() {
        let existing = KanbanCardComment(
            id: "comment-1",
            kind: .handoff,
            body: "Agent handoff stays out of source notes.",
            author: "Cody",
            source: "discord",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let card = KanbanCard(
            id: "comments-card",
            title: "Comments Card",
            notes: "Problem: keep this source spec intact.",
            comments: [existing]
        )

        var draft = KanbanCardDraft(card: card)
        draft.comments.append(KanbanCardComment(
            id: "comment-2",
            kind: .evidence,
            body: "Focused persistence test passed.",
            author: "Cody",
            source: "cli",
            createdAt: Date(timeIntervalSince1970: 1_700_100_000),
            parentCommentID: "comment-1"
        ))

        let updated = draft.updatedCard(from: card)

        #expect(updated.notes == "Problem: keep this source spec intact.")
        #expect(updated.comments.map(\.id) == ["comment-1", "comment-2"])
        #expect(updated.comments.last?.kind == .evidence)
        #expect(updated.comments.last?.parentCommentID == "comment-1")
    }

    @Test("draft preserves typed comment attachments")
    func draftPreservesTypedCommentAttachments() {
        let card = KanbanCard(
            id: "attachment-card",
            title: "Attachment Card"
        )

        var draft = KanbanCardDraft(card: card)
        draft.comments.append(KanbanCardComment(
            id: "comment-with-attachments",
            kind: .evidence,
            body: "Keep the research URL and local screenshot on the card.",
            attachments: [
                KanbanCardCommentAttachment(
                    id: "research-url",
                    kind: .url,
                    type: .research,
                    title: "Linear inspiration",
                    url: "https://linear.app/changelog",
                    previewKind: .link
                ),
                KanbanCardCommentAttachment(
                    id: "local-shot",
                    kind: .image,
                    type: .inspiration,
                    title: "Card detail screenshot",
                    localPath: "Projects/Cider/QA/card-detail.png",
                    previewKind: .image
                ),
            ]
        ))

        let updated = draft.updatedCard(from: card)

        let attachments = updated.comments.first?.attachments ?? []
        #expect(attachments.map(\.id) == ["research-url", "local-shot"])
        #expect(attachments.first?.type == .research)
        #expect(attachments.first?.url == "https://linear.app/changelog")
        #expect(attachments.last?.kind == .image)
        #expect(attachments.last?.localPath == "Projects/Cider/QA/card-detail.png")
        #expect(updated.attachmentSummary.totalCount == 2)
        #expect(updated.attachmentSummary.countsByType[.research] == 1)
        #expect(updated.attachmentSummary.countsByPreviewKind[.image] == 1)
    }
}
