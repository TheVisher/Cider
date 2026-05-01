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
        ItemMetadataPanel(width: width, content: content) {
            EmptyView()
        }
    }
}

struct ItemMetadataPanel<Content: View, Footer: View>: View {
    var width: CGFloat = BookmarksDesign.detailsSidebarFixedWidth
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: .infinity)

            footer()
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

struct ItemMetadataDivider: View {
    var body: some View {
        Divider()
            .background(CiderColors.separator)
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

struct ItemMetadataEmptyText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CiderFont.body)
            .foregroundColor(CiderColors.quaternary)
            .fixedSize(horizontal: false, vertical: true)
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

struct ItemMetadataActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @Environment(\.textScale) private var textScale

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(CiderFont.bodyMedium(scale: textScale))
                .foregroundColor(CiderColors.secondary)
                .frame(minHeight: BookmarksDesign.buttonTapTarget)
                .padding(.horizontal, Spacing.sm)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }
}

struct ItemMetadataFolderPicker: View {
    var folderID: UUID?
    var folders: [Folder] = VaultFolderService.shared.legacyFolders
    var onFolderChanged: (UUID?) -> Void

    @Environment(\.textScale) private var textScale

    var body: some View {
        Menu {
            Button("No Folder") {
                onFolderChanged(nil)
            }
            if !folders.isEmpty { Divider() }
            ForEach(folders) { folder in
                Button(folder.name) {
                    onFolderChanged(folder.id)
                }
            }
        } label: {
            HStack {
                Label(currentFolderName, systemImage: "folder")
                    .font(CiderFont.body(scale: textScale))
                    .foregroundColor(CiderColors.secondary)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(CiderFont.caption(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: BookmarksDesign.buttonTapTarget)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private var currentFolderName: String {
        guard let folderID else { return "No Folder" }
        return folders.first(where: { $0.id == folderID })?.name ?? "No Folder"
    }
}

struct ItemMetadataTagsPicker: View {
    var labelIDs: [UUID]
    var onToggleLabel: (UUID) -> Void
    var onCreateAndAssignLabel: () -> Void

    @ObservedObject private var labelStorage = CardLabelStorage.shared
    @Environment(\.textScale) private var textScale

    var body: some View {
        TagFlowLayout(spacing: Spacing.xs) {
            ForEach(assignedLabels) { label in
                TagPillView(
                    label: label,
                    onRemove: { onToggleLabel(label.id) }
                )
            }

            Menu {
                if unassignedLabels.isEmpty && labelStorage.labels.isEmpty {
                    Button("New Tag...", action: onCreateAndAssignLabel)
                } else {
                    ForEach(unassignedLabels) { label in
                        Button {
                            onToggleLabel(label.id)
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                                    .frame(width: BookmarksDesign.tagColorDotSize, height: BookmarksDesign.tagColorDotSize)
                                Text(label.name)
                            }
                        }
                    }

                    Divider()

                    Button("New Tag...", action: onCreateAndAssignLabel)
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "plus")
                        .font(CiderFont.badgeSemibold)
                    Text("Add Tag")
                        .font(CiderFont.caption(scale: textScale))
                }
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.accentSubtle)
                )
            }
            .menuStyle(.borderlessButton)
        }
    }

    private var assignedLabels: [CardLabel] {
        labelIDs.compactMap { id in
            labelStorage.labels.first(where: { $0.id == id })
        }
    }

    private var unassignedLabels: [CardLabel] {
        let assigned = Set(labelIDs)
        return labelStorage.labels.filter { !assigned.contains($0.id) }
    }
}

struct ItemMetadataLinkedSection: View {
    var rows: [ItemMetadataRow]
    @Binding var isExpanded: Bool
    var onOpenLinkedRef: ((LibraryEntityRef) -> Void)?
    var canOpenLinkedRef: ((LibraryEntityRef) -> Bool)?

    var body: some View {
        ItemMetadataSectionView(title: "Linked", isExpanded: $isExpanded) {
            if rows.isEmpty {
                ItemMetadataEmptyText(text: "No linked items.")
            } else {
                ItemMetadataRowsView(
                    rows: rows,
                    onOpenRef: onOpenLinkedRef,
                    canOpenRef: canOpenLinkedRef
                )
            }
        }
    }
}

struct ItemMetadataInfoFooter: View {
    var rows: [ItemMetadataRow]
    var onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isInfoExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ItemMetadataDivider()

            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isInfoExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("Info")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.tertiary)
                        .rotationEffect(.degrees(isInfoExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isInfoExpanded {
                ItemMetadataPropertyRows(rows: rows)
                    .padding(.bottom, Spacing.xxs)
            }

            if let onDelete {
                ItemMetadataDivider()

                Button("Delete", action: onDelete)
                    .buttonStyle(CiderDestructiveButtonStyle())
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(Spacing.md)
    }
}

struct ItemMetadataPropertyRows: View {
    let rows: [ItemMetadataRow]

    @Environment(\.textScale) private var textScale

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: Spacing.xs) {
                    Text(row.title)
                        .font(CiderFont.caption(scale: textScale))
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(width: BookmarksDesign.propertyLabelWidth, alignment: .leading)
                    Text(row.value)
                        .font(CiderFont.caption(scale: textScale))
                        .foregroundColor(CiderColors.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
