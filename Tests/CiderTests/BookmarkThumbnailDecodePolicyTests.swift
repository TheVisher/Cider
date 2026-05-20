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

    @Test("large product thumbnails are not rendered as icon overlays even when the URL contains touch-icon")
    func largeTouchIconURLImageDoesNotUseIconOverlay() {
        let rendersAsIcon = BookmarkThumbnailView.shouldRenderAsIconOverlay(
            width: 575,
            height: 720,
            remoteURLString: "https://www.vans.com/touch-icon-iphone.png?v=2"
        )

        #expect(rendersAsIcon == false)
    }

    @Test("small square icon thumbnails still render as icon overlays")
    func smallSquareImageUsesIconOverlay() {
        let rendersAsIcon = BookmarkThumbnailView.shouldRenderAsIconOverlay(
            width: 64,
            height: 64,
            remoteURLString: "https://example.com/image.png"
        )

        #expect(rendersAsIcon == true)
    }

    @Test("small favicon URL thumbnails render as icon overlays")
    func smallFaviconURLImageUsesIconOverlay() {
        let rendersAsIcon = BookmarkThumbnailView.shouldRenderAsIconOverlay(
            width: 128,
            height: 128,
            remoteURLString: "https://example.com/favicon.png"
        )

        #expect(rendersAsIcon == true)
    }

    @Test("thumbnail cache stamp falls back to file modification time when bookmark metadata timestamp is missing")
    func thumbnailCacheStampUsesFileModificationTimeWhenMetadataIsMissing() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4e, 0x47]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let modifiedAt = Date(timeIntervalSince1970: 1_779_309_749)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: tempURL.path)

        let stamp = BookmarkThumbnailView.thumbnailCacheModifiedAt(
            fileURL: tempURL,
            metadataUpdatedAt: nil
        )

        #expect(abs(stamp - modifiedAt.timeIntervalSince1970) < 0.001)
    }
}
