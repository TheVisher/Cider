import AppKit

/// Shared in-process cache for bookmark thumbnail images.
/// Prevents re-decoding the same JPEG/PNG from disk every time a card,
/// table row, detail hero, or carousel page appears.
@MainActor
final class BookmarkThumbnailCache {
    static let shared = BookmarkThumbnailCache()
    static let defaultCountLimit = 120
    static let defaultTotalCostLimit = 160 * 1_024 * 1_024

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

    init() {
        cache.countLimit = Self.defaultCountLimit
        cache.totalCostLimit = Self.defaultTotalCostLimit
    }

    /// Cache key combines the file path and modification timestamp so stale
    /// entries auto-invalidate when the thumbnail file changes on disk.
    func get(
        _ filePath: String,
        modifiedAt: TimeInterval,
        minPixelSize: CGFloat? = nil
    ) -> CachedThumbnail? {
        let key = "\(filePath):\(modifiedAt)" as NSString
        guard let cached = cache.object(forKey: key)?.value else { return nil }
        guard let minPixelSize else { return cached }

        let largestDimension = CGFloat(max(Self.pixelWidth(for: cached.image), Self.pixelHeight(for: cached.image)))
        return largestDimension + 0.5 >= minPixelSize ? cached : nil
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
        cache.setObject(
            Box(thumbnail),
            forKey: key,
            cost: Self.memoryCost(for: thumbnail.image)
        )
    }

    nonisolated static func memoryCost(for image: NSImage) -> Int {
        let width = pixelWidth(for: image)
        let height = pixelHeight(for: image)
        return width * height * 4
    }

    nonisolated private static func pixelWidth(for image: NSImage) -> Int {
        if let representation = image.representations.first {
            return max(representation.pixelsWide, 1)
        }

        return max(Int(image.size.width.rounded(.up)), 1)
    }

    nonisolated private static func pixelHeight(for image: NSImage) -> Int {
        if let representation = image.representations.first {
            return max(representation.pixelsHigh, 1)
        }

        return max(Int(image.size.height.rounded(.up)), 1)
    }
}
