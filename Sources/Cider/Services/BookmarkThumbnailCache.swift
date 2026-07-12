import AppKit
import Combine
import Foundation
import ImageIO

struct AgentRoomsBookmarkThumbnailReference: Equatable, Sendable {
    let bookmarkID: UUID
    let relativePath: String
    let modifiedAt: TimeInterval
}

@MainActor
enum AgentRoomsBookmarkReceiptThumbnail {
    private static let thumbnailDirectoryName = ".thumbnails"

    static func reference(
        for bookmark: Bookmark,
        cacheRoot: URL = StoragePaths.cachedDirectoryURL(for: .bookmarks)
    ) -> AgentRoomsBookmarkThumbnailReference? {
        guard let relativePath = bookmark.thumbnailRelativePath,
              let fileURL = canonicalFileURL(
                relativePath: relativePath,
                bookmarkID: bookmark.id,
                cacheRoot: cacheRoot
              ),
              let modifiedAt = localFileModifiedAt(fileURL)
        else { return nil }

        return AgentRoomsBookmarkThumbnailReference(
            bookmarkID: bookmark.id,
            relativePath: relativePath,
            modifiedAt: modifiedAt
        )
    }

    static func load(
        _ reference: AgentRoomsBookmarkThumbnailReference,
        expectedBookmarkID: UUID,
        cacheRoot: URL = StoragePaths.cachedDirectoryURL(for: .bookmarks)
    ) async -> NSImage? {
        guard reference.bookmarkID == expectedBookmarkID,
              let fileURL = canonicalFileURL(
                relativePath: reference.relativePath,
                bookmarkID: expectedBookmarkID,
                cacheRoot: cacheRoot
              ),
              let currentModifiedAt = localFileModifiedAt(fileURL),
              abs(currentModifiedAt - reference.modifiedAt) < 0.001
        else { return nil }

        let cacheKey = fileURL.path + ":rooms-receipt"
        if let cached = BookmarkThumbnailCache.shared.get(
            cacheKey,
            modifiedAt: reference.modifiedAt
        ) {
            return cached.image
        }

        let image: NSImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    BookmarkThumbnailDecodePolicy.thumbnailOptions(
                        maxPixelSize: BookmarkThumbnailDecodePolicy.listMaxPixelSize
                    )
                  ),
                  cgImage.width > 0,
                  cgImage.height > 0
            else { return nil }

            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
        }.value

        guard !Task.isCancelled,
              let image,
              let decodedModifiedAt = localFileModifiedAt(fileURL),
              abs(decodedModifiedAt - reference.modifiedAt) < 0.001
        else { return nil }
        BookmarkThumbnailCache.shared.set(
            image,
            for: cacheKey,
            modifiedAt: reference.modifiedAt
        )
        return image
    }

    private static func canonicalFileURL(
        relativePath: String,
        bookmarkID: UUID,
        cacheRoot: URL
    ) -> URL? {
        let path = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = NSString(string: path).pathComponents
        guard components.count == 2,
              components[0] == thumbnailDirectoryName,
              !components[1].isEmpty,
              NSString(string: components[1]).deletingPathExtension == bookmarkID.uuidString,
              !NSString(string: components[1]).pathExtension.isEmpty
        else { return nil }

        let fileURL = cacheRoot.appendingPathComponent(path)
        guard FileContainment.isContained(fileURL, in: cacheRoot),
              FileManager.default.isReadableFile(atPath: fileURL.path),
              let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              (values.fileSize ?? 0) > 0
        else { return nil }
        return fileURL
    }

    private static func localFileModifiedAt(_ fileURL: URL) -> TimeInterval? {
        try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate?
            .timeIntervalSince1970
    }
}

@MainActor
final class AgentRoomsBookmarkReceiptThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private let cacheRoot: URL

    init(cacheRoot: URL = StoragePaths.cachedDirectoryURL(for: .bookmarks)) {
        self.cacheRoot = cacheRoot
    }

    func load(
        _ reference: AgentRoomsBookmarkThumbnailReference,
        expectedBookmarkID: UUID
    ) async {
        image = nil
        image = await AgentRoomsBookmarkReceiptThumbnail.load(
            reference,
            expectedBookmarkID: expectedBookmarkID,
            cacheRoot: cacheRoot
        )
    }
}

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
