import Foundation

enum BookmarkNativeCapturePolicy {
    static func allowsAutomaticThumbnailReplacement(hasUsableLocalThumbnail: Bool) -> Bool {
        !hasUsableLocalThumbnail
    }

    static func allowsScreenshotFallback(
        thumbnailURL: URL?,
        hasUsableLocalThumbnail: Bool = false
    ) -> Bool {
        thumbnailURL == nil
            && allowsAutomaticThumbnailReplacement(hasUsableLocalThumbnail: hasUsableLocalThumbnail)
    }
}
