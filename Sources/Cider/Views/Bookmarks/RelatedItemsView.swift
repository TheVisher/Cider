import SwiftUI

/// Shows up to 3 semantically similar bookmarks below the detail panel's AI section.
struct RelatedItemsView: View {
    let bookmarkID: UUID

    @Environment(\.textScale) private var textScale
    @State private var relatedBookmarks: [Bookmark] = []

    var body: some View {
        Group {
            if !relatedBookmarks.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(relatedBookmarks) { bookmark in
                        RelatedItemRow(bookmark: bookmark, textScale: textScale)
                    }
                }
            }
        }
        .task(id: bookmarkID) {
            recompute()
        }
    }

    private func recompute() {
        let ids = SimilarItemsService.findSimilar(
            to: bookmarkID,
            in: EmbeddingStore.shared,
            excluding: [bookmarkID],
            limit: 3
        )
        let allBookmarks = BookmarksStorage.shared.bookmarks
        relatedBookmarks = ids.compactMap { id in allBookmarks.first { $0.id == id } }
    }
}

// MARK: - Row

private struct RelatedItemRow: View {
    let bookmark: Bookmark
    let textScale: Double

    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .openBookmarkDetails,
                object: nil,
                userInfo: ["bookmarkID": bookmark.id]
            )
        } label: {
            HStack(spacing: Spacing.sm) {
                BookmarkThumbnailView(bookmark: bookmark, mode: .list)
                    .frame(width: 32, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .font(CiderFont.bodyMedium(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    if !bookmark.hostDisplay.isEmpty {
                        Text(bookmark.hostDisplay)
                            .font(CiderFont.caption(scale: textScale))
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isHovered ? CiderColors.surfaceHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
