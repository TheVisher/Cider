import SwiftUI

struct FolderKanbanView: View {
    let folderID: UUID
    let items: [LibraryItemV2]
    var onOpen: ((LibraryItemV2) -> Void)?

    @ObservedObject private var storage = FolderKanbanStorage.shared
    @State private var searchText = ""
    @State private var compactCards = false
    @State private var renamingColumnID: String?
    @State private var columnNameDraft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: [FolderKanbanColumn] {
        storage.columns(for: folderID)
    }

    private var itemsByID: [String: LibraryItemV2] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    /// Items not assigned to any column.
    private var uncategorizedItems: [LibraryItemV2] {
        let assigned = storage.assignedItemIDs(for: folderID)
        return items.filter { !assigned.contains($0.id) }
    }

    /// Filter items by search text.
    private func matchesSearch(_ item: LibraryItemV2) -> Bool {
        guard !searchText.isEmpty else { return true }
        return item.title.localizedStandardContains(searchText)
    }

    /// Resolve column item IDs to actual items, applying search filter.
    private func resolvedItems(for column: FolderKanbanColumn) -> [LibraryItemV2] {
        column.itemIDs.compactMap { itemsByID[$0] }.filter { matchesSearch($0) }
    }

    private var filteredUncategorized: [LibraryItemV2] {
        uncategorizedItems.filter { matchesSearch($0) }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            kanbanToolbar
            columnsArea
        }
        .task(id: items.map(\.id)) {
            // Prune stale item refs when folder contents change
            storage.pruneStaleItems(folderID: folderID, validItemIDs: Set(items.map(\.id)))
        }
    }

    // MARK: - Toolbar

    private var kanbanToolbar: some View {
        HStack(spacing: Spacing.sm) {
            Spacer()

            // Search field
            HStack(spacing: Spacing.xxs) {
                Image(systemName: "magnifyingglass")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                TextField("Filter cards...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(CiderFont.caption)
                    .frame(width: 100)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )

            // Compact toggle
            Button {
                withAnimation(reduceMotion ? .none : .spring) {
                    compactCards.toggle()
                }
            } label: {
                Image(systemName: compactCards ? "list.bullet" : "rectangle.grid.1x2")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .help(compactCards ? "Expanded view" : "Compact view")

            // Add column
            Button {
                withAnimation(reduceMotion ? .none : .spring) {
                    let col = storage.addColumn(folderID: folderID, name: "New Column")
                    renamingColumnID = col.id
                    columnNameDraft = col.name
                }
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: "plus")
                    Text("Column")
                }
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.controlAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.md + Spacing.xxs)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Columns Area

    private var columnsArea: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(columns) { column in
                    columnView(column)
                }

                // Uncategorized column (always last, if items exist)
                if !filteredUncategorized.isEmpty {
                    uncategorizedColumn
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Column

    /// Prefix to distinguish column drags from card drags.
    private static let columnDragPrefix = "col:"

    private func columnView(_ column: FolderKanbanColumn) -> some View {
        let columnItems = resolvedItems(for: column)
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            columnHeader(column, count: columnItems.count)
                .draggable("\(Self.columnDragPrefix)\(column.id)") {
                    Text(column.name)
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.primary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(CiderColors.surfaceElevated)
                        )
                }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(columnItems) { item in
                        cardView(item)
                            .draggable(item.id) {
                                cardDragPreview(item)
                            }
                            .dropDestination(for: String.self) { droppedIDs, _ in
                                guard let itemID = droppedIDs.first, itemID != item.id else { return false }
                                // Ignore column drags on card drop targets
                                guard !itemID.hasPrefix(Self.columnDragPrefix) else { return false }
                                let targetIndex = column.itemIDs.firstIndex(of: item.id) ?? column.itemIDs.count
                                withAnimation(reduceMotion ? .none : .spring) {
                                    storage.moveItem(folderID: folderID, itemID: itemID, toColumnID: column.id, toIndex: targetIndex)
                                }
                                return true
                            }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let dragID = droppedIDs.first else { return false }
            if dragID.hasPrefix(Self.columnDragPrefix) {
                // Column reorder
                let colID = String(dragID.dropFirst(Self.columnDragPrefix.count))
                guard colID != column.id else { return false }
                let targetIndex = columns.firstIndex(where: { $0.id == column.id }) ?? columns.count
                withAnimation(reduceMotion ? .none : .spring) {
                    storage.moveColumn(folderID: folderID, columnID: colID, toIndex: targetIndex)
                }
                return true
            } else {
                // Card drop
                withAnimation(reduceMotion ? .none : .spring) {
                    storage.moveItem(folderID: folderID, itemID: dragID, toColumnID: column.id, toIndex: column.itemIDs.count)
                }
                return true
            }
        }
    }

    private func columnHeader(_ column: FolderKanbanColumn, count: Int) -> some View {
        HStack(spacing: Spacing.xs) {
            if renamingColumnID == column.id {
                TextField("Column name", text: $columnNameDraft)
                    .textFieldStyle(.plain)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.primary)
                    .onSubmit {
                        let trimmed = columnNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            storage.renameColumn(folderID: folderID, columnID: column.id, name: trimmed)
                        }
                        renamingColumnID = nil
                    }
            } else {
                Text(column.name)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.primary)
                    .onTapGesture(count: 2) {
                        columnNameDraft = column.name
                        renamingColumnID = column.id
                    }
            }

            Spacer()

            Text("\(count)")
                .font(CiderFont.micro)
                .foregroundColor(CiderColors.tertiary)

            Menu {
                Button {
                    columnNameDraft = column.name
                    renamingColumnID = column.id
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Divider()
                Button(role: .destructive) {
                    withAnimation(reduceMotion ? .none : .spring) {
                        storage.deleteColumn(folderID: folderID, columnID: column.id)
                    }
                } label: {
                    Label("Delete Column", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Uncategorized Column

    private var uncategorizedColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Text("Uncategorized")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                Spacer()
                Text("\(filteredUncategorized.count)")
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xs)

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(filteredUncategorized) { item in
                        cardView(item)
                            .draggable(item.id) {
                                cardDragPreview(item)
                            }
                    }
                }
            }
        }
        .padding(Spacing.sm)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle.opacity(0.5))
        )
    }

    // MARK: - Card

    private func cardView(_ item: LibraryItemV2) -> some View {
        Button {
            onOpen?(item)
        } label: {
            VStack(alignment: .leading, spacing: compactCards ? Spacing.xxs : Spacing.xs) {
                Text(item.title)
                    .font(compactCards ? CiderFont.caption : CiderFont.label)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(compactCards ? 1 : 2)
                    .multilineTextAlignment(.leading)

                if !compactCards {
                    cardSubtitle(item)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func cardDragPreview(_ item: LibraryItemV2) -> some View {
        Text(item.title)
            .font(CiderFont.label)
            .foregroundColor(CiderColors.primary)
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceElevated)
            )
    }

    @ViewBuilder
    private func cardSubtitle(_ item: LibraryItemV2) -> some View {
        switch item {
        case .bookmark(let bookmark):
            Text(bookmark.hostDisplay)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
        case .note(let note):
            if !note.contentPreview.isEmpty {
                Text(note.contentPreview)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
        case .dateCard(let dateCard):
            HStack(spacing: Spacing.xxs) {
                if dateCard.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(CiderColors.controlAccent)
                }
                Text(dateCard.startAt, style: .date)
                    .foregroundColor(CiderColors.tertiary)
            }
            .font(CiderFont.caption)
        case .todo(let todo):
            HStack(spacing: Spacing.xxs) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? CiderColors.controlAccent : CiderColors.tertiary)
                if let dueDate = todo.dueDate {
                    Text(dueDate, style: .date)
                        .foregroundColor(CiderColors.tertiary)
                }
            }
            .font(CiderFont.caption)
        case .contact(let contact):
            if !contact.displayName.isEmpty {
                Text(contact.displayName)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }
        case .vaultFile(let file):
            Text(file.filename)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
        }
    }
}
