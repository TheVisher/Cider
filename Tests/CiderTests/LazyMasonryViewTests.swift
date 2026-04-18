import AppKit
import Testing
@testable import Cider

struct LazyMasonryViewTests {
    private struct TestItem: Identifiable {
        let id: String
        let estimatedHeight: CGFloat
    }

    @Test("lazy masonry assigns items to the shortest column using estimates")
    func plannerAssignsItemsGreedily() {
        let items = [
            TestItem(id: "a", estimatedHeight: 200),
            TestItem(id: "b", estimatedHeight: 120),
            TestItem(id: "c", estimatedHeight: 180),
        ]

        let columns = LazyMasonryColumnPlanner.plan(
            items: items,
            columnCount: 2,
            itemSpacing: 12
        ) { $0.estimatedHeight }

        #expect(columns.count == 2)
        #expect(columns[0].map(\.id) == ["a"])
        #expect(columns[1].map(\.id) == ["b", "c"])
    }

    @Test("lazy masonry computes adaptive column widths")
    func plannerComputesColumnWidth() {
        let layout = LazyMasonryColumnPlanner.layout(
            containerWidth: 800,
            minimumColumnWidth: 240,
            itemSpacing: 16
        )

        #expect(layout.columnCount == 3)
        #expect(layout.columnWidth == 256)
    }

    @Test("lazy masonry keeps a stable column plan while estimates change")
    func plannerKeepsStableColumnsForSameItemsAndLayout() {
        let items = [
            TestItem(id: "a", estimatedHeight: 200),
            TestItem(id: "b", estimatedHeight: 120),
            TestItem(id: "c", estimatedHeight: 180),
        ]
        let layout = LazyMasonryColumnPlanner.LayoutMetrics(columnCount: 2, columnWidth: 240)

        let initialPlan = LazyMasonryColumnPlanner.stablePlan(
            items: items,
            layout: layout,
            itemSpacing: 12,
            estimatedHeight: { $0.estimatedHeight },
            previousPlan: .empty
        )
        let updatedPlan = LazyMasonryColumnPlanner.stablePlan(
            items: items.map { item in
                TestItem(id: item.id, estimatedHeight: item.estimatedHeight * 4)
            },
            layout: layout,
            itemSpacing: 12,
            estimatedHeight: { $0.estimatedHeight },
            previousPlan: initialPlan
        )

        #expect(updatedPlan == initialPlan)
    }

    @Test("thumbnail cache stores aspect ratio for masonry sizing")
    @MainActor
    func thumbnailCacheStoresAspectRatio() {
        let image = NSImage(size: NSSize(width: 300, height: 450))
        let entry = BookmarkThumbnailCache.CachedThumbnail(
            image: image,
            aspectRatio: 1.5,
            isIconOverlay: false
        )

        BookmarkThumbnailCache.shared.set(entry, for: "/tmp/lazy-masonry-thumb.png", modifiedAt: 1)

        #expect(BookmarkThumbnailCache.shared.aspectRatio(for: "/tmp/lazy-masonry-thumb.png", modifiedAt: 1) == 1.5)
    }

    @Test("bookmark masonry estimates use cached thumbnail aspect ratio")
    @MainActor
    func bookmarkMasonryEstimateUsesCachedAspectRatio() {
        let bookmark = Bookmark(
            title: "Example",
            urlString: "https://example.com",
            thumbnailRelativePath: "thumbnails/example.png",
            metadataUpdatedAt: Date(timeIntervalSince1970: 2)
        )

        let image = NSImage(size: NSSize(width: 200, height: 300))
        BookmarkThumbnailCache.shared.set(
            .init(image: image, aspectRatio: 1.5, isIconOverlay: false),
            for: bookmark.thumbnailFileURL!.path,
            modifiedAt: 2
        )

        let sizing = LibraryCardSizing(scale: 1)
        let estimate = LibraryItemMasonryMetrics.estimatedHeight(
            for: .bookmark(bookmark),
            columnWidth: 200,
            cardSizing: sizing
        )

        #expect(estimate > sizing.bookmarkSizing.masonryThumbnailHeightFallback + 60)
    }
}
