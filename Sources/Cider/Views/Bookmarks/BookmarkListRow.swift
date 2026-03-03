import AppKit
import SwiftUI

struct BookmarkListRow: View {
    let bookmark: Bookmark
    var searchText: String
    let cardSizing: CardSizing
    var folders: [Folder] = []
    var dragProvider: (() -> NSItemProvider)? = nil
    var dragPreviewOverride: AnyView? = nil
    let onShowDetails: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isSelected {
                SelectionCheckmark()
            }

            Button { handleClick(normalAction: onShowDetails) } label: {
                BookmarkThumbnailView(bookmark: bookmark, mode: .list)
                    .frame(width: cardSizing.listThumbnailWidth, height: cardSizing.listThumbnailHeight)
            }
            .buttonStyle(.plain)
            .help("Show bookmark details")

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Button { handleClick(normalAction: onOpen) } label: {
                    HighlightedText(bookmark.title, highlight: searchText)
                        .font(CiderFont.labelSemibold(scale: textScale))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button { handleClick(normalAction: onOpen) } label: {
                    HStack(spacing: Spacing.xs) {
                        if bookmark.hasURL {
                            Text(bookmark.hostDisplay)
                                .font(CiderFont.body(scale: textScale))
                                .foregroundColor(CiderColors.secondary)
                                .lineLimit(1)

                            Text("\u{2022}")
                                .font(CiderFont.captionSemibold(scale: textScale))
                                .foregroundColor(CiderColors.tertiary)
                        }

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
                .fill(
                    isSelected
                        ? CiderColors.selectedFill
                        : isHovered ? CiderColors.surfaceInput : Color.clear
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isFocused ? CiderColors.controlAccent : Color.clear, lineWidth: 1.5)
        )
        .hoverState($isHovered, animation: .snappy)
        .bookmarkContextMenu(
            bookmark: bookmark,
            folders: folders,
            onOpen: onOpen,
            onShowDetails: onShowDetails,
            onRefetchMetadata: { BookmarksStorage.shared.refetchMetadata(for: bookmark.id) },
            onMoveToFolder: { folderID in onMoveToFolder?(folderID) },
            onDelete: onDelete,
            onToggleLabel: { labelID in
                if bookmark.labelIDs.contains(labelID) {
                    _ = BookmarksStorage.shared.removeLabel(bookmark.id, labelID: labelID)
                } else {
                    _ = BookmarksStorage.shared.assignLabel(bookmark.id, labelID: labelID)
                }
            },
            isSelected: isSelected,
            onToggleLabelBulk: onToggleLabelBulk
        )
        .ciderDraggable(dragProvider) {
            if let preview = dragPreviewOverride {
                preview
            } else {
                BookmarkDragPreview(bookmark: bookmark)
            }
        }
    }
}
