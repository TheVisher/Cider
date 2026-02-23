import SwiftUI

struct ContinueSectionView: View {
    let items: [LibraryItemV2]
    let onOpen: (LibraryItemV2) -> Void
    var dragProviderForItem: ((LibraryItemV2) -> (() -> NSItemProvider)?)? = nil

    /// Threshold below which we hide the right column.
    /// Set high enough that the sidebar hiding (~200pt freed) doesn't push
    /// the content area above this threshold, preventing column flicker.
    private static let compactWidthThreshold: CGFloat = 700

    private var leftItems: [LibraryItemV2] {
        Array(items.prefix(4))
    }

    private var rightItems: [LibraryItemV2] {
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

    private func makeRow(_ item: LibraryItemV2) -> some View {
        ContinueRow(
            item: item,
            rowHeight: rowHeight,
            onOpen: { onOpen(item) },
            dragProvider: dragProviderForItem?(item)
        )
    }
}

// MARK: - ContinueRow

private struct ContinueRow: View {
    let item: LibraryItemV2
    let rowHeight: CGFloat
    let onOpen: () -> Void
    var dragProvider: (() -> NSItemProvider)?

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: item.iconName)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(item.iconColor)
                    .frame(width: 16)

                Text(item.title)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                item.subtitleView

                Text(item.updatedDate.formatted(.relative(presentation: .named)))
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

// MARK: - LibraryItemV2 Continue Helpers

extension LibraryItemV2 {
    var iconName: String {
        switch self {
        case .bookmark: "bookmark"
        case .note: "note.text"
        case .dateCard(let dc): dc.isCompleted ? "checkmark.circle.fill" : "calendar"
        case .contact: "person.crop.circle"
        case .externalFile: "folder.badge.gear"
        }
    }

    var iconColor: Color {
        switch self {
        case .bookmark, .note, .externalFile: CiderColors.tertiary
        case .dateCard(let dc): dc.isCompleted ? CiderColors.controlAccent : CiderColors.tertiary
        case .contact: CiderColors.controlAccent
        }
    }

    @ViewBuilder
    var subtitleView: some View {
        switch self {
        case .bookmark(let b):
            if b.hasURL {
                Text(b.hostDisplay)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            } else {
                Text(b.updatedAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }
        case .dateCard(let dc):
            Text(dc.allDay ? dc.startAt.formatted(.dateTime.month(.abbreviated).day()) :
                 dc.startAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
        case .contact(let c) where !c.relationshipLabel.isEmpty:
            Text(c.relationshipLabel)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
        default:
            EmptyView()
        }
    }
}
