import AppKit
import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    var selectedFolderID: UUID?
    @Binding var displayMode: LibraryDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var continueSectionCollapsed: Bool
    @Binding var selectedItemIDs: Set<String>
    @State private var config = CiderConfig.load()
    @State private var detailsDraft: BookmarkDetailsDraft?
    @State private var detailsErrorMessage: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Library Items

    /// Continue section always shows global recents regardless of folder selection
    private var continueItems: [LibraryItem] {
        let bookmarkItems = bookmarksViewModel.bookmarks.map { LibraryItem.bookmark($0) }
        let noteItems = notesViewModel.notes.map { LibraryItem.note($0) }
        return (bookmarkItems + noteItems)
            .sorted { $0.date > $1.date }
            .prefix(8)
            .map { $0 }
    }

    /// Library feed filters by folder when one is selected
    private var libraryItems: [LibraryItem] {
        let bookmarks: [Bookmark]
        let notes: [Note]

        if let folderID = selectedFolderID {
            bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
            notes = notesViewModel.notes.filter { $0.folderID == folderID }
        } else {
            bookmarks = bookmarksViewModel.bookmarks
            notes = notesViewModel.notes
        }

        let bookmarkItems = bookmarks.map { LibraryItem.bookmark($0) }
        let noteItems = notes.map { LibraryItem.note($0) }
        return (bookmarkItems + noteItems)
            .sorted { $0.createdDate > $1.createdDate }
    }

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private var foldersByID: [UUID: Folder] {
        Dictionary(uniqueKeysWithValues: bookmarksViewModel.folders.map { ($0.id, $0) })
    }

    private var selectedDetailsBookmark: Bookmark? {
        guard let detailsDraft else { return nil }
        return bookmarksViewModel.bookmarks.first(where: { $0.id == detailsDraft.id })
    }

    private var isExpandMode: Bool {
        CiderConfig.load().detailModalMode == .expand
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if libraryItems.isEmpty {
                    // No scrollable content — show recents normally above empty state
                    if config.showContinueSection && !continueItems.isEmpty && !continueSectionCollapsed {
                        ContinueSectionView(
                            items: continueItems,
                            onOpenBookmark: { presentDetails(for: $0) },
                            onOpenNote: { note in openNoteInPanel(note) },
                            dragProviderForItem: continueDragProvider
                        )
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.md)
                    }
                    emptyState
                } else {
                    if config.showContinueSection && !continueItems.isEmpty {
                        CollapsiblePinnedSection(isCollapsed: $continueSectionCollapsed) {
                            ContinueSectionView(
                                items: continueItems,
                                onOpenBookmark: { presentDetails(for: $0) },
                                onOpenNote: { note in openNoteInPanel(note) },
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
            .blur(radius: (isExpandMode && detailsDraft != nil) ? BookmarksDesign.detailsContentBlurRadius : 0)
            .animation(reduceMotion ? .none : .snappy, value: detailsDraft != nil)

            if isExpandMode, detailsDraft != nil {
                detailsOverlay
            }
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
    private func libraryListRow(_ item: LibraryItem) -> some View {
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
        }
    }

    // MARK: - Card (Grid / Masonry)

    @ViewBuilder
    private func libraryCard(_ item: LibraryItem, mode: BookmarkCard.CardMode) -> some View {
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

    private func itemID(for item: LibraryItem) -> String {
        switch item {
        case .bookmark(let b): return "bookmark-\(b.id.uuidString)"
        case .note(let n): return "note-\(n.id.uuidString)"
        }
    }

    private func isItemSelected(_ item: LibraryItem) -> Bool {
        selectedItemIDs.contains(itemID(for: item))
    }

    @State private var selectionAnchorID: String?

    private func handleSelect(item: LibraryItem) {
        let id = itemID(for: item)
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
        selectionAnchorID = id
    }

    private func handleShiftSelect(item: LibraryItem) {
        let id = itemID(for: item)
        let items = libraryItems
        guard let anchorID = selectionAnchorID,
              let anchorIndex = items.firstIndex(where: { itemID(for: $0) == anchorID }),
              let clickedIndex = items.firstIndex(where: { itemID(for: $0) == id }) else {
            selectedItemIDs.insert(id)
            selectionAnchorID = id
            return
        }

        let range = min(anchorIndex, clickedIndex) ... max(anchorIndex, clickedIndex)
        for i in range {
            selectedItemIDs.insert(itemID(for: items[i]))
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
        NotificationCenter.default.post(
            name: .openNoteInPanel,
            object: note,
            userInfo: ["modal": true]
        )
    }

    // MARK: - Bookmark Details

    private func presentDetails(for bookmark: Bookmark) {
        let draft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsDraft = draft
        detailsErrorMessage = nil

        let config = CiderConfig.load()
        if config.detailModalMode == .popover {
            showDetailsPopover(draft: draft)
        } else {
            requestPanelExpansionForDetails()
        }
    }

    private func closeDetails() {
        let config = CiderConfig.load()
        if config.detailModalMode == .popover {
            NotificationCenter.default.post(name: .dismissDetailPopover, object: nil)
        } else {
            requestPanelRestoreAfterDetails()
        }
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

    // MARK: - Drag Providers

    private func continueDragProvider(for item: LibraryItem) -> (() -> NSItemProvider)? {
        switch item {
        case .bookmark(let bookmark):
            return bookmarkDragProvider(for: bookmark)
        case .note(let note):
            return noteDragProvider(for: note)
        }
    }

    private func bookmarkDragProvider(for bookmark: Bookmark) -> () -> NSItemProvider {
        return {
            let bookmarkItemID = itemID(for: .bookmark(bookmark))

            if selectedItemIDs.contains(bookmarkItemID) && selectedItemIDs.count > 1 {
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
            let noteItemID = itemID(for: .note(note))

            if selectedItemIDs.contains(noteItemID) && selectedItemIDs.count > 1 {
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

    private func multiDragPreview(for item: LibraryItem) -> AnyView? {
        let id = itemID(for: item)
        guard selectedItemIDs.contains(id), selectedItemIDs.count > 1 else { return nil }

        var previewItems: [MultiDragPreviewItem] = [multiDragPreviewItem(from: item)]
        for libraryItem in libraryItems where isItemSelected(libraryItem) && itemID(for: libraryItem) != id {
            previewItems.append(multiDragPreviewItem(from: libraryItem))
            if previewItems.count >= 3 { break }
        }

        return AnyView(MultiDragPreview(items: previewItems, totalCount: selectedItemIDs.count))
    }

    private func multiDragPreviewItem(from item: LibraryItem) -> MultiDragPreviewItem {
        switch item {
        case .bookmark(let b): return .bookmark(b)
        case .note(let n): return .note(n)
        }
    }
}
