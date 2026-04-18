import AppKit
import Foundation
import Testing
@testable import Cider

struct DetailSlideOutMotionTests {
    @Test("sidebar child transitions stay disabled so the panel moves as one surface")
    func sidebarTransitionStyleStaysIdentity() {
        #expect(DetailSlideOutMotionPolicy.sidebarTransitionStyle() == .identity)
    }

    @Test("slide-out detail panels composite into one moving surface")
    func slideOutPanelsCompositeAsSingleSurface() {
        #expect(DetailSlideOutMotionPolicy.shouldCompositeSurface(detailViewMode: .slideOut))
        #expect(DetailSlideOutMotionPolicy.shouldCompositeSurface(detailViewMode: .page))
    }

    @Test("slide-out detail preloads web content after the entrance animation settles")
    func slideOutPreloadDelayIsLongerThanPage() {
        #expect(DetailSlideOutMotionPolicy.preloadDelay(for: .slideOut) == .milliseconds(700))
        #expect(DetailSlideOutMotionPolicy.preloadDelay(for: .page) == .zero)
        #expect(DetailSlideOutMotionPolicy.preloadDelay(for: .fullPanel) == .zero)
    }

    @MainActor
    @Test("hero preview can bootstrap from cached thumbnails before async loading")
    func heroPreviewUsesCachedThumbnailImmediately() {
        let image = NSImage(size: NSSize(width: 12, height: 8))
        let filePath = "/tmp/detail-hero-bootstrap-\(UUID().uuidString)"
        let modifiedAt = 1234.5

        BookmarkThumbnailCache.shared.set(image, for: filePath, modifiedAt: modifiedAt)

        let bootstrapped = DetailHeroPreviewImageBootstrap.cachedThumbnailImage(
            filePath: filePath,
            modifiedAt: modifiedAt
        )

        #expect(bootstrapped != nil)
        #expect(ObjectIdentifier(bootstrapped!) == ObjectIdentifier(image))
    }
}
