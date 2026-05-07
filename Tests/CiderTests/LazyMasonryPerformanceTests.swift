import Foundation
import Testing
@testable import Cider

struct LazyMasonryPerformanceTests {
    private struct TestItem: Identifiable {
        let id: Int
        let baseHeight: CGFloat
    }

    @Test("masonry planner avoids per-pixel replans during live resize")
    func masonryPlannerAvoidsPerPixelReplansDuringLiveResize() {
        let items = (0..<1_000).map { index in
            TestItem(id: index, baseHeight: CGFloat(120 + (index % 11) * 24))
        }
        var previousPlan = LazyMasonryColumnPlanner.Plan<Int>.empty
        var recomputeCount = 0
        let start = ContinuousClock.now

        for width in stride(from: CGFloat(720), through: CGFloat(1_120), by: CGFloat(1)) {
            let layout = LazyMasonryColumnPlanner.layout(
                containerWidth: width,
                minimumColumnWidth: 220,
                itemSpacing: 16
            )
            let nextPlan = LazyMasonryColumnPlanner.stablePlan(
                items: items,
                layout: layout,
                itemSpacing: 16,
                estimatedHeight: { item in item.baseHeight + layout.columnWidth * 0.18 },
                previousPlan: previousPlan
            )
            if nextPlan.key != previousPlan.key {
                recomputeCount += 1
            }
            previousPlan = nextPlan
        }

        let elapsed = start.duration(to: ContinuousClock.now)
        print("MASONRY_RESIZE_PLAN widths=401 items=1000 recompute_count=\(recomputeCount) elapsed=\(elapsed)")
        #expect(recomputeCount <= 60)
    }
}
