import Testing

@testable import Cider

struct KanbanDetailSlideOutLayoutPolicyTests {
    @Test("shrinking Kanban detail hides metadata before source notes")
    func shrinkingHidesMetadataBeforeSourceNotes() {
        let bothVisibleWidth = KanbanDetailSlideOutLayoutPolicy.minimumWidth(
            sourceNotesVisible: true,
            metadataVisible: true
        )
        let sourceOnlyWidth = KanbanDetailSlideOutLayoutPolicy.minimumWidth(
            sourceNotesVisible: true,
            metadataVisible: false
        )

        let metadataHidden = KanbanDetailSlideOutLayoutPolicy.fittingState(
            for: bothVisibleWidth - 1,
            sourceNotesVisible: true,
            metadataVisible: true
        )
        #expect(metadataHidden.sourceNotesVisible)
        #expect(!metadataHidden.metadataVisible)

        let sourceHidden = KanbanDetailSlideOutLayoutPolicy.fittingState(
            for: sourceOnlyWidth - 1,
            sourceNotesVisible: true,
            metadataVisible: false
        )
        #expect(!sourceHidden.sourceNotesVisible)
        #expect(!sourceHidden.metadataVisible)
    }

    @Test("opening hidden Kanban panes expands slide out to fit")
    func openingHiddenPanesExpandsSlideOutToFit() {
        let sourceOnlyWidth = KanbanDetailSlideOutLayoutPolicy.expandedWidth(
            currentWidth: 600,
            maxWidth: 1_400,
            sourceNotesVisible: true,
            metadataVisible: false
        )
        #expect(sourceOnlyWidth == KanbanDetailSlideOutLayoutPolicy.minimumWidth(sourceNotesVisible: true, metadataVisible: false))

        let allPaneWidth = KanbanDetailSlideOutLayoutPolicy.expandedWidth(
            currentWidth: sourceOnlyWidth,
            maxWidth: 1_400,
            sourceNotesVisible: true,
            metadataVisible: true
        )
        #expect(allPaneWidth == KanbanDetailSlideOutLayoutPolicy.minimumWidth(sourceNotesVisible: true, metadataVisible: true))
    }
}
