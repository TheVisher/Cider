import Foundation

enum BookmarkNativeCapturePolicy {
    static func allowsThumbnailReplacement(
        hasUsableLocalThumbnail: Bool,
        isExplicitUserRefresh: Bool = false
    ) -> Bool {
        isExplicitUserRefresh || !hasUsableLocalThumbnail
    }

    static func allowsScreenshotFallback(
        thumbnailURL: URL?,
        hasUsableLocalThumbnail: Bool = false,
        isExplicitUserRefresh: Bool = false
    ) -> Bool {
        thumbnailURL == nil
            && allowsThumbnailReplacement(
                hasUsableLocalThumbnail: hasUsableLocalThumbnail,
                isExplicitUserRefresh: isExplicitUserRefresh
            )
    }
}
