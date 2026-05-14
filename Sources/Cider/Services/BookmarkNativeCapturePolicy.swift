import Foundation

enum BookmarkNativeCapturePolicy {
    static func allowsScreenshotFallback(thumbnailURL: URL?) -> Bool {
        thumbnailURL == nil
    }
}
