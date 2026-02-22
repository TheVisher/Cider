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
    var onEditDateCard: (DateCard) -> Void = { _ in }
    var onEditContact: (ContactCard) -> Void = { _ in }

    @State private var config = CiderConfig.load()
    @State private var detailsDraft: BookmarkDetailsDraft?
    @State private var detailsPresentationMode: DetailModalMode?
    @State private var detailsErrorMessage: String?
    @State private var selectedDateCard: DateCard?
    @State private var selectedContact: ContactCard?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Library Items

    private var filterSpec: SavedViewFilterSpec {
        SavedViewFilterSpec(
            entityTypes: entityFilter,
            labelIDs: [],
            folderID: selectedFolderID,
            includeCompleted: true,
            textQuery: searchText
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

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private func cardMinWidth(for mode: BookmarkCard.CardMode) -> CGFloat {
        cardSizing.bookmarkSizing.cardMinWidth
    }

    private var foldersByID: [UUID: Folder] {
        bookmarksViewModel.foldersByID
    }

    private var selectedDetailsBookmark: Bookmark? {
        guard let detailsDraft else { return nil }
        return bookmarksViewModel.bookmarks.first(where: { $0.id == detailsDraft.id })
    }

    private var isExpandMode: Bool {
        (detailsPresentationMode ?? config.detailModalMode) == .expand
    }

    private var shouldBlurContent: Bool {
        (isExpandMode && detailsDraft != nil) || selectedDateCard != nil || selectedContact != nil
    }

    var body: some View {
        ZStack {
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

                    ScrollView {
                        libraryFeed
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    .padding(Spacing.xxs)
                    .padding(.horizontal, Spacing.md)
                    .padding(.top, Spacing.md)
                    .padding(.bottom, Spacing.md)
                }
            }
            .blur(radius: shouldBlurContent ? BookmarksDesign.detailsContentBlurRadius : 0)
            .animation(reduceMotion ? .none : .snappy, value: shouldBlurContent)

            if isExpandMode, detailsDraft != nil {
                detailsOverlay
            }

            if selectedDateCard != nil {
                dateCardDetailOverlay
                    .transition(.opacity)
                    .animation(reduceMotion ? .none : .snappy, value: selectedDateCard != nil)
            }

            if selectedContact != nil {
                contactDetailOverlay
                    .transition(.opacity)
                    .animation(reduceMotion ? .none : .snappy, value: selectedContact != nil)
            }
        }
        .onChange(of: bookmarksViewModel.pendingDetailBookmarkID) { _, bookmarkID in
            guard let bookmarkID,
                  let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == bookmarkID })
            else { return }
            bookmarksViewModel.pendingDetailBookmarkID = nil
            presentDetails(for: bookmark)
        }
        .onChange(of: bookmarksViewModel.bookmarks.map(\.id)) { _, bookmarkIDs in
            guard let detailsDraft else { return }
            if !bookmarkIDs.contains(detailsDraft.id) {
                closeDetails()
            }
        }
        .onDisappear {
            if detailsDraft != nil {
                closeDetails()
            }
        }
    }

    // MARK: - Library Feed

    @ViewBuilder
    private var libraryFeed: some View {
        switch displayMode {
        case .list:
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(libraryItems) { item in
                    libraryListRow(item)
                }
            }

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .grid)
                }
            }

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(libraryItems) { item in
                    libraryCard(item, mode: .masonry)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
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
                onShowDetails: { handleNormalAction { presentDetails(for: bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { bookmarksViewModel.deleteBookmarks([bookmark]) },
                onMoveToFolder: { _ = bookmarksViewModel.assign(bookmark, toFolder: $0) },
                isSelected: isItemSelected(item),
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        case .note(let note):
            NoteListRow(
                note: note,
                cardSizing: cardSizing.noteSizing,
                searchText: "",
                folderName: folderName(for: note),
                folders: bookmarksViewModel.folders,
                isSelected: isItemSelected(item),
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
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        case .dateCard(let dateCard):
            DateCardListRow(
                dateCard: dateCard,
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
                    _ = DateCardStorage.shared.deleteDateCard(dateCard.id)
                    let trashItem = TrashStorage.shared.trashDateCard(dateCard, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                }
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
                    _ = ContactStorage.shared.deleteContact(contact.id)
                    let trashItem = TrashStorage.shared.trashContact(contact, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                }
            )
        case .externalFile(let file):
            SourceCardView(
                file: file,
                width: .infinity,
                isSelected: isItemSelected(item),
                onOpen: {
                    handleNormalAction {
                        NotificationCenter.default.post(
                            name: Notification.Name("cider.openExternalFile"),
                            object: nil,
                            userInfo: ["fileURL": file.path]
                        )
                    }
                },
                onDelete: { try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil) }
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
                onShowDetails: { handleNormalAction { presentDetails(for: bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { bookmarksViewModel.deleteBookmarks([bookmark]) },
                onMoveToFolder: { _ = bookmarksViewModel.assign(bookmark, toFolder: $0) },
                isSelected: isItemSelected(item),
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
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
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        case .dateCard(let dateCard):
            DateCardCardView(
                dateCard: dateCard,
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
                    _ = DateCardStorage.shared.deleteDateCard(dateCard.id)
                    let trashItem = TrashStorage.shared.trashDateCard(dateCard, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                }
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
                    _ = ContactStorage.shared.deleteContact(contact.id)
                    let trashItem = TrashStorage.shared.trashContact(contact, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                }
            )
        case .externalFile(let file):
            SourceCardView(
                file: file,
                width: cardMinWidth(for: mode),
                isSelected: isItemSelected(item),
                onOpen: {
                    handleNormalAction {
                        NotificationCenter.default.post(
                            name: Notification.Name("cider.openExternalFile"),
                            object: nil,
                            userInfo: ["fileURL": file.path]
                        )
                    }
                },
                onDelete: { try? FileManager.default.trashItem(at: file.path, resultingItemURL: nil) }
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

    // MARK: - Bookmark Details

    private func presentDetails(for bookmark: Bookmark) {
        let draft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsDraft = draft
        detailsErrorMessage = nil

        let presentationMode = config.detailModalMode
        detailsPresentationMode = presentationMode

        if presentationMode == .popover {
            showDetailsPopover(draft: draft)
        } else {
            requestPanelExpansionForDetails()
        }
    }

    private func closeDetails() {
        let presentationMode = detailsPresentationMode ?? config.detailModalMode
        if presentationMode == .popover {
            NotificationCenter.default.post(name: .dismissDetailPopover, object: nil)
        } else {
            requestPanelRestoreAfterDetails()
        }
        detailsPresentationMode = nil
        detailsDraft = nil
        detailsErrorMessage = nil
    }

    private func showDetailsPopover(draft: BookmarkDetailsDraft) {
        let draftBinding = Binding<BookmarkDetailsDraft>(
            get: { self.detailsDraft ?? draft },
            set: { next in
                self.detailsDraft = next
                self.detailsErrorMessage = nil
            }
        )

        let popoverContent = AnyView(
            BookmarkDetailsSheet(
                draft: draftBinding,
                bookmark: selectedDetailsBookmark,
                errorMessage: detailsErrorMessage,
                folders: bookmarksViewModel.folders,
                onDelete: { deleteDetailsBookmark() },
                onFolderChanged: { assignDetailsBookmarkToFolder($0) },
                onOpenURL: openDetailsURL,
                onCopyURL: copyDetailsURL,
                onSave: saveDetails,
                onCancel: { closeDetails() }
            )
            .padding(Spacing.xl)
        )

        NotificationCenter.default.post(
            name: .showDetailPopover,
            object: nil,
            userInfo: [
                "view": popoverContent,
                "preferredWidth": BookmarksDesign.detailsRequiredPanelWidth,
            ]
        )
    }

    private func requestPanelExpansionForDetails() {
        NotificationCenter.default.post(
            name: .expandCiderPanelForDetailModal,
            object: nil,
            userInfo: ["minimumWidth": BookmarksDesign.detailsRequiredPanelWidth]
        )
    }

    private func requestPanelRestoreAfterDetails() {
        NotificationCenter.default.post(name: .restoreCiderPanelAfterDetailModal, object: nil)
    }

    private func saveDetails() {
        guard let detailsDraft else { return }
        guard let selectedBookmark = selectedDetailsBookmark else {
            detailsErrorMessage = "This bookmark is no longer available."
            return
        }

        let parsedTags = detailsDraft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let didSave = bookmarksViewModel.updateDetails(
            for: selectedBookmark,
            title: detailsDraft.title,
            notes: detailsDraft.notes,
            tags: parsedTags
        )

        if didSave {
            closeDetails()
        } else {
            detailsErrorMessage = "Could not save bookmark details."
        }
    }

    private func deleteDetailsBookmark() {
        guard let bookmark = selectedDetailsBookmark else { return }
        closeDetails()
        bookmarksViewModel.deleteBookmarks([bookmark])
    }

    private func assignDetailsBookmarkToFolder(_ folderID: UUID?) {
        guard let bookmark = selectedDetailsBookmark else { return }
        _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
    }

    private func copyDetailsURL() {
        guard let detailsDraft else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(detailsDraft.urlString, forType: .string)
    }

    private func openDetailsURL() {
        guard let detailsDraft,
              let url = URL(string: detailsDraft.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Details Overlay

    @ViewBuilder
    private var detailsOverlay: some View {
        if let draft = detailsDraft {
            let draftBinding = Binding(
                get: { self.detailsDraft ?? draft },
                set: { next in
                    self.detailsDraft = next
                    detailsErrorMessage = nil
                }
            )

            GeometryReader { proxy in
                let sheetWidth = resolvedDetailsSheetWidth(for: proxy.size.width)
                let sheetHeight = resolvedDetailsSheetHeight(for: proxy.size.height)

                ZStack {
                    CiderColors.backdropSubtle
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeDetails()
                        }

                    BookmarkDetailsSheet(
                        draft: draftBinding,
                        bookmark: selectedDetailsBookmark,
                        errorMessage: detailsErrorMessage,
                        folders: bookmarksViewModel.folders,
                        onDelete: { deleteDetailsBookmark() },
                        onFolderChanged: { assignDetailsBookmarkToFolder($0) },
                        onOpenURL: openDetailsURL,
                        onCopyURL: copyDetailsURL,
                        onSave: saveDetails,
                        onCancel: { closeDetails() }
                    )
                    .frame(width: sheetWidth)
                    .frame(maxHeight: sheetHeight)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xxl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        }
    }

    private func resolvedDetailsSheetWidth(for containerWidth: CGFloat) -> CGFloat {
        let horizontalInset = Spacing.xxxl * 2
        let availableWidth = max(containerWidth - horizontalInset, 1)
        let minimumWidth = min(BookmarksDesign.detailsSheetMinWidth, availableWidth)
        let preferredWidth = max(minimumWidth, availableWidth * BookmarksDesign.detailsSheetPreferredWidthRatio)
        return min(preferredWidth, BookmarksDesign.detailsSheetMaxWidth)
    }

    private func resolvedDetailsSheetHeight(for containerHeight: CGFloat) -> CGFloat {
        let verticalInset = Spacing.xxxl * 2
        let availableHeight = max(containerHeight - verticalInset, 1)
        let minimumHeight = min(BookmarksDesign.detailsSheetMinHeight, availableHeight)
        let preferredHeight = max(minimumHeight, availableHeight * BookmarksDesign.detailsSheetPreferredHeightRatio)
        return min(preferredHeight, BookmarksDesign.detailsSheetMaxHeight)
    }

    // MARK: - Date Card & Contact Detail

    private func presentDateCardDetail(_ dateCard: DateCard) {
        selectedDateCard = dateCard
    }

    private func presentContactDetail(_ contact: ContactCard) {
        selectedContact = contact
    }

    @ViewBuilder
    private var dateCardDetailOverlay: some View {
        if let dateCard = selectedDateCard {
            GeometryReader { proxy in
                let sheetWidth = min(400, max(280, proxy.size.width - Spacing.xxxl * 2))
                ZStack {
                    CiderColors.backdropSubtle
                        .contentShape(Rectangle())
                        .onTapGesture { selectedDateCard = nil }

                    LibraryDetailModalContainer(
                        onClose: { selectedDateCard = nil },
                        onEdit: {
                            selectedDateCard = nil
                            onEditDateCard(dateCard)
                        }
                    ) {
                        DateCardDetailView(
                            dateCard: dateCard,
                            onEdit: {
                                selectedDateCard = nil
                                onEditDateCard(dateCard)
                            },
                            onDismiss: { selectedDateCard = nil }
                        )
                    }
                    .frame(width: sheetWidth)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xxl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var contactDetailOverlay: some View {
        if let contact = selectedContact {
            GeometryReader { proxy in
                let sheetWidth = min(420, max(280, proxy.size.width - Spacing.xxxl * 2))
                ZStack {
                    CiderColors.backdropSubtle
                        .contentShape(Rectangle())
                        .onTapGesture { selectedContact = nil }

                    LibraryDetailModalContainer(
                        onClose: { selectedContact = nil },
                        onEdit: {
                            selectedContact = nil
                            onEditContact(contact)
                        }
                    ) {
                        ContactDetailView(
                            contact: contact,
                            onEdit: {
                                selectedContact = nil
                                onEditContact(contact)
                            },
                            onDismiss: { selectedContact = nil }
                        )
                    }
                    .frame(width: sheetWidth)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xxl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Drag Providers

    private func handleContinueOpen(_ item: LibraryItemV2) {
        switch item {
        case .bookmark(let bookmark): presentDetails(for: bookmark)
        case .note(let note): openNoteInPanel(note)
        case .dateCard(let dateCard): presentDateCardDetail(dateCard)
        case .contact(let contact): presentContactDetail(contact)
        case .externalFile(let file):
            NotificationCenter.default.post(
                name: Notification.Name("cider.openExternalFile"),
                object: nil,
                userInfo: ["fileURL": file.path]
            )
        }
    }

    private func continueDragProvider(for item: LibraryItemV2) -> (() -> NSItemProvider)? {
        switch item {
        case .bookmark(let bookmark): return bookmarkDragProvider(for: bookmark)
        case .note(let note): return noteDragProvider(for: note)
        case .dateCard, .contact, .externalFile: return nil
        }
    }

    private func bookmarkDragProvider(for bookmark: Bookmark) -> () -> NSItemProvider {
        return {
            let itemID = "bookmark-\(bookmark.id.uuidString)"

            if selectedItemIDs.contains(itemID) && selectedItemIDs.count > 1 {
                let allItems = CiderMultiDrag.parseSelectedItemIDs(selectedItemIDs)
                return CiderMultiDrag.makeProvider(
                    primaryType: BookmarkDragPayload.typeIdentifier,
                    primaryID: bookmark.id,
                    allItemIDs: allItems
                )
            } else {
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
                    allItemIDs: allItems
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
