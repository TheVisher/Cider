import Testing
@testable import Cider

struct SearchPaletteSearchPublishPolicyTests {
    @Test("cancelled searches do not publish results")
    func cancelledSearchesDoNotPublishResults() {
        #expect(!SearchPaletteSearchPublishPolicy.canPublish(
            taskQuery: "needle",
            currentQuery: "needle",
            isCancelled: true
        ))
    }

    @Test("superseded searches do not publish stale results")
    func supersededSearchesDoNotPublishStaleResults() {
        #expect(!SearchPaletteSearchPublishPolicy.canPublish(
            taskQuery: "old query",
            currentQuery: "new query",
            isCancelled: false
        ))
    }

    @Test("current non-cancelled search publishes results")
    func currentNonCancelledSearchPublishesResults() {
        #expect(SearchPaletteSearchPublishPolicy.canPublish(
            taskQuery: "needle",
            currentQuery: "  needle  ",
            isCancelled: false
        ))
    }

    @Test("typing with the full query selected replaces instead of appending")
    func fullSelectionTypingReplacesQueryInsteadOfAppending() {
        let original = "Jami smores"
        let result = SearchPaletteQueryEditing.replacingSelectedText(
            in: original,
            selection: 0..<original.count,
            replacement: "Botan Ramen"
        )

        #expect(result == "Botan Ramen")
    }

    @Test("typing without a selection still inserts at the caret")
    func caretTypingStillInsertsAtCaret() {
        let result = SearchPaletteQueryEditing.replacingSelectedText(
            in: "Botan",
            selection: 5..<5,
            replacement: " Ramen"
        )

        #expect(result == "Botan Ramen")
    }
}
