import SwiftUI

struct ItemMetadataToggleButton: View {
    @Binding var isVisible: Bool
    var helpVisible: String = "Hide metadata"
    var helpHidden: String = "Show metadata"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                isVisible.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                .overlay {
                    Image(systemName: isVisible ? "info.circle.fill" : "info.circle")
                        .font(CiderFont.toolbarIcon)
                        .foregroundColor(isVisible ? CiderColors.controlAccent : CiderColors.secondary)
                }
        }
        .buttonStyle(.plain)
        .help(isVisible ? helpVisible : helpHidden)
    }
}

struct ItemMetadataInspectorView<Content: View>: View {
    var width: CGFloat = BookmarksDesign.detailsSidebarFixedWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
        }
    }
}

struct ItemMetadataSectionView<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text(title)
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
            }
        }
        .padding(.vertical, Spacing.md)
    }
}

struct ItemMetadataRowsView: View {
    let rows: [ItemMetadataRow]
    var onOpenRef: ((LibraryEntityRef) -> Void)?
    var canOpenRef: ((LibraryEntityRef) -> Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(rows) { row in
                if let ref = row.ref,
                   let onOpenRef,
                   canOpenRef?(ref) ?? true {
                    Button {
                        onOpenRef(ref)
                    } label: {
                        metadataRow(row)
                    }
                    .buttonStyle(.plain)
                } else {
                    metadataRow(row)
                }
            }
        }
    }

    private func metadataRow(_ row: ItemMetadataRow) -> some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: row.symbol)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.md)

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(row.title)
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
                if !row.value.isEmpty {
                    Text(row.value)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}
