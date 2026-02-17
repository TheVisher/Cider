import AppKit
import SwiftUI

struct BookmarkListRow: View {
    let bookmark: Bookmark
    var searchText: String
    let cardSizing: CardSizing
    var folders: [Folder] = []
    var dragProvider: (() -> NSItemProvider)? = nil
    let onShowDetails: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: ((UUID?) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button(action: onShowDetails) {
                BookmarkThumbnailView(bookmark: bookmark, mode: .list)
                    .frame(width: cardSizing.listThumbnailWidth, height: cardSizing.listThumbnailHeight)
            }
            .buttonStyle(.plain)
            .help("Show bookmark details")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button(action: onOpen) {
                    HighlightedText(bookmark.title, highlight: searchText)
                        .font(CiderFont.labelSemibold(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button(action: onOpen) {
                    HStack(spacing: Spacing.xs) {
                        Text(bookmark.hostDisplay)
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.secondary)
                            .lineLimit(1)

                        Text("\u{2022}")
                            .font(CiderFont.captionSemibold(scale: textScale))
                            .foregroundColor(CiderColors.tertiary)

                        Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                            .font(CiderFont.body(scale: textScale))
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(CiderFont.bodySemibold(scale: textScale))
                        .foregroundColor(CiderColors.destructive)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.destructiveLight)
                )
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, cardSizing.isExtraLarge ? Spacing.sm : Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isHovered ? CiderColors.surfaceInput : Color.clear)
        )
        .hoverState($isHovered, animation: .snappy)
        .bookmarkContextMenu(
            bookmark: bookmark,
            folders: folders,
            onOpen: onOpen,
            onShowDetails: onShowDetails,
            onMoveToFolder: { folderID in onMoveToFolder?(folderID) },
            onDelete: onDelete
        )
        .bookmarkDraggable(dragProvider) {
            BookmarkDragPreview(bookmark: bookmark)
        }
    }
}
