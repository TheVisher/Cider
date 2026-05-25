import Testing
@testable import Cider

struct KanbanHorizontalPanPolicyTests {
    @Test func proposedOffsetClampsToScrollableRange() {
        #expect(KanbanHorizontalPanPolicy.proposedOffset(
            currentOffset: 120,
            dragDeltaX: -60,
            contentWidth: 600,
            viewportWidth: 300
        ) == 180)

        #expect(KanbanHorizontalPanPolicy.proposedOffset(
            currentOffset: 260,
            dragDeltaX: -120,
            contentWidth: 600,
            viewportWidth: 300
        ) == 300)

        #expect(KanbanHorizontalPanPolicy.proposedOffset(
            currentOffset: 20,
            dragDeltaX: 80,
            contentWidth: 600,
            viewportWidth: 300
        ) == 0)
    }

    @Test func proposedOffsetReturnsZeroWhenContentFitsViewport() {
        #expect(KanbanHorizontalPanPolicy.proposedOffset(
            currentOffset: 40,
            dragDeltaX: -120,
            contentWidth: 260,
            viewportWidth: 300
        ) == 0)
    }
}
