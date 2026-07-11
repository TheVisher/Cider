import Testing
@testable import Cider

@MainActor
struct HomeDashboardReviewLoaderTests {
    @Test func repeatedLoadsReuseTheNavigationSnapshotUntilInvalidated() async {
        var loadCount = 0
        let loader = HomeDashboardReviewLoader {
            loadCount += 1
            return nil
        }

        await loader.loadIfNeeded()
        await loader.loadIfNeeded()
        #expect(loadCount == 1)

        loader.invalidate()
        await loader.loadIfNeeded()
        #expect(loadCount == 2)
    }
}
