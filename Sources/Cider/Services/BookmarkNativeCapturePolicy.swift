import Foundation

enum BookmarkNativeCapturePolicy {
    static func allowsScreenshotFallback(
        thumbnailURL: URL?,
        hasUsableLocalThumbnail: Bool = false
    ) -> Bool {
        thumbnailURL == nil && !hasUsableLocalThumbnail
    }
}
