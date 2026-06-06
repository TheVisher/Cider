import Foundation
import Testing
@testable import Cider

struct BookmarkNativeCapturePolicyTests {
    @Test("screenshots are only fallback when no provider thumbnail exists")
    func screenshotsAreOnlyLastResort() {
        let providerThumbnail = URL(string: "https://example.com/thumb.jpg")!

        #expect(BookmarkNativeCapturePolicy.allowsScreenshotFallback(thumbnailURL: nil))
        #expect(!BookmarkNativeCapturePolicy.allowsScreenshotFallback(thumbnailURL: providerThumbnail))
    }

    @Test("screenshots do not replace an existing usable local thumbnail")
    func screenshotsDoNotReplaceExistingLocalThumbnail() {
        #expect(!BookmarkNativeCapturePolicy.allowsScreenshotFallback(
            thumbnailURL: nil,
            hasUsableLocalThumbnail: true
        ))
    }
}
