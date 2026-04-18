import AppKit

/// Shared in-process cache for bookmark thumbnail images.
/// Prevents re-decoding the same JPEG/PNG from disk every time a card,
/// table row, detail hero, or carousel page appears.
@MainActor
final class BookmarkThumbnailCache {
    static let shared = BookmarkThumbnailCache()

    struct CachedThumbnail {
        let image: NSImage
        let aspectRatio: CGFloat?
        let isIconOverlay: Bool
    }

    private final class Box: NSObject {
        let value: CachedThumbnail

        init(_ value: CachedThumbnail) {
            self.value = value
        }
    }

    private let cache = NSCache<NSString, Box>()

    init() { cache.countLimit = 300 }

    /// Cache key combines the file path and modification timestamp so stale
    /// entries auto-invalidate when the thumbnail file changes on disk.
    func get(_ filePath: String, modifiedAt: TimeInterval) -> CachedThumbnail? {
        let key = "\(filePath):\(modifiedAt)" as NSString
        return cache.object(forKey: key)?.value
    }

    func aspectRatio(for filePath: String, modifiedAt: TimeInterval) -> CGFloat? {
        get(filePath, modifiedAt: modifiedAt)?.aspectRatio
    }

    func set(_ image: NSImage, for filePath: String, modifiedAt: TimeInterval) {
        set(
            CachedThumbnail(
                image: image,
                aspectRatio: nil,
                isIconOverlay: false
            ),
            for: filePath,
            modifiedAt: modifiedAt
        )
    }

    func set(_ thumbnail: CachedThumbnail, for filePath: String, modifiedAt: TimeInterval) {
        let key = "\(filePath):\(modifiedAt)" as NSString
        cache.setObject(Box(thumbnail), forKey: key)
    }
}
