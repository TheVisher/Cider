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
}
