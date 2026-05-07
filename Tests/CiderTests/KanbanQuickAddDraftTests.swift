import Testing
@testable import Cider

struct KanbanQuickAddDraftTests {
    @Test("quick add draft normalizes metadata for card creation")
    func quickAddDraftNormalizesMetadataForCardCreation() {
        var draft = KanbanQuickAddDraft()
        draft.title = "  New card  "
        draft.notes = "  Useful notes  "
        draft.priority = .high
        draft.color = .purple
        draft.tagsText = " kanban, quick-add, kanban "
        draft.parentCardID = "parent"

        #expect(draft.canCreate)
        #expect(draft.trimmedTitle == "New card")
        #expect(draft.trimmedNotes == "Useful notes")
        #expect(draft.tags == ["kanban", "quick-add", "kanban"])
    }

    @Test("blank quick add draft cannot create a card")
    func blankQuickAddDraftCannotCreateCard() {
        let draft = KanbanQuickAddDraft()

        #expect(!draft.canCreate)
        #expect(draft.trimmedNotes == nil)
        #expect(draft.tags.isEmpty)
    }
}
