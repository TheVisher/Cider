import SwiftUI

struct ContinueSectionView: View {
    let items: [LibraryItem]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void
    var dragProviderForItem: ((LibraryItem) -> (() -> NSItemProvider)?)? = nil

    /// Threshold below which we hide the right column.
    /// Set high enough that the sidebar hiding (~200pt freed) doesn't push
    /// the content area above this threshold, preventing column flicker.
    private static let compactWidthThreshold: CGFloat = 700

    private var leftItems: [LibraryItem] {
        Array(items.prefix(4))
    }

    private var rightItems: [LibraryItem] {
        Array(items.dropFirst(4).prefix(4))
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < Self.compactWidthThreshold

            if isCompact {
                VStack(spacing: 0) {
                    ForEach(leftItems) { item in
                        makeRow(item)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(leftItems) { item in
                            makeRow(item)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    if !rightItems.isEmpty {
                        Divider()
                            .background(CiderColors.separator)
                            .padding(.vertical, Spacing.xs)

                        VStack(spacing: 0) {
                            ForEach(rightItems) { item in
                                makeRow(item)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(height: rowHeight * CGFloat(min(leftItems.count, 4)))
    }

    private var rowHeight: CGFloat { 32 }

    // MARK: - Row

    private func makeRow(_ item: LibraryItem) -> some View {
        ContinueRow(
            item: item,
            rowHeight: rowHeight,
            onOpen: {
                switch item {
                case .bookmark(let bookmark):
                    onOpenBookmark(bookmark)
                case .note(let note):
                    onOpenNote(note)
                }
            },
            dragProvider: dragProviderForItem?(item)
        )
    }
}

// MARK: - ContinueRow

private struct ContinueRow: View {
    let item: LibraryItem
    let rowHeight: CGFloat
    let onOpen: () -> Void
    var dragProvider: (() -> NSItemProvider)?

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: item.iconName)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 16)

                Text(item.title)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                if case .bookmark(let bookmark) = item {
                    Text(bookmark.hostDisplay)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Text(item.date.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .frame(height: rowHeight)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isHovered ? CiderColors.surfaceHover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverState($isHovered, animation: .snappy)
        .ciderDraggable(dragProvider) {
            Text(item.title)
                .font(CiderFont.labelMedium)
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceElevated)
                )
        }
    }
}

// MARK: - LibraryItem Helpers

extension LibraryItem {
    var iconName: String {
        switch self {
        case .bookmark:
            "bookmark"
        case .note:
            "note.text"
        }
    }
}
