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
    var onOpenSession: (BrowserSession) -> Void = { _ in }
    var onlyUnassigned: Bool = false
    var activeLabelIDs: Set<UUID> = []
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
        libraryViewModel.filteredItems(using: filterSpec, sort: sortSpec)
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
                    ScrollViewReader { proxy in
                        ScrollView {
                            libraryFeed
                                .frame(maxWidth: .infinity, alignment: .leading)
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
    private var libraryFeed: some View {
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

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .masonry)
                        .id(item.id)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
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
                            .frame(width: 220)
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
                    DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID)
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
                    TodoCardStorage.shared.assignTodoCard(todoCard.id, toFolder: folderID)
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

    // MARK: - List Row

    @ViewBuilder
    private func libraryListRow(_ item: LibraryItemV2) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkListRow(
                bookmark: bookmark,
                searchText: "",
                cardSizing: cardSizing.bookmarkSizing,
                folders: bookmarksViewModel.folders,
                dragProvider: bookmarkDragProvider(for: bookmark),
                dragPreviewOverride: multiDragPreview(for: item),
                onShowDetails: { handleNormalAction { onShowBookmarkDetails(bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { bookmarksViewModel.deleteBookmarks([bookmark]) },
                onMoveToFolder: { _ = bookmarksViewModel.assign(bookmark, toFolder: $0) },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .note(let note):
            NoteListRow(
                note: note,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: bookmarksViewModel.folders,
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onOpen: { handleNormalAction { openNoteInPanel(note) } },
                onRename: { newTitle in
                    NotesStorage.shared.rename(note: note, to: newTitle)
                },
                onDelete: {
                    notesViewModel.deleteNotes([note])
                },
                onMoveToFolder: { folderID in
                    _ = notesViewModel.assignNote(note, toFolder: folderID)
                },
                dragProvider: noteDragProvider(for: note),
                dragPreviewOverride: multiDragPreview(for: item),
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .dateCard(let dateCard):
            DateCardListRow(
                dateCard: dateCard,
                urgency: dateCard.urgency(windowDays: config.dateCardSurfacingDays),
                onOpen: { handleNormalAction { presentDateCardDetail(dateCard) } },
                onToggleComplete: { DateCardStorage.shared.markCompleted(dateCard.id, completed: !dateCard.isCompleted) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = dateCard.folderID
                    DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID)
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
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .contact(let contact):
            ContactListRow(
                contact: contact,
                onOpen: { handleNormalAction { presentContactDetail(contact) } },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = contact.folderID
                    ContactStorage.shared.assignContact(contact.id, toFolder: folderID)
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .contact, itemID: contact.id, title: contact.displayName,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .todo(let todoCard):
            TodoListRow(
                todoCard: todoCard,
                onOpen: { handleNormalAction { presentTodoDetail(todoCard) } },
                onToggleComplete: { TodoCardStorage.shared.markCompleted(todoCard.id, completed: !todoCard.isCompleted) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = todoCard.folderID
                    TodoCardStorage.shared.assignTodoCard(todoCard.id, toFolder: folderID)
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
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .externalFile(let file):
            SourceCardView(
                file: file,
                width: .infinity,
                isSelected: isItemSelected(item),
                onOpen: {
                    handleNormalAction {
                        NotificationCenter.default.post(
                            name: .openExternalFile,
                            object: nil,
                            userInfo: ["fileURL": file.path]
                        )
                    }
                },
                onDelete: { try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil) }
            )
        case .vaultFile(let vaultFile):
            VaultFileListRow(
                file: vaultFile,
                onOpen: { handleNormalAction { onOpenVaultFile(vaultFile) } },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        case .session(let session):
            SessionListRow(
                session: session,
                onOpen: { handleNormalAction { onOpenSession(session) } },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = session.folderID
                    BrowserSessionStorage.shared.assignSession(session.id, toFolder: folderID)
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .session, itemID: session.id, title: session.name,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    if let trashItem = BrowserSessionStorage.shared.delete(session.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .session, trashItem: trashItem))
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        }
    }

    // MARK: - Card (Grid / Masonry)

    @ViewBuilder
    private func libraryCard(_ item: LibraryItemV2, mode: BookmarkCard.CardMode) -> some View {
        switch item {
        case .bookmark(let bookmark):
            BookmarkCard(
                bookmark: bookmark,
                searchText: "",
                mode: mode == .grid ? .grid : .masonry,
                cardSizing: cardSizing.bookmarkSizing,
                folders: bookmarksViewModel.folders,
                dragProvider: bookmarkDragProvider(for: bookmark),
                dragPreviewOverride: multiDragPreview(for: item),
                onShowDetails: { handleNormalAction { onShowBookmarkDetails(bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { bookmarksViewModel.deleteBookmarks([bookmark]) },
                onMoveToFolder: { _ = bookmarksViewModel.assign(bookmark, toFolder: $0) },
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
                    notesViewModel.deleteNotes([note])
                },
                onMoveToFolder: { folderID in
                    _ = notesViewModel.assignNote(note, toFolder: folderID)
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
                    DateCardStorage.shared.assignDateCard(dateCard.id, toFolder: folderID)
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
                    ContactStorage.shared.assignContact(contact.id, toFolder: folderID)
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .contact, itemID: contact.id, title: contact.displayName,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
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
                    TodoCardStorage.shared.assignTodoCard(todoCard.id, toFolder: folderID)
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
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .externalFile(let file):
            SourceCardView(
                file: file,
                width: cardMinWidth(for: mode),
                isSelected: isItemSelected(item),
                onOpen: {
                    handleNormalAction {
                        NotificationCenter.default.post(
                            name: .openExternalFile,
                            object: nil,
                            userInfo: ["fileURL": file.path]
                        )
                    }
                },
                onDelete: { try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil) }
            )
        case .vaultFile(let vaultFile):
            VaultFileCardView(
                file: vaultFile,
                onOpen: { handleNormalAction { onOpenVaultFile(vaultFile) } },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        case .session(let session):
            SessionCardCardView(
                session: session,
                onOpen: { handleNormalAction { onOpenSession(session) } },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = session.folderID
                    BrowserSessionStorage.shared.assignSession(session.id, toFolder: folderID)
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .session, itemID: session.id, title: session.name,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    if let trashItem = BrowserSessionStorage.shared.delete(session.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .session, trashItem: trashItem))
                    }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) },
                onToggleLabelBulk: onToggleLabelBulk
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
        case .externalFile(let file):
            NotificationCenter.default.post(
                name: .openExternalFile,
                object: nil,
                userInfo: ["fileURL": file.path]
            )
        case .vaultFile(let vaultFile):
            onOpenVaultFile(vaultFile)
        case .session(let session):
            onOpenSession(session)
        }
    }

    private func continueDragProvider(for item: LibraryItemV2) -> (() -> NSItemProvider)? {
        switch item {
        case .bookmark(let bookmark): return bookmarkDragProvider(for: bookmark)
        case .note(let note): return noteDragProvider(for: note)
        case .dateCard, .contact, .todo, .externalFile, .vaultFile, .session: return nil
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
                    provider.suggestedName = bookmark.title + "." + fileURL.pathExtension
                    return provider
                }
                // Fallback: raw image data
                let provider = NSItemProvider()
                BookmarkDragPayload.registerPublicImage(on: provider, bookmark: bookmark)
                return provider
            }

            if selectedItemIDs.contains(itemID) && selectedItemIDs.count > 1 {
                let allItems = CiderMultiDrag.parseSelectedItemIDs(selectedItemIDs)
                return CiderMultiDrag.makeProvider(
                    primaryType: BookmarkDragPayload.typeIdentifier,
                    primaryID: bookmark.id,
                    allItemIDs: allItems,
                )
            } else {
                // Normal drag: text (bookmark ID) + URL for internal folders + external link sharing
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
                BookmarkDragPayload.registerPublicURL(on: provider, urlString: bookmark.urlString)
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
            } else {
                let provider = NSItemProvider(
                    object: "\(NoteDragPayload.textPrefix)\(note.id.uuidString)" as NSString
                )
                let payload = Data(note.id.uuidString.utf8)
                provider.registerDataRepresentation(
                    forTypeIdentifier: NoteDragPayload.typeIdentifier,
                    visibility: .all
                ) { completion in
                    completion(payload, nil)
                    return nil
                }
                // NOTE: Do NOT call NoteDragPayload.registerPublicFileURL here.
                // Registering public.file-url breaks SwiftUI's .onDrop, causing
                // providers to arrive with empty registeredTypeIdentifiers.
                return provider
            }
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
