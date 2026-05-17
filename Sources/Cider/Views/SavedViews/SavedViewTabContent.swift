import SwiftUI
import os

struct SavedViewTabContent: View {
    private static let logger = Logger(subsystem: "com.cider.app", category: "SavedViewTabContent")

    let savedView: SavedView
    @ObservedObject var libraryViewModel: LibraryViewModel
    var folders: [Folder] = []
    var onOpenBookmark: ((Bookmark) -> Void)? = nil
    var onOpenNote: ((Note) -> Void)? = nil
    var onDeleteBookmark: ((Bookmark) -> Void)? = nil
    var onDeleteNote: ((Note) -> Void)? = nil
    var onRenameNote: ((Note, String) -> Void)? = nil
    var onMoveBookmarkToFolder: ((Bookmark, UUID?) -> Void)? = nil
    var onMoveNoteToFolder: ((Note, UUID?) -> Void)? = nil
    var onOpenDateCard: ((DateCard) -> Void)? = nil
    var onOpenContact: ((ContactCard) -> Void)? = nil
    var onOpenTodo: ((TodoCard) -> Void)? = nil
    var onOpenVaultFile: ((VaultFile) -> Void)? = nil
    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared
    @ObservedObject private var labelStorage = CardLabelStorage.shared
    var searchText: String = ""
    var onUpdateSavedView: ((SavedView) -> Void)? = nil
    var onDeleteSavedView: ((UUID) -> Void)? = nil

    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var calendarMode: CalendarProjectionMode = .month
    @State private var calendarAnchorDate = Date()
    @State private var editorContext: DateCardEditorContext?
    @State private var contactEditorContext: ContactEditorContext?
    @State private var savedViewConfig = CiderConfig.load()
    @State private var tableColumnConfig: TableColumnConfig = CiderConfig.load().tableColumnConfig

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: savedView.layoutSpec.cardSizeScale)
    }

    private var effectiveFilterSpec: SavedViewFilterSpec {
        let sidebarQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if sidebarQuery.isEmpty {
            return savedView.filterSpec
        }
        // Combine sidebar search with any existing persistent textQuery
        var spec = savedView.filterSpec
        if spec.textQuery.isEmpty {
            spec.textQuery = sidebarQuery
        } else {
            spec.textQuery = spec.textQuery + " " + sidebarQuery
        }
        return spec
    }

    private var filteredItems: [LibraryItemV2] {
        libraryViewModel.filteredItems(
            using: effectiveFilterSpec,
            sort: savedView.sortSpec
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                headerRow
                filterChipsRow

                if savedView.layoutSpec.showsCalendarProjection {
                    calendarControlsRow
                    CalendarProjectionView(
                        items: filteredItems,
                        mode: calendarMode,
                        anchorDate: calendarAnchorDate,
                        showsGhostCells: savedView.layoutSpec.showsGhostCells,
                        onSelectDay: { day in
                            editorContext = DateCardEditorContext(existingCard: nil, defaultDate: day)
                        },
                        onSelectDateCard: { dateCard in
                            editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                        }
                    )
                } else {
                    listGridMasonryContent
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .scrollIndicators(.hidden)
        .sheet(item: $editorContext) { context in
            DateCardEditorSheet(
                existingCard: context.existingCard,
                defaultDate: context.defaultDate,
                onSave: { title, details, startAt, endAt, allDay, location, amount, actionURLString, labelIDs, recurrenceRule, rules in
                    LibraryItemEditor.saveDateCard(
                        existingCard: context.existingCard,
                        title: title,
                        details: details,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        location: location,
                        amount: amount,
                        actionURLString: actionURLString,
                        labelIDs: labelIDs,
                        recurrenceRule: recurrenceRule,
                        rules: rules
                    )
                },
                onDelete: { dateCard in
                    if let trashItem = dateCardStorage.deleteDateCard(dateCard.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                    }
                }
            )
        }
        .sheet(item: $contactEditorContext) { context in
            ContactEditorSheet(
                existingContact: context.existingContact,
                onSave: { draftContactID, displayName, relationshipLabel, birthday, notes, labelIDs, addBirthdayDateCard, email, phone, address, hasAvatar, customFields in
                    LibraryItemEditor.saveContact(
                        draftContactID: draftContactID,
                        existingContact: context.existingContact,
                        displayName: displayName,
                        relationshipLabel: relationshipLabel,
                        birthday: birthday,
                        notes: notes,
                        labelIDs: labelIDs,
                        addBirthdayDateCard: addBirthdayDateCard,
                        email: email,
                        phone: phone,
                        address: address,
                        hasAvatar: hasAvatar,
                        customFields: customFields
                    )
                },
                onDelete: { contact in
                    if let trashItem = contactStorage.deleteContact(contact.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                    }
                }
            )
        }
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: savedView.layoutSpec.showsCalendarProjection ? "calendar" : "line.3.horizontal.decrease.circle")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            if isRenaming {
                TextField("View name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
                    .onSubmit { commitRename() }
                    .frame(maxWidth: 220, alignment: .leading)
            } else {
                Text(savedView.name)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.secondary)
            }

            Text("\(filteredItems.count)")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.quaternary)

            Spacer(minLength: Spacing.xs)

            if isRenaming {
                Button {
                    commitRename()
                } label: {
                    Image(systemName: "checkmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                Button {
                    isRenaming = false
                    draftName = savedView.name
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    draftName = savedView.name
                    isRenaming = true
                } label: {
                    Image(systemName: "pencil")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Rename view")

                Button {
                    onDeleteSavedView?(savedView.id)
                } label: {
                    Image(systemName: "trash")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.destructive)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Delete view")

                Button {
                    toggleCalendarProjection()
                } label: {
                    Image(systemName: savedView.layoutSpec.showsCalendarProjection ? "list.bullet" : "calendar")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(savedView.layoutSpec.showsCalendarProjection ? "Show list view" : "Show calendar view")

                Button {
                    editorContext = DateCardEditorContext(existingCard: nil, defaultDate: calendarAnchorDate)
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Create date card")

                Button {
                    contactEditorContext = ContactEditorContext(existingContact: nil)
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help("Create contact card")

            }
        }
        .padding(.bottom, Spacing.xs)
        .onAppear {
            if draftName.isEmpty {
                draftName = savedView.name
            }
        }
    }

    private var calendarControlsRow: some View {
        HStack(spacing: Spacing.xs) {
            modeButton(.week, label: "Week")
            modeButton(.month, label: "Month")

            Spacer(minLength: Spacing.xs)

            Button {
                shiftCalendarAnchor(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Text(calendarHeaderTitle)
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.secondary)

            Button {
                shiftCalendarAnchor(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Button {
                calendarAnchorDate = Date()
            } label: {
                Text("Today")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)

            Button {
                toggleGhostCells()
            } label: {
                Image(systemName: savedView.layoutSpec.showsGhostCells ? "square.dashed" : "square")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help(savedView.layoutSpec.showsGhostCells ? "Hide ghost cells" : "Show ghost cells")
        }
        .padding(.bottom, Spacing.sm)
    }

    private var filterChipsRow: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Spacer(minLength: 0)

                Menu {
                    sortButton(.createdDescending, label: "Created (Newest)")
                    sortButton(.createdAscending, label: "Created (Oldest)")
                    sortButton(.updatedDescending, label: "Updated (Newest)")
                    sortButton(.updatedAscending, label: "Updated (Oldest)")
                    sortButton(.titleAscending, label: "Title (A-Z)")
                    sortButton(.titleDescending, label: "Title (Z-A)")
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, Spacing.hairline)
                        .background(
                            Capsule(style: .continuous)
                                .fill(CiderColors.separatorLight)
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    filterChip(for: .bookmark, label: "Bookmarks")
                    filterChip(for: .note, label: "Notes")
                    filterChip(for: .dateCard, label: "Date Cards")
                    filterChip(for: .contact, label: "Contacts")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    completedChip
                    ForEach(labelStorage.labels) { label in
                        labelFilterChip(label)
                    }
                }
            }

            HStack(spacing: Spacing.xs) {
                displayModeChip(.list, label: "List")
                displayModeChip(.grid, label: "Grid")
                displayModeChip(.masonry, label: "Masonry")
            }
        }
        .padding(.bottom, Spacing.sm)
    }

    private func filterChip(for type: LibraryEntityType, label: String) -> some View {
        let isOn = savedView.filterSpec.entityTypes.contains(type)
        return Button {
            toggleEntityType(type)
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func toggleEntityType(_ type: LibraryEntityType) {
        var nextTypes = savedView.filterSpec.entityTypes
        if nextTypes.contains(type) {
            if nextTypes.count == 1 {
                return
            }
            nextTypes.remove(type)
        } else {
            nextTypes.insert(type)
        }

        var updated = savedView
        updated.filterSpec.entityTypes = nextTypes
        onUpdateSavedView?(updated)
    }

    private var completedChip: some View {
        let isOn = savedView.filterSpec.includeCompleted
        return Button {
            var updated = savedView
            updated.filterSpec.includeCompleted.toggle()
            onUpdateSavedView?(updated)
        } label: {
            Text("Completed")
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func labelFilterChip(_ label: CardLabel) -> some View {
        let isOn = savedView.filterSpec.labelIDs.contains(label.id)
        return Button {
            var updated = savedView
            if updated.filterSpec.labelIDs.contains(label.id) {
                updated.filterSpec.labelIDs.remove(label.id)
            } else {
                updated.filterSpec.labelIDs.insert(label.id)
            }
            onUpdateSavedView?(updated)
        } label: {
            Text(label.name)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func sortButton(_ mode: LibrarySortMode, label: String) -> some View {
        Button(label) {
            var updated = savedView
            updated.sortSpec.mode = mode
            onUpdateSavedView?(updated)
        }
    }

    private func displayModeChip(_ mode: LibraryDisplayMode, label: String) -> some View {
        let isOn = savedView.layoutSpec.displayMode == mode
        return Button {
            var updated = savedView
            updated.layoutSpec.displayMode = mode
            onUpdateSavedView?(updated)
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isOn ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private func commitRename() {
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            draftName = savedView.name
            isRenaming = false
            return
        }
        var updated = savedView
        updated.name = trimmed
        onUpdateSavedView?(updated)
        isRenaming = false
    }

    private func toggleCalendarProjection() {
        var updated = savedView
        updated.layoutSpec.showsCalendarProjection.toggle()
        onUpdateSavedView?(updated)
    }

    private func toggleGhostCells() {
        var updated = savedView
        updated.layoutSpec.showsGhostCells.toggle()
        onUpdateSavedView?(updated)
    }

    private func modeButton(_ mode: CalendarProjectionMode, label: String) -> some View {
        let isSelected = calendarMode == mode
        return Button {
            calendarMode = mode
        } label: {
            Text(label)
                .font(CiderFont.captionMedium)
                .foregroundColor(isSelected ? CiderColors.primary : CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.hairline)
                .background(
                    Capsule(style: .continuous)
                        .fill(isSelected ? CiderColors.separatorMedium : CiderColors.separatorLight)
                )
        }
        .buttonStyle(.plain)
    }

    private var calendarHeaderTitle: String {
        let formatter = DateFormatter()
        switch calendarMode {
        case .week:
            let calendar = Calendar.current
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: calendarAnchorDate) else {
                return "Week"
            }
            formatter.dateFormat = "MMM d"
            let start = formatter.string(from: weekInterval.start)
            let end = formatter.string(from: weekInterval.end.addingTimeInterval(-1))
            return "\(start) - \(end)"
        case .month:
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: calendarAnchorDate)
        }
    }

    private func shiftCalendarAnchor(by delta: Int) {
        let calendar = Calendar.current
        let component: Calendar.Component = (calendarMode == .week) ? .weekOfYear : .month
        if let next = calendar.date(byAdding: component, value: delta, to: calendarAnchorDate) {
            calendarAnchorDate = next
        }
    }

    @ViewBuilder
    private var listGridMasonryContent: some View {
        if filteredItems.isEmpty {
            emptyStateInline
        } else {
            switch savedView.layoutSpec.displayMode {
            case .list:
                LibraryTableHeader(
                    columnConfig: $tableColumnConfig,
                    allSelected: false,
                    onToggleSelectAll: { }
                )
                .onChange(of: tableColumnConfig) { _, newConfig in
                    savedViewConfig.tableColumnConfig = newConfig
                    savedViewConfig.save()
                }
                LibraryTableRows(
                    items: filteredItems,
                    labels: labelStorage.labels,
                    folders: folders,
                    columnConfig: tableColumnConfig,
                    selectedItemIDs: [],
                    onOpen: { item in openSavedViewItem(item) },
                    onSelect: { _ in },
                    onShiftSelect: { _ in }
                )
            case .grid:
                let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filteredItems) { item in
                        itemCard(item)
                            .modifier(CardContextMenuModifier {
                                contextMenuItems(for: item)
                            })
                    }
                }
            case .masonry:
                LazyMasonryView(
                    items: filteredItems,
                    minimumColumnWidth: cardSizing.cardMinWidth,
                    itemSpacing: Spacing.md,
                    estimatedHeight: { item, columnWidth in
                        LibraryItemMasonryMetrics.estimatedHeight(
                            for: item,
                            columnWidth: columnWidth,
                            cardSizing: cardSizing
                        )
                    }
                ) { item, columnWidth in
                    itemCard(item, masonryCardWidth: columnWidth)
                        .modifier(CardContextMenuModifier {
                            contextMenuItems(for: item)
                        })
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            case .kanban:
                // Kanban with custom columns requires a folder context — fall back to grid
                let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(filteredItems) { item in
                        itemCard(item)
                            .modifier(CardContextMenuModifier {
                                contextMenuItems(for: item)
                            })
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemCard(_ item: LibraryItemV2, masonryCardWidth: CGFloat? = nil) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkCard(
                bookmark: bookmark,
                searchText: "",
                mode: savedView.layoutSpec.displayMode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.bookmarkSizing,
                masonryCardWidth: masonryCardWidth,
                folders: folders,
                onShowDetails: { onOpenBookmark?(bookmark) },
                onOpen: { onOpenBookmark?(bookmark) },
                onDelete: { onDeleteBookmark?(bookmark) },
                onMoveToFolder: { folderID in onMoveBookmarkToFolder?(bookmark, folderID) }
            )
        case .note(let note):
            NoteCardView(
                note: note,
                mode: savedView.layoutSpec.displayMode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: folders,
                onOpen: { onOpenNote?(note) },
                onRename: { newTitle in onRenameNote?(note, newTitle) },
                onDelete: { onDeleteNote?(note) },
                onMoveToFolder: { folderID in onMoveNoteToFolder?(note, folderID) }
            )
        case .dateCard(let dateCard):
            DateCardCardView(
                dateCard: dateCard,
                urgency: dateCard.urgency(windowDays: savedViewConfig.dateCardSurfacingDays),
                onOpen: {
                    if let cb = onOpenDateCard { cb(dateCard) }
                    else { editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt) }
                },
                onToggleComplete: { DateCardStorage.shared.markCompleted(dateCard.id, completed: !dateCard.isCompleted) },
                folders: folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = dateCard.folderID
                    guard DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID) else { return }
                    let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .dateCard, itemID: dateCard.id, title: dateCard.title,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    if let trashItem = DateCardStorage.shared.deleteDateCard(dateCard.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                    }
                }
            )
        case .contact:
            if case .contact(let contact) = item {
                ContactCardCardView(
                    contact: contact,
                    onOpen: {
                        if let cb = onOpenContact { cb(contact) }
                        else { contactEditorContext = ContactEditorContext(existingContact: contact) }
                    },
                    folders: folders,
                    onMoveToFolder: { folderID in
                        let oldFolderID = contact.folderID
                        guard ContactStorage.shared.assignContact(contact.id, toFolder: folderID) else { return }
                        let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                        CiderUndoManager.shared.record(.movedToFolder(
                            itemType: .contact, itemID: contact.id, title: contact.displayName,
                            fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                        ))
                    },
                    onDelete: {
                        if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                        }
                    }
                )
            } else {
                GenericLibraryItemCard(item: item)
            }
        case .todo:
            if case .todo(let todoCard) = item {
                TodoCardCardView(
                    todoCard: todoCard,
                    onOpen: { onOpenTodo?(todoCard) },
                    onToggleComplete: { TodoCardStorage.shared.markCompleted(todoCard.id, completed: !todoCard.isCompleted) },
                    onToggleChecklistItem: { itemID in TodoCardStorage.shared.toggleChecklistItem(todoCard.id, checklistItemID: itemID) },
                    folders: folders,
                    onMoveToFolder: { folderID in
                        let oldFolderID = todoCard.folderID
                        guard TodoCardStorage.shared.assignTodoCard(todoCard.id, toFolder: folderID) else { return }
                        let folderName = folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                        CiderUndoManager.shared.record(.movedToFolder(
                            itemType: .todo, itemID: todoCard.id, title: todoCard.title,
                            fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                        ))
                    },
                    onDelete: {
                        if let trashItem = TodoCardStorage.shared.deleteTodoCard(todoCard.id) {
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
                        }
                    }
                )
            } else {
                GenericLibraryItemCard(item: item)
            }
        case .vaultFile:
            EmptyView()
        }
    }

    private func contextMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        var items: [CardMenuItem] = []
        items.append(contentsOf: exportMenuItems(for: item))
        items.append(contentsOf: linkMenuItems(for: item))
        items.append(contentsOf: linkedItemsMenuItems(for: item))
        return items
    }

    private func exportMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        switch item {
        case .bookmark(let bookmark):
            guard let sourceURL = BookmarkDragPayload.imageExportURL(for: bookmark) else { return [] }
            return ExportMenuBuilder.bookmarkImageExportMenuItems {
                CiderFileExporter.exportFile(
                    sourceURL: sourceURL,
                    suggestedFileName: BookmarkDragPayload.suggestedImageExportFileName(
                        title: bookmark.title,
                        fileURL: sourceURL
                    ),
                    helpText: ExportMenuBuilder.bookmarkImageSavePanelHint
                )
            }
        case .note(let note):
            guard let sourceURL = NoteDragPayload.markdownExportURL(for: note) else { return [] }
            return ExportMenuBuilder.noteMarkdownExportMenuItems {
                CiderFileExporter.exportFile(
                    sourceURL: sourceURL,
                    suggestedFileName: NoteDragPayload.markdownExportFileName(
                        for: note,
                        fileURL: sourceURL
                    ),
                    helpText: ExportMenuBuilder.noteMarkdownSavePanelHint
                )
            }
        case .dateCard, .contact, .todo, .vaultFile:
            return []
        }
    }

    private func linkMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        let source = entityRef(for: item)
        if case .contact = item {
            let groups = linkableItemGroups(excluding: source)
            guard !groups.isEmpty else {
                return [.submenu(title: "Link Item", children: [.disabled(title: "No items available")])]
            }
            return [.submenu(title: "Link Item", children: groups)]
        } else {
            if contactStorage.contacts.isEmpty {
                return [.submenu(title: "Link Contact", children: [.disabled(title: "No contacts available")])]
            }
            let children: [CardMenuItem] = contactStorage.contacts.map { contact in
                let target = LibraryEntityRef(type: .contact, entityID: contact.id)
                let alreadyLinked = isLinked(source, target)
                if alreadyLinked {
                    return .disabled(title: "\(contact.displayName) (Linked)")
                } else {
                    return .action(title: contact.displayName) {
                        link(source: source, to: target)
                    }
                }
            }
            return [.submenu(title: "Link Contact", children: children)]
        }
    }

    private func linkedItemsMenuItems(for item: LibraryItemV2) -> [CardMenuItem] {
        let ref = entityRef(for: item)
        let refs = (try? ItemLinkService.shared.relatedRefs(for: ref)) ?? linkedEntityRefs(for: item)
        let summaries = ItemLinkService.shared.summaries(for: refs)
        guard !summaries.isEmpty else { return [] }
        let children: [CardMenuItem] = summaries.map { summary in
            .action(title: summary.title) {
                openLinkedRef(summary.ref)
            }
        }
        return [.submenu(title: "Linked Items", children: children)]
    }

    private func linkedEntityRefs(for item: LibraryItemV2) -> [LibraryEntityRef] {
        switch item {
        case .dateCard(let dateCard):
            return dateCard.linkedEntities
        case .contact(let contact):
            return contact.linkedEntities
        case .todo(let todoCard):
            return todoCard.linkedEntities
        case .bookmark, .note, .vaultFile:
            return []
        }
    }

    private func titleForLinkedRef(_ ref: LibraryEntityRef) -> String? {
        if let summary = ItemLinkService.shared.summary(for: ref) {
            return summary.title
        }
        switch ref.type {
        case .bookmark:
            return VaultBookmarkService.shared.bookmarks.first(where: { $0.id == ref.entityID })?.title
        case .note:
            return NotesStorage.shared.notes.first(where: { $0.id == ref.entityID })?.title
        case .dateCard:
            return dateCardStorage.dateCard(for: ref.entityID)?.title
        case .contact:
            return contactStorage.contact(for: ref.entityID)?.displayName
        case .todo:
            return TodoCardStorage.shared.todoCard(for: ref.entityID)?.title
        case .externalFile, .vaultFile, .session: // session kept for backward compat
            return nil
        }
    }

    private func openLinkedRef(_ ref: LibraryEntityRef) {
        switch ref.type {
        case .bookmark:
            if let bookmark = VaultBookmarkService.shared.bookmarks.first(where: { $0.id == ref.entityID }) {
                onOpenBookmark?(bookmark)
            }
        case .note:
            if let note = NotesStorage.shared.notes.first(where: { $0.id == ref.entityID }) {
                onOpenNote?(note)
            }
        case .dateCard:
            if let dateCard = dateCardStorage.dateCard(for: ref.entityID) {
                editorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
            }
        case .contact:
            if let contact = contactStorage.contact(for: ref.entityID) {
                contactEditorContext = ContactEditorContext(existingContact: contact)
            }
        case .todo:
            if let todoCard = TodoCardStorage.shared.todoCard(for: ref.entityID) {
                onOpenTodo?(todoCard)
            }
        case .vaultFile:
            if let file = VaultFileService.shared.file(for: ref.entityID) {
                onOpenVaultFile?(file)
            }
        case .externalFile, .session: // session kept for backward compat
            break
        }
    }

    private func link(source: LibraryEntityRef, to target: LibraryEntityRef) {
        do {
            try ItemLinkService.shared.addLink(from: source, to: target)
            updateInMemoryLinkedEntities(source: source, target: target, shouldAdd: true)
            updateInMemoryLinkedEntities(source: target, target: source, shouldAdd: true)
        } catch {
            Self.logger.error("Failed to link \(source.id, privacy: .public) to \(target.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateInMemoryLinkedEntities(source: LibraryEntityRef, target: LibraryEntityRef, shouldAdd: Bool) {
        switch source.type {
        case .dateCard:
            guard var dateCard = dateCardStorage.dateCard(for: source.entityID) else { return }
            mergePersistedOutgoingRefs(into: &dateCard.linkedEntities, source: source)
            updateRefs(&dateCard.linkedEntities, target: target, shouldAdd: shouldAdd)
            _ = dateCardStorage.updateDateCard(dateCard)
        case .contact:
            guard var contact = contactStorage.contact(for: source.entityID) else { return }
            mergePersistedOutgoingRefs(into: &contact.linkedEntities, source: source)
            updateRefs(&contact.linkedEntities, target: target, shouldAdd: shouldAdd)
            _ = contactStorage.updateContact(contact)
        case .todo:
            guard var todo = TodoCardStorage.shared.todoCard(for: source.entityID) else { return }
            mergePersistedOutgoingRefs(into: &todo.linkedEntities, source: source)
            updateRefs(&todo.linkedEntities, target: target, shouldAdd: shouldAdd)
            _ = TodoCardStorage.shared.updateTodoCard(todo)
        case .bookmark, .note, .vaultFile, .externalFile, .session:
            break
        }
    }

    private func mergePersistedOutgoingRefs(into refs: inout [LibraryEntityRef], source: LibraryEntityRef) {
        guard let persistedRefs = try? ItemLinkService.shared.outgoingRefs(for: source) else { return }
        for ref in persistedRefs where !refs.contains(ref) {
            refs.append(ref)
        }
    }

    private func updateRefs(_ refs: inout [LibraryEntityRef], target: LibraryEntityRef, shouldAdd: Bool) {
        if shouldAdd {
            if !refs.contains(target) {
                refs.append(target)
            }
        } else {
            refs.removeAll { $0 == target }
        }
    }

    private func isLinked(_ source: LibraryEntityRef, _ target: LibraryEntityRef) -> Bool {
        ((try? ItemLinkService.shared.relatedRefs(for: source)) ?? linkedEntityRefs(for: source)).contains(target)
    }

    private func linkedEntityRefs(for ref: LibraryEntityRef) -> [LibraryEntityRef] {
        switch ref.type {
        case .dateCard:
            return dateCardStorage.dateCard(for: ref.entityID)?.linkedEntities ?? []
        case .contact:
            return contactStorage.contact(for: ref.entityID)?.linkedEntities ?? []
        case .todo:
            return TodoCardStorage.shared.todoCard(for: ref.entityID)?.linkedEntities ?? []
        case .bookmark, .note, .vaultFile, .externalFile, .session:
            return []
        }
    }

    private func linkableItemGroups(excluding source: LibraryEntityRef) -> [CardMenuItem] {
        [
            linkableGroup(title: "Bookmarks", refsAndTitles: VaultBookmarkService.shared.bookmarks.map {
                (LibraryEntityRef(type: .bookmark, entityID: $0.id), $0.title)
            }, excluding: source),
            linkableGroup(title: "Notes", refsAndTitles: NotesStorage.shared.notes.map {
                (LibraryEntityRef(type: .note, entityID: $0.id), $0.title)
            }, excluding: source),
            linkableGroup(title: "Todos", refsAndTitles: TodoCardStorage.shared.todoCards.map {
                (LibraryEntityRef(type: .todo, entityID: $0.id), $0.title)
            }, excluding: source),
            linkableGroup(title: "Date Cards", refsAndTitles: dateCardStorage.dateCards.map {
                (LibraryEntityRef(type: .dateCard, entityID: $0.id), $0.title)
            }, excluding: source),
            linkableGroup(title: "Contacts", refsAndTitles: contactStorage.contacts.map {
                (LibraryEntityRef(type: .contact, entityID: $0.id), $0.displayName)
            }, excluding: source),
            linkableGroup(title: "Files", refsAndTitles: VaultFileService.shared.files.map {
                (LibraryEntityRef(type: .vaultFile, entityID: $0.id), $0.displayTitle)
            }, excluding: source)
        ]
        .compactMap { $0 }
    }

    private func linkableGroup(
        title: String,
        refsAndTitles: [(LibraryEntityRef, String)],
        excluding source: LibraryEntityRef
    ) -> CardMenuItem? {
        let children: [CardMenuItem] = refsAndTitles
            .filter { $0.0 != source }
            .map { target, title in
                if isLinked(source, target) {
                    return .disabled(title: "\(title) (Linked)")
                }
                return .action(title: title) {
                    link(source: source, to: target)
                }
            }
        guard !children.isEmpty else { return nil }
        return .submenu(title: title, children: children)
    }

    private func entityRef(for item: LibraryItemV2) -> LibraryEntityRef {
        switch item {
        case .bookmark(let bookmark):
            return LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        case .note(let note):
            return LibraryEntityRef(type: .note, entityID: note.id)
        case .dateCard(let dateCard):
            return LibraryEntityRef(type: .dateCard, entityID: dateCard.id)
        case .contact(let contact):
            return LibraryEntityRef(type: .contact, entityID: contact.id)
        case .todo(let todoCard):
            return LibraryEntityRef(type: .todo, entityID: todoCard.id)
        case .vaultFile(let file):
            return LibraryEntityRef(type: .vaultFile, entityID: file.id)
        }
    }

    private var emptyStateInline: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: savedView.layoutSpec.showsCalendarProjection ? "calendar" : "line.3.horizontal.decrease.circle")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)

            Text("No items in \(savedView.name)")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.secondary)

            Text("Adjust filters or add more content to this saved view.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xl)
    }

    private func folderName(for note: Note) -> String? {
        guard let folderID = note.folderID else { return nil }
        return folders.first(where: { $0.id == folderID })?.name
    }

    private func openSavedViewItem(_ item: LibraryItemV2) {
        switch item {
        case .bookmark(let bookmark): onOpenBookmark?(bookmark)
        case .note(let note): onOpenNote?(note)
        case .dateCard(let dateCard): onOpenDateCard?(dateCard)
        case .contact(let contact): onOpenContact?(contact)
        case .todo(let todoCard): onOpenTodo?(todoCard)
        case .vaultFile: break
        }
    }
}

private struct GenericLibraryItemCard: View {
    let item: LibraryItemV2
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.controlAccent)
                Text(item.title)
                    .font(CiderFont.subheadingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
            }
            Text(subtitle)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(2)
            Text(item.updatedDate.formatted(.relative(presentation: .named)))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardContainer(isHovered: isHovered)
        .hoverState($isHovered, animation: .snappy)
    }

    private var icon: String {
        switch item {
        case .bookmark: "bookmark"
        case .note: "note.text"
        case .dateCard: "calendar"
        case .contact: "person.crop.circle"
        case .todo: "checklist"
        case .vaultFile: "doc.on.doc"
        }
    }

    private var subtitle: String {
        switch item {
        case .bookmark(let bookmark):
            bookmark.hostDisplay
        case .note:
            "Note"
        case .dateCard(let dateCard):
            dateCard.location.isEmpty ? "Date Card" : dateCard.location
        case .contact(let contact):
            contact.relationshipLabel.isEmpty ? "Contact" : contact.relationshipLabel
        case .todo(let todoCard):
            todoCard.isCompleted ? "Completed" : "Todo"
        case .vaultFile(let file):
            file.filename
        }
    }
}
