import CoreGraphics

@MainActor
enum LibraryItemMasonryMetrics {
    static func estimatedHeight(
        for item: LibraryItemV2,
        columnWidth: CGFloat,
        cardSizing: LibraryCardSizing
    ) -> CGFloat {
        switch item {
        case .journal:
            return max(132, columnWidth * 0.55)
        case .bookmark(let bookmark):
            let bookmarkSizing = cardSizing.bookmarkSizing
            let thumbnailHeight = estimatedBookmarkThumbnailHeight(
                for: bookmark,
                columnWidth: columnWidth,
                cardSizing: bookmarkSizing
            )
            let footerHeight: CGFloat = bookmark.labelIDs.isEmpty && bookmark.tags.isEmpty ? 76 : 104
            return thumbnailHeight + footerHeight + (Spacing.sm * 2)

        case .note:
            return cardSizing.notePreviewHeight + cardSizing.noteImageWidth + 112

        case .dateCard:
            return max(168, columnWidth * 0.68)

        case .contact:
            return max(160, columnWidth * 0.62)

        case .todo:
            return max(176, columnWidth * 0.7)

        case .vaultFile:
            return max(148, columnWidth * 0.75)
        }
    }

    private static func estimatedBookmarkThumbnailHeight(
        for bookmark: Bookmark,
        columnWidth: CGFloat,
        cardSizing: CardSizing
    ) -> CGFloat {
        guard
            let fileURL = bookmark.thumbnailFileURL,
            let aspectRatio = BookmarkThumbnailCache.shared.aspectRatio(
                for: fileURL.path,
                modifiedAt: bookmark.metadataUpdatedAt?.timeIntervalSince1970 ?? -1
            )
        else {
            return cardSizing.masonryThumbnailHeightFallback
        }

        let rawHeight = columnWidth * aspectRatio
        return min(
            max(rawHeight, cardSizing.masonryThumbnailHeightMin),
            cardSizing.masonryThumbnailHeightMax
        )
    }
}
