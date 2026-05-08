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

    @Test("masonry render width avoids per-pixel relayout during live resize")
    func masonryRenderWidthAvoidsPerPixelRelayoutDuringLiveResize() {
        var distinctRenderWidths = Set<CGFloat>()

        for width in stride(from: CGFloat(720), through: CGFloat(1_120), by: CGFloat(1)) {
            let layout = LazyMasonryColumnPlanner.layout(
                containerWidth: width,
                minimumColumnWidth: 220,
                itemSpacing: 16
            )
            distinctRenderWidths.insert(LazyMasonryColumnPlanner.renderingColumnWidth(for: layout))
        }

        print("MASONRY_RENDER_WIDTH widths=401 distinct_render_widths=\(distinctRenderWidths.count)")
        #expect(distinctRenderWidths.count <= 60)
    }

    @Test("masonry container width publishing avoids per-pixel body invalidation")
    func masonryContainerWidthPublishingAvoidsPerPixelBodyInvalidation() {
        var publishedWidth: CGFloat = 0
        var publishCount = 0

        for width in stride(from: CGFloat(720), through: CGFloat(1_120), by: CGFloat(1)) {
            guard LazyMasonryColumnPlanner.shouldPublishContainerWidth(
                currentWidth: publishedWidth,
                candidateWidth: width,
                minimumColumnWidth: 220,
                itemSpacing: 16
            ) else { continue }
            publishedWidth = width
            publishCount += 1
        }

        print("MASONRY_CONTAINER_WIDTH widths=401 publish_count=\(publishCount)")
        #expect(publishCount <= 60)
    }
}
