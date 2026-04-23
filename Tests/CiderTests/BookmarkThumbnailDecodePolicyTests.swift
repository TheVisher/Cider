import AppKit
import Foundation
import ImageIO
import Testing
@testable import Cider

struct BookmarkThumbnailDecodePolicyTests {
    @Test("bookmark card decode policy caps thumbnail sizes by presentation mode")
    func cardThumbnailSizesAreCapped() {
        #expect(BookmarkThumbnailDecodePolicy.cardMaxPixelSize(for: BookmarkThumbnailView.ThumbnailMode.list) == 160)
        #expect(BookmarkThumbnailDecodePolicy.cardMaxPixelSize(for: BookmarkThumbnailView.ThumbnailMode.grid) == 512)
        #expect(BookmarkThumbnailDecodePolicy.cardMaxPixelSize(for: BookmarkThumbnailView.ThumbnailMode.masonry) == 640)
        #expect(BookmarkThumbnailDecodePolicy.carouselMaxPixelSize == 640)
    }

    @Test("bookmark thumbnail decode options always include a max pixel size")
    func thumbnailOptionsIncludeMaxPixelSize() {
        let options = BookmarkThumbnailDecodePolicy.thumbnailOptions(maxPixelSize: 512) as NSDictionary

        #expect(options[kCGImageSourceCreateThumbnailFromImageAlways] as? Bool == true)
        #expect(options[kCGImageSourceShouldCacheImmediately] as? Bool == true)
        #expect(options[kCGImageSourceCreateThumbnailWithTransform] as? Bool == true)
        #expect(options[kCGImageSourceThumbnailMaxPixelSize] as? CGFloat == 512)
    }

    @Test("thumbnail cache does not reuse an image that is too small for the next request")
    @MainActor
    func thumbnailCacheRequiresSufficientPixelSize() {
        let image = NSImage(size: NSSize(width: 160, height: 160))
        BookmarkThumbnailCache.shared.set(image, for: "/tmp/thumb-cache-size.png", modifiedAt: 1)

        #expect(
            BookmarkThumbnailCache.shared.get(
                "/tmp/thumb-cache-size.png",
                modifiedAt: 1,
                minPixelSize: 512
            ) == nil
        )
    }
}
