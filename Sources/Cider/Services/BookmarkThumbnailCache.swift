import AppKit

/// Shared in-process cache for bookmark thumbnail images.
/// Prevents re-decoding the same JPEG/PNG from disk every time a card,
/// table row, detail hero, or carousel page appears.
@MainActor
final class BookmarkThumbnailCache {
    static let shared = BookmarkThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    init() { cache.countLimit = 300 }

    /// Cache key combines the file path and modification timestamp so stale
    /// entries auto-invalidate when the thumbnail file changes on disk.
    func get(_ filePath: String, modifiedAt: TimeInterval) -> NSImage? {
        let key = "\(filePath):\(modifiedAt)" as NSString
        return cache.object(forKey: key)
    }

    func set(_ image: NSImage, for filePath: String, modifiedAt: TimeInterval) {
        let key = "\(filePath):\(modifiedAt)" as NSString
        cache.setObject(image, forKey: key)
    }
}
