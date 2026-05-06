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
}
