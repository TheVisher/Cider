import AppKit
import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject var libraryViewModel: LibraryViewModel
    var selectedFolderID: UUID?
    @Binding var displayMode: LibraryDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var continueSectionCollapsed: Bool
    @Binding var selectedItemIDs: Set<String>
    @Binding var sortMode: LibrarySortMode
    @Binding var entityFilter: Set<LibraryEntityType>
    var searchText: String = ""
    var onOpenNote: (Note) -> Void = { _ in }
    var onShowBookmarkDetails: (Bookmark) -> Void = { _ in }
    var onEditDateCard: (DateCard) -> Void = { _ in }
    var onEditContact: (ContactCard) -> Void = { _ in }
    var onOpenDateCard: (DateCard) -> Void = { _ in }
    var onOpenContact: (ContactCard) -> Void = { _ in }
    var onOpenTodo: (TodoCard) -> Void = { _ in }
    var onOpenVaultFile: (VaultFile) -> Void = { _ in }
    var onlyUnassigned: Bool = false
    var activeLabelIDs: Set<UUID> = []
    var maxVisibleItems: Int?
    var onToggleLabelBulk: ((UUID) -> Void)? = nil
    var showComingUp: Bool = true
    @Binding var scrollToItemID: String?
    var focusedItemID: String? = nil

    @State private var config = CiderConfig.load()
    @State private var tableColumnConfig: TableColumnConfig = CiderConfig.load().tableColumnConfig
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Library Items

    private var filterSpec: SavedViewFilterSpec {
        SavedViewFilterSpec(
            entityTypes: entityFilter,
            labelIDs: activeLabelIDs,
            folderID: selectedFolderID,
            includeCompleted: true,
            textQuery: searchText,
            onlyUnassigned: onlyUnassigned
        )
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sortSpec: SavedViewSortSpec {
        SavedViewSortSpec(mode: sortMode)
    }

    /// Continue section always shows global recents regardless of folder/filter selection
    private var continueItems: [LibraryItemV2] {
        libraryViewModel.recentItems
    }

    /// Library feed applies current filter + sort
    private var libraryItems: [LibraryItemV2] {
        let items = libraryViewModel.filteredItems(using: filterSpec, sort: sortSpec)
        guard let maxVisibleItems else { return items }
        return Array(items.prefix(maxVisibleItems))
    }

    /// Date cards and todos with approaching/today/overdue dates
    private var comingUpItems: [LibraryItemV2] {
        let windowDays = config.dateCardSurfacingDays
        guard windowDays > 0 else { return [] }
        return libraryItems.filter { item in
            switch item {
            case .dateCard(let dc):
                return dc.urgency(windowDays: windowDays) != nil
            case .todo(let tc):
                return tc.urgency(windowDays: windowDays) != nil
            default:
                return false
            }
        }.sorted { lhs, rhs in
            let lhsDate = lhs.dateAnchor ?? lhs.createdDate
            let rhsDate = rhs.dateAnchor ?? rhs.createdDate
            return lhsDate < rhsDate
        }
    }

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private func cardMinWidth(for mode: BookmarkCard.CardMode) -> CGFloat {
        cardSizing.bookmarkSizing.cardMinWidth
    }

    private var foldersByID: [UUID: Folder] {
        bookmarksViewModel.foldersByID
    }

    var body: some View {
        VStack(spacing: 0) {
            if libraryItems.isEmpty {
                // No scrollable content — show recents normally above empty state
                if config.showContinueSection && !isSearching && !continueItems.isEmpty && !continueSectionCollapsed {
                    ContinueSectionView(
                        items: continueItems,
                        onOpen: { handleContinueOpen($0) },
                        dragProviderForItem: continueDragProvider
                    )
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                }
                emptyState
            } else {
                if config.showContinueSection && !isSearching && !continueItems.isEmpty {
                    CollapsiblePinnedSection(isCollapsed: $continueSectionCollapsed) {
                        ContinueSectionView(
                            items: continueItems,
                            onOpen: { handleContinueOpen($0) },
                            dragProviderForItem: continueDragProvider
                        )
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.md)
                    }
                }

                if showComingUp && !isSearching && !comingUpItems.isEmpty {
                    comingUpSection
                }

                if displayMode == .list {
                    // Table view manages its own scroll + sticky header
                    LibraryTableView(
                        items: libraryItems,
                        labels: labelStorage.labels,
                        folders: bookmarksViewModel.folders,
                        columnConfig: $tableColumnConfig,
                        selectedItemIDs: selectedItemIDs,
                        focusedItemID: focusedItemID,
                        onOpen: { item in handleNormalAction { handleContinueOpen(item) } },
                        onSelect: { item in handleSelect(item: item) },
                        onShiftSelect: { item in handleShiftSelect(item: item) },
                        onSelectAll: { selectedItemIDs = Set(libraryItems.map(\.id)) },
                        onDeselectAll: { selectedItemIDs.removeAll() },
                        scrollToItemID: $scrollToItemID
                    )
                    .onChange(of: tableColumnConfig) { _, newConfig in
                        config.tableColumnConfig = newConfig
                        config.save()
                    }
                } else {
                    GeometryReader { contentProxy in
                        let feedWidth = HomeDashboardFeedLayout.availableWidth(
                            contentWidth: contentProxy.size.width
                        )

                        ScrollViewReader { proxy in
                            ScrollView {
                                libraryFeed(availableWidth: feedWidth)
                                    .frame(width: feedWidth, alignment: .leading)
                            }
                            .scrollIndicators(.hidden)
                            .onChange(of: scrollToItemID) { _, id in
                                if let id {
                                    withAnimation(reduceMotion ? .none : .snappy) {
                                        proxy.scrollTo(id, anchor: .center)
                                    }
                                    scrollToItemID = nil
                                }
                            }
                        }
                        .frame(width: feedWidth, alignment: .leading)
                    }
                    .padding(Spacing.xxs)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.md)
                }
            }
        }
    }

    // MARK: - Library Feed

    @ViewBuilder
    private func libraryFeed(availableWidth: CGFloat) -> some View {
        switch displayMode {
        case .list:
            // Handled separately in body — this branch should not be reached
            EmptyView()

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .grid)
                        .id(item.id)
                }
            }
            .frame(width: availableWidth, alignment: .leading)

        case .masonry:
            LazyMasonryView(
                items: libraryItems,
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md,
                viewportWidth: availableWidth,
                estimatedHeight: { item, columnWidth in
                    LibraryItemMasonryMetrics.estimatedHeight(
                        for: item,
                        columnWidth: columnWidth,
                        cardSizing: cardSizing
                    )
                }
            ) { item, columnWidth in
                libraryCard(item, mode: .masonry, masonryCardWidth: columnWidth)
            }
            .frame(width: availableWidth, alignment: .leading)
            .padding(.bottom, Spacing.xs)

        case .kanban:
            // Kanban only supported in folder detail — fall back to grid
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .grid)
                        .id(item.id)
                }
            }
            .frame(width: availableWidth, alignment: .leading)
        }
    }

    // MARK: - Coming Up Section

    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
                Text("COMING UP")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(comingUpItems) { item in
                        comingUpCard(item)
                            .frame(width: cardSizing.cardMinWidth)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.md + Spacing.xxs)
        .padding(.top, Spacing.md)
    }

    @ViewBuilder
    private func comingUpCard(_ item: LibraryItemV2) -> some View {
        switch item {
        case .dateCard(let dateCard):
            DateCardCardView(
                dateCard: dateCard,
                urgency: dateCard.urgency(windowDays: config.dateCardSurfacingDays),
                onOpen: { handleNormalAction { presentDateCardDetail(dateCard) } },
                onToggleComplete: { DateCardStorage.shared.markCompleted(dateCard.id, completed: !dateCard.isCompleted) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = dateCard.folderID
                    guard DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID) else { return }
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
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
        case .todo(let todoCard):
            TodoCardCardView(
                todoCard: todoCard,
                onOpen: { handleNormalAction { presentTodoDetail(todoCard) } },
                onToggleComplete: { TodoCardStorage.shared.markCompleted(todoCard.id, completed: !todoCard.isCompleted) },
                onToggleChecklistItem: { itemID in TodoCardStorage.shared.toggleChecklistItem(todoCard.id, checklistItemID: itemID) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = todoCard.folderID
                    guard TodoCardStorage.shared.assignTodoCard(todoCard.id, toFolder: folderID) else { return }
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
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
        default:
            EmptyView()
        }
    }

    // MARK: - Card (Grid / Masonry)

    @ViewBuilder
    private func libraryCard(
        _ item: LibraryItemV2,
        mode: BookmarkCard.CardMode,
        masonryCardWidth: CGFloat? = nil
    ) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkCard(
                bookmark: bookmark,
                searchText: "",
                mode: mode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.bookmarkSizing,
                masonryCardWidth: masonryCardWidth,
                folders: bookmarksViewModel.folders,
                dragProvider: bookmarkDragProvider(for: bookmark),
                dragPreviewOverride: multiDragPreview(for: item),
                onShowDetails: { handleNormalAction { onShowBookmarkDetails(bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { handleContextMenuDelete(item: item) { bookmarksViewModel.deleteBookmarks([bookmark]) } },
                onMoveToFolder: { folderID in
                    guard bookmarksViewModel.assign(bookmark, toFolder: folderID) else { return }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .note(let note):
            NoteCardView(
                note: note,
                mode: mode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: bookmarksViewModel.folders,
                onOpen: { handleNormalAction { openNoteInPanel(note) } },
                onRename: { newTitle in
                    NotesStorage.shared.rename(note: note, to: newTitle)
                },
                onDelete: {
                    handleContextMenuDelete(item: item) { notesViewModel.deleteNotes([note]) }
                },
                onMoveToFolder: { folderID in
                    guard notesViewModel.assignNote(note, toFolder: folderID) else { return }
                },
                dragProvider: noteDragProvider(for: note),
                dragPreviewOverride: multiDragPreview(for: item),
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .dateCard(let dateCard):
            DateCardCardView(
                dateCard: dateCard,
                urgency: dateCard.urgency(windowDays: config.dateCardSurfacingDays),
                onOpen: { handleNormalAction { presentDateCardDetail(dateCard) } },
                onToggleComplete: { DateCardStorage.shared.markCompleted(dateCard.id, completed: !dateCard.isCompleted) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = dateCard.folderID
                    guard DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID) else { return }
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .dateCard, itemID: dateCard.id, title: dateCard.title,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    handleContextMenuDelete(item: item) {
                        if let trashItem = DateCardStorage.shared.deleteDateCard(dateCard.id) {
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                        }
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .contact(let contact):
            ContactCardCardView(
                contact: contact,
                onOpen: { handleNormalAction { presentContactDetail(contact) } },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = contact.folderID
                    guard ContactStorage.shared.assignContact(contact.id, toFolder: folderID) else { return }
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .contact, itemID: contact.id, title: contact.displayName,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    handleContextMenuDelete(item: item) {
                        if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                        }
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .todo(let todoCard):
            TodoCardCardView(
                todoCard: todoCard,
                onOpen: { handleNormalAction { presentTodoDetail(todoCard) } },
                onToggleComplete: { TodoCardStorage.shared.markCompleted(todoCard.id, completed: !todoCard.isCompleted) },
                onToggleChecklistItem: { itemID in TodoCardStorage.shared.toggleChecklistItem(todoCard.id, checklistItemID: itemID) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = todoCard.folderID
                    guard TodoCardStorage.shared.assignTodoCard(todoCard.id, toFolder: folderID) else { return }
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .todo, itemID: todoCard.id, title: todoCard.title,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    handleContextMenuDelete(item: item) {
                        if let trashItem = TodoCardStorage.shared.deleteTodoCard(todoCard.id) {
                            CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
                        }
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .vaultFile(let vaultFile):
            VaultFileCardView(
                file: vaultFile,
                onOpen: { handleNormalAction { onOpenVaultFile(vaultFile) } },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = vaultFile.folderID
                    guard VaultFileService.shared.assignFile(vaultFile.id, toFolder: folderID) else { return }
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .vaultFile, itemID: vaultFile.id, title: vaultFile.displayTitle,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    handleContextMenuDelete(item: item) {
                        let trashItem = TrashStorage.shared.trashVaultFile(vaultFile)
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .vaultFile, trashItem: trashItem))
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer(minLength: 0)

            Image(systemName: selectedFolderID != nil ? "folder" : "tray.2")
                .font(CiderFont.heroDisplay(scale: 1.0))
                .foregroundColor(CiderColors.tertiary)

            Text(selectedFolderID != nil ? "No items in this folder" : "Your library is empty")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.secondary)

            Text(selectedFolderID != nil
                ? "Drag bookmarks or notes into this folder to organize them"
                : "Capture a bookmark or create a note to get started")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection Helpers

    private func isItemSelected(_ item: LibraryItemV2) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    /// Handles context menu delete: if the item is part of a multi-selection, delete all selected items.
    private func handleContextMenuDelete(item: LibraryItemV2, singleDelete: () -> Void) {
        if selectedItemIDs.count > 1 && selectedItemIDs.contains(item.id) {
            // Snapshot ViewModel arrays before the loop — deleting item N updates the
            // @Published array immediately, so item N+1 lookup would fail without this.
            let bookmarksSnapshot = bookmarksViewModel.bookmarks
            let notesSnapshot = notesViewModel.notes
            var allTrashItems: [TrashItem] = []
            for id in selectedItemIDs {
                if id.hasPrefix("bookmark-"),
                   let uuid = UUID(uuidString: String(id.dropFirst("bookmark-".count))),
                   let bookmark = bookmarksSnapshot.first(where: { $0.id == uuid }) {
                    allTrashItems.append(contentsOf: VaultBookmarkService.shared.removeAll([bookmark]))
                } else if id.hasPrefix("note-"),
                          let uuid = UUID(uuidString: String(id.dropFirst("note-".count))),
                          let note = notesSnapshot.first(where: { $0.id == uuid }) {
                    allTrashItems.append(NotesStorage.shared.delete(note: note))
                } else if id.hasPrefix("datecard-"),
                          let uuid = UUID(uuidString: String(id.dropFirst("datecard-".count))) {
                    if let item = DateCardStorage.shared.deleteDateCard(uuid) {
                        allTrashItems.append(item)
                    }
                } else if id.hasPrefix("contact-"),
                          let uuid = UUID(uuidString: String(id.dropFirst("contact-".count))) {
                    if let item = ContactStorage.shared.deleteContact(uuid) {
                        allTrashItems.append(item)
                    }
                } else if id.hasPrefix("todo-"),
                          let uuid = UUID(uuidString: String(id.dropFirst("todo-".count))) {
                    if let item = TodoCardStorage.shared.deleteTodoCard(uuid) {
                        allTrashItems.append(item)
                    }
                } else if id.hasPrefix("vaultfile-"),
                          let uuid = UUID(uuidString: String(id.dropFirst("vaultfile-".count))),
                          let file = VaultFileService.shared.file(for: uuid) {
                    allTrashItems.append(TrashStorage.shared.trashVaultFile(file))
                }
            }
            if !allTrashItems.isEmpty {
                CiderUndoManager.shared.record(.bulkDeletedToTrash(allTrashItems))
            }
            selectedItemIDs.removeAll()
        } else {
            singleDelete()
        }
    }

    @State private var selectionAnchorID: String?

    private func handleSelect(item: LibraryItemV2) {
        let id = item.id
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
        selectionAnchorID = id
    }

    private func handleShiftSelect(item: LibraryItemV2) {
        let id = item.id
        let items = libraryItems
        guard let anchorID = selectionAnchorID,
              let anchorIndex = items.firstIndex(where: { $0.id == anchorID }),
              let clickedIndex = items.firstIndex(where: { $0.id == id }) else {
            selectedItemIDs.insert(id)
            selectionAnchorID = id
            return
        }

        let range = min(anchorIndex, clickedIndex) ... max(anchorIndex, clickedIndex)
        for i in range {
            selectedItemIDs.insert(items[i].id)
        }
    }

    private func handleNormalAction(_ action: () -> Void) {
        if !selectedItemIDs.isEmpty {
            selectedItemIDs.removeAll()
        } else {
            action()
        }
    }

    // MARK: - Helpers

    private func folderName(for note: Note) -> String? {
        guard let folderID = note.folderID else { return nil }
        return foldersByID[folderID]?.name
    }

    // MARK: - Note Panel

    private func openNoteInPanel(_ note: Note) {
        onOpenNote(note)
    }

    // MARK: - Date Card & Contact Detail

    private func presentDateCardDetail(_ dateCard: DateCard) {
        onOpenDateCard(dateCard)
    }

    private func presentContactDetail(_ contact: ContactCard) {
        onOpenContact(contact)
    }

    private func presentTodoDetail(_ todoCard: TodoCard) {
        onOpenTodo(todoCard)
    }

    // MARK: - Drag Providers

    private func handleContinueOpen(_ item: LibraryItemV2) {
        switch item {
        case .bookmark(let bookmark): onShowBookmarkDetails(bookmark)
        case .note(let note): openNoteInPanel(note)
        case .dateCard(let dateCard): presentDateCardDetail(dateCard)
        case .contact(let contact): presentContactDetail(contact)
        case .todo(let todoCard): presentTodoDetail(todoCard)
        case .vaultFile(let vaultFile):
            onOpenVaultFile(vaultFile)
        }
    }

    private func continueDragProvider(for item: LibraryItemV2) -> (() -> NSItemProvider)? {
        switch item {
        case .bookmark(let bookmark): return bookmarkDragProvider(for: bookmark)
        case .note(let note): return noteDragProvider(for: note)
        case .dateCard, .contact, .todo, .vaultFile: return nil
        }
    }

    private func bookmarkDragProvider(for bookmark: Bookmark) -> () -> NSItemProvider {
        return {
            let itemID = "bookmark-\(bookmark.id.uuidString)"

            let isOptionHeld = NSEvent.modifierFlags.contains(.option)
            let hasImage = bookmark.originalImageFileURL != nil || bookmark.thumbnailFileURL != nil

            // Option+drag = export image to external apps (Finder, iMessage, etc.)
            // Use NSItemProvider(contentsOf:) so the provider carries the image file
            // without text — prevents text fields (Facebook) from receiving the title.
            if isOptionHeld && hasImage {
                let fileURL = bookmark.originalImageFileURL ?? bookmark.thumbnailFileURL
                if let fileURL, let provider = NSItemProvider(contentsOf: fileURL) {
                    provider.suggestedName = BookmarkDragPayload.suggestedImageExportName(
                        title: bookmark.title,
                        fileURL: fileURL
                    )
                    return provider
                }
            }

            if selectedItemIDs.contains(itemID) && selectedItemIDs.count > 1 {
                let allItems = CiderMultiDrag.parseSelectedItemIDs(selectedItemIDs)
                return CiderMultiDrag.makeProvider(
                    primaryType: BookmarkDragPayload.typeIdentifier,
                    primaryID: bookmark.id,
                    allItemIDs: allItems,
                )
            } else {
                // Normal drag: internal payload only. External file/image export is handled by Option-drag.
                let provider = NSItemProvider(
                    object: "\(BookmarkDragPayload.textPrefix)\(bookmark.id.uuidString)" as NSString
                )
                let payload = Data(bookmark.id.uuidString.utf8)
                provider.registerDataRepresentation(
                    forTypeIdentifier: BookmarkDragPayload.typeIdentifier,
                    visibility: .all
                ) { completion in
                    completion(payload, nil)
                    return nil
                }
                return provider
            }
        }
    }

    private func noteDragProvider(for note: Note) -> () -> NSItemProvider {
        return {
            let itemID = "note-\(note.id.uuidString)"

            if selectedItemIDs.contains(itemID) && selectedItemIDs.count > 1 {
                let allItems = CiderMultiDrag.parseSelectedItemIDs(selectedItemIDs)
                return CiderMultiDrag.makeProvider(
                    primaryType: NoteDragPayload.typeIdentifier,
                    primaryID: note.id,
                    allItemIDs: allItems,
                )
            }

            if NSEvent.modifierFlags.contains(.option),
               let provider = NoteDragPayload.makeMarkdownFileProvider(for: note) {
                return provider
            }

            return NoteDragPayload.makeInternalProvider(for: note)
        }
    }

    // MARK: - Multi-Drag Preview

    private func multiDragPreview(for item: LibraryItemV2) -> AnyView? {
        let id = item.id
        guard selectedItemIDs.contains(id), selectedItemIDs.count > 1 else { return nil }

        var previewItems: [MultiDragPreviewItem] = []
        if case .bookmark(let b) = item { previewItems.append(.bookmark(b)) }
        else if case .note(let n) = item { previewItems.append(.note(n)) }

        for libraryItem in libraryItems where isItemSelected(libraryItem) && libraryItem.id != id {
            if case .bookmark(let b) = libraryItem { previewItems.append(.bookmark(b)) }
            else if case .note(let n) = libraryItem { previewItems.append(.note(n)) }
            if previewItems.count >= 3 { break }
        }

        guard !previewItems.isEmpty else { return nil }
        return AnyView(MultiDragPreview(items: previewItems, totalCount: selectedItemIDs.count))
    }
}

enum HomeDashboardFeedLayout {
    static func availableWidth(contentWidth: CGFloat) -> CGFloat {
        guard contentWidth.isFinite, contentWidth > 0 else { return 1 }
        return contentWidth
    }
}
