import AppKit
import SwiftUI

struct FolderDetailView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    let folderID: UUID
    @Binding var displayMode: LibraryDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var selectedItemIDs: Set<String>
    @Binding var subFoldersCollapsed: Bool
    var searchText: String = ""
    var onSelectSubFolder: ((UUID) -> Void)?
    var onOpenNote: ((Note) -> Void)?
    var onShowBookmarkDetails: ((Bookmark) -> Void)?
    var onEditDateCard: ((DateCard) -> Void)?
    var onEditContact: ((ContactCard) -> Void)?
    var onOpenDateCard: ((DateCard) -> Void)?
    var onOpenContact: ((ContactCard) -> Void)?
    var onOpenTodo: ((TodoCard) -> Void)?
    var onOpenVaultFile: ((VaultFile) -> Void)?
    var onToggleLabelBulk: ((UUID) -> Void)? = nil
    @Binding var scrollToItemID: String?
    var focusedItemID: String? = nil

    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared
    @ObservedObject private var vaultFileService = VaultFileService.shared
    @State private var selectionAnchorID: String?
    @State private var coverImage: NSImage?
    @State private var coverOffsetY: Double = 0.5
    @State private var isHoveringCover = false
    @State private var folderConfig = CiderConfig.load()
    @State private var tableColumnConfig: TableColumnConfig = CiderConfig.load().tableColumnConfig
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Data

    private var folder: Folder? {
        bookmarksViewModel.folders.first(where: { $0.id == folderID })
    }

    private var childFolders: [Folder] {
        bookmarksViewModel.folders
            .filter { $0.parentID == folderID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var folderItems: [LibraryItemV2] {
        let bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
            .map { LibraryItemV2.bookmark($0) }
        let notes = notesViewModel.notes.filter { $0.folderID == folderID }
            .map { LibraryItemV2.note($0) }
        let dateCards = dateCardStorage.dateCards.filter { $0.folderID == folderID }
            .map { LibraryItemV2.dateCard($0) }
        let contacts = contactStorage.contacts.filter { $0.folderID == folderID }
            .map { LibraryItemV2.contact($0) }
        let vaultFiles = vaultFileService.files(inFolder: folderID)
            .map { LibraryItemV2.vaultFile($0) }
        var all = (bookmarks + notes + dateCards + contacts + vaultFiles)
            .sorted { $0.createdDate > $1.createdDate }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let scope = SearchService.parseScope(from: query)
            if let scopeTypes = scope.entityTypes {
                all = all.filter { item in
                    switch item {
                    case .bookmark:     return scopeTypes.contains(.bookmark)
                    case .note:         return scopeTypes.contains(.note)
                    case .dateCard:     return scopeTypes.contains(.dateCard)
                    case .contact:      return scopeTypes.contains(.contact)
                    case .todo:         return scopeTypes.contains(.todo)
                    case .vaultFile:    return false
                    }
                }
            }
            if let labelID = scope.labelID {
                all = all.filter { $0.labelIDs.contains(labelID) }
            }
            if !scope.cleanQuery.isEmpty {
                all = all.filter { LibraryViewModel.matchesTextQuery(scope.cleanQuery, in: $0) }
            }
        }

        return all
    }

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private var foldersByID: [UUID: Folder] {
        bookmarksViewModel.foldersByID
    }

    /// Ancestors of the current folder (excluding itself), from root → parent.
    private var breadcrumbPath: [Folder] {
        let fullPath = bookmarksViewModel.folderPath(to: folderID)
        return Array(fullPath.dropLast())
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            if childFolders.isEmpty && folderItems.isEmpty && coverImage == nil {
                VStack(spacing: 0) {
                    folderHeader
                        .frame(maxWidth: .infinity, alignment: .leading)
                    emptyState
                }
                .frame(maxWidth: .infinity)
            } else {
                GeometryReader { contentProxy in
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                if coverImage != nil {
                                    folderCoverBanner
                                }

                                folderHeaderSection

                                if !folderItems.isEmpty {
                                    if displayMode == .list {
                                        LibraryTableHeader(
                                            columnConfig: $tableColumnConfig,
                                            allSelected: !folderItems.isEmpty && folderItems.allSatisfy { selectedItemIDs.contains($0.id) },
                                            onToggleSelectAll: {
                                                if folderItems.allSatisfy({ selectedItemIDs.contains($0.id) }) {
                                                    selectedItemIDs.removeAll()
                                                } else {
                                                    selectedItemIDs = Set(folderItems.map(\.id))
                                                }
                                            }
                                        )
                                        .onChange(of: tableColumnConfig) { _, newConfig in
                                            folderConfig.tableColumnConfig = newConfig
                                            folderConfig.save()
                                        }
                                    }
                                    let noPadding = displayMode == .list || displayMode == .kanban
                                    let viewportWidth = max(
                                        0,
                                        contentProxy.size.width - (noPadding ? 0 : (Spacing.xxs * 2) + (Spacing.md * 2))
                                    )
                                    libraryFeed(viewportWidth: viewportWidth)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(noPadding ? 0 : Spacing.xxs)
                                        .padding(.horizontal, noPadding ? 0 : Spacing.md)
                                        .padding(.vertical, noPadding ? 0 : Spacing.md)
                                } else {
                                    EmptyStateView(
                                        icon: "tray",
                                        title: "No items yet",
                                        subtitle: "Drag bookmarks or notes here, or add them from the sidebar"
                                    )
                                    .frame(minHeight: BookmarksDesign.detailsSheetNotesHeight)
                                }
                            }
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
                }
                .padding(.bottom, Spacing.md)
            }

        }
        .task(id: "\(folderID)-\(folder?.coverImagePath ?? "")-\(folder?.updatedAt.timeIntervalSinceReferenceDate ?? 0)") {
            await loadCoverImage()
            coverOffsetY = folder?.coverImageOffsetY ?? 0.5
        }
    }

    // MARK: - Folder Header Section

    private var folderHeaderSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            folderHeader

            if !childFolders.isEmpty && !subFoldersCollapsed {
                subFolderCards
                    .padding(.horizontal, Spacing.md + Spacing.xxs)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Folder Header

    private var folderHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Breadcrumbs (only if nested)
            if !breadcrumbPath.isEmpty {
                HStack(spacing: Spacing.xs) {
                    ForEach(Array(breadcrumbPath.enumerated()), id: \.element.id) { index, ancestor in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.quaternary)
                        }
                        Button {
                            onSelectSubFolder?(ancestor.id)
                        } label: {
                            Text(ancestor.name)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                    Image(systemName: "chevron.right")
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.quaternary)
                }
            }

            // Folder name + sub-folder toggle
            HStack(alignment: .lastTextBaseline) {
                if let icon = folder?.icon {
                    if folder?.iconIsEmoji == true {
                        Text(icon)
                            .font(CiderFont.display)
                    } else {
                        Image(systemName: icon)
                            .font(CiderFont.titleMedium)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                }
                Text(folder?.name ?? "Folder")
                    .font(CiderFont.titleMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
    
                if !childFolders.isEmpty {
                    Spacer()
                    SectionCollapseToggle(
                        label: "Folders",
                        isCollapsed: $subFoldersCollapsed
                    )
                    }
            }

            // Item count
            let total = folderItems.count
            let subCount = childFolders.count
            HStack(spacing: Spacing.sm) {
                if total > 0 {
                    Text("\(total) item\(total == 1 ? "" : "s")")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                if subCount > 0 {
                    Text("\(subCount) folder\(subCount == 1 ? "" : "s")")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                if total == 0 && subCount == 0 {
                    Text("Empty")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
            }
        }
        .padding(.horizontal, Spacing.md + Spacing.xxs)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.xs)
        .contextMenu {
            if coverImage != nil {
                Button("Change Cover Image...") { pickCoverImage() }
                Button("Remove Cover Image") { removeCoverImage() }
            } else {
                Button("Set Cover Image...") { pickCoverImage() }
            }
        }
    }

    // MARK: - Cover Banner

    private static let coverBannerHeight: CGFloat = 160

    private var folderCoverBanner: some View {
        GeometryReader { geo in
            if let coverImage {
                let imageAspect = coverImage.size.height / max(coverImage.size.width, 1)
                let imageHeight = geo.size.width * imageAspect
                let containerHeight = Self.coverBannerHeight
                let maxOffset = max(imageHeight - containerHeight, 0)

                Image(nsImage: coverImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: imageHeight)
                    .offset(y: -coverOffsetY * maxOffset)
                    .frame(width: geo.size.width, height: containerHeight, alignment: .top)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .overlay(alignment: .bottom) {
                        if isHoveringCover && maxOffset > 0 {
                            Text("Drag to reposition")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.textOnColor)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .background(Capsule().fill(CiderColors.coverBannerLabel))
                                .padding(.bottom, Spacing.sm)
                                .transition(.opacity)
                                .animation(reduceMotion ? .none : .snappy, value: isHoveringCover)
                        }
                    }
                    .overlay {
                        CoverRepositionOverlay(
                            maxOffset: maxOffset,
                            baseOffsetY: folder?.coverImageOffsetY ?? 0.5,
                            onOffsetChanged: { coverOffsetY = $0 },
                            onDragEnded: { bookmarksViewModel.setFolderCoverOffset(folderID, offsetY: $0) },
                            onHoverChanged: { isHoveringCover = $0 }
                        )
                    }
            }
        }
        .frame(height: Self.coverBannerHeight)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .padding(.horizontal, Spacing.md + Spacing.xxs)
        .padding(.top, Spacing.sm)
        .contextMenu {
            Button("Change Cover Image...") { pickCoverImage() }
            Button("Remove Cover Image") { removeCoverImage() }
        }
    }

    // MARK: - Cover Image Loading

    private func loadCoverImage() async {
        guard let folder,
              let url = bookmarksViewModel.folderCoverURL(for: folder) else {
            coverImage = nil
            return
        }

        let loaded = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as NSImage? }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                return nil as NSImage?
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value

        if !Task.isCancelled {
            coverImage = loaded
        }
    }

    private func pickCoverImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.title = "Choose Cover Image"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        bookmarksViewModel.setFolderCover(folderID, imageData: data)
    }

    private func removeCoverImage() {
        bookmarksViewModel.removeFolderCover(folderID)
    }

    // MARK: - Sub-Folder Cards

    private var subFolderCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: FolderDetailDesign.subFolderCardMinWidth, maximum: FolderDetailDesign.subFolderCardMaxWidth), spacing: Spacing.sm)],
            spacing: Spacing.sm
        ) {
            ForEach(childFolders) { folder in
                subFolderCard(folder)
            }
        }
    }

    private static let dropTypeIdentifiers = [
        MultiDragPayload.typeIdentifier,
        BookmarkDragPayload.typeIdentifier,
        NoteDragPayload.typeIdentifier,
        "public.utf8-plain-text"
    ]

    private func subFolderCard(_ folder: Folder) -> some View {
        let bookmarkCount = bookmarksViewModel.bookmarks.filter { $0.folderID == folder.id }.count
        let noteCount = notesViewModel.notes.filter { $0.folderID == folder.id }.count
        let totalItems = bookmarkCount + noteCount

        return Button {
            onSelectSubFolder?(folder.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "folder.fill")
                        .font(CiderFont.display)
                        .foregroundColor(CiderColors.controlAccent)

                    Spacer()

                    if totalItems > 0 {
                        Text("\(totalItems)")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(CiderColors.surfaceInput)
                            )
                    }
                }

                Text(folder.name)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                HStack(spacing: Spacing.sm) {
                    if bookmarkCount > 0 {
                        Label("\(bookmarkCount)", systemImage: "bookmark")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                    if noteCount > 0 {
                        Label("\(noteCount)", systemImage: "note.text")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                    if totalItems == 0 {
                        Text("Empty")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionContainer()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: Self.dropTypeIdentifiers, isTargeted: nil) { providers in
            handleSubFolderDrop(providers: providers, targetFolderID: folder.id)
        }
    }

    private func handleSubFolderDrop(providers: [NSItemProvider], targetFolderID: UUID) -> Bool {
        var handled = false

        let bvm = bookmarksViewModel
        let nvm = notesViewModel

        for provider in providers {
            // Multi-drag drop
            if provider.registeredTypeIdentifiers.contains(MultiDragPayload.typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: MultiDragPayload.typeIdentifier) { data, _ in
                    guard let data, let items = MultiDragPayload.decode(from: data) else { return }
                    Task { @MainActor in
                        for item in items {
                            if item.type == "bookmark",
                               let bookmark = bvm.bookmarks.first(where: { $0.id == item.id }) {
                                _ = bvm.assign(bookmark, toFolder: targetFolderID)
                            } else if item.type == "note",
                                      let note = nvm.notes.first(where: { $0.id == item.id }) {
                                _ = nvm.assignNote(note, toFolder: targetFolderID)
                            }
                        }
                    }
                }
                handled = true
                continue
            }

            // Bookmark drop
            if provider.hasItemConformingToTypeIdentifier(BookmarkDragPayload.typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: BookmarkDragPayload.typeIdentifier) { data, _ in
                    guard let data, let idString = String(data: data, encoding: .utf8),
                          let bookmarkID = UUID(uuidString: idString) else { return }
                    Task { @MainActor in
                        guard let bookmark = bvm.bookmarks.first(where: { $0.id == bookmarkID }) else { return }
                        _ = bvm.assign(bookmark, toFolder: targetFolderID)
                    }
                }
                handled = true
                continue
            }

            // Note drop
            if provider.hasItemConformingToTypeIdentifier(NoteDragPayload.typeIdentifier) {
                provider.loadDataRepresentation(forTypeIdentifier: NoteDragPayload.typeIdentifier) { data, _ in
                    guard let data, let idString = String(data: data, encoding: .utf8),
                          let noteID = UUID(uuidString: idString) else { return }
                    Task { @MainActor in
                        guard let note = nvm.notes.first(where: { $0.id == noteID }) else { return }
                        _ = nvm.assignNote(note, toFolder: targetFolderID)
                    }
                }
                handled = true
                continue
            }

            // Text fallback — also handles multi-drag
            provider.loadItem(forTypeIdentifier: "public.utf8-plain-text", options: nil) { item, _ in
                guard let data = item as? Data, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    if let items = MultiDragPayload.decodeFromText(text) {
                        for item in items {
                            if item.type == "bookmark",
                               let bookmark = bvm.bookmarks.first(where: { $0.id == item.id }) {
                                _ = bvm.assign(bookmark, toFolder: targetFolderID)
                            } else if item.type == "note",
                                      let note = nvm.notes.first(where: { $0.id == item.id }) {
                                _ = nvm.assignNote(note, toFolder: targetFolderID)
                            }
                        }
                    } else if let bookmarkID = BookmarkDragPayload.bookmarkID(from: text),
                              let bookmark = bvm.bookmarks.first(where: { $0.id == bookmarkID }) {
                        _ = bvm.assign(bookmark, toFolder: targetFolderID)
                    } else if let noteID = NoteDragPayload.noteID(from: text),
                              let note = nvm.notes.first(where: { $0.id == noteID }) {
                        _ = nvm.assignNote(note, toFolder: targetFolderID)
                    }
                }
            }
            handled = true
        }

        return handled
    }

    // MARK: - Library Feed

    @ViewBuilder
    private func libraryFeed(viewportWidth: CGFloat? = nil) -> some View {
        switch displayMode {
        case .list:
            LibraryTableRows(
                items: folderItems,
                labels: labelStorage.labels,
                folders: bookmarksViewModel.folders,
                columnConfig: tableColumnConfig,
                selectedItemIDs: selectedItemIDs,
                focusedItemID: focusedItemID,
                onOpen: { item in handleNormalAction { openItem(item) } },
                onSelect: { item in handleSelect(item: item) },
                onShiftSelect: { item in handleShiftSelect(item: item) }
            )

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(folderItems) { item in
                    libraryCard(item, mode: .grid)
                        .id(item.id)
                }
            }

        case .masonry:
            LazyMasonryView(
                items: folderItems,
                viewportWidth: viewportWidth,
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
                libraryCard(item, mode: .masonry, masonryCardWidth: columnWidth)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)

        case .kanban:
            FolderKanbanView(
                folderID: folderID,
                items: folderItems,
                onOpen: { item in handleNormalAction { openItem(item) } }
            )
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
                onShowDetails: { handleNormalAction { onShowBookmarkDetails?(bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { handleContextMenuDelete(item: item) { bookmarksViewModel.deleteBookmarks([bookmark]) } },
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
                    handleContextMenuDelete(item: item) { notesViewModel.deleteNotes([note]) }
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
                urgency: dateCard.urgency(windowDays: CiderConfig.load().dateCardSurfacingDays),
                onOpen: { (onOpenDateCard ?? onEditDateCard)?(dateCard) },
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
                onOpen: { (onOpenContact ?? onEditContact)?(contact) },
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
                onOpen: { onOpenTodo?(todoCard) },
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
        case .vaultFile(let file):
            VaultFileCardView(
                file: file,
                onOpen: { onOpenVaultFile?(file) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = file.folderID
                    VaultFileService.shared.assignFile(file.id, toFolder: folderID)
                    let folderName = bookmarksViewModel.folders.first(where: { $0.id == folderID })?.name ?? "Unfiled"
                    CiderUndoManager.shared.record(.movedToFolder(
                        itemType: .vaultFile, itemID: file.id, title: file.displayTitle,
                        fromFolderID: oldFolderID, toFolderID: folderID, folderName: folderName
                    ))
                },
                onDelete: {
                    handleContextMenuDelete(item: item) {
                        let trashItem = TrashStorage.shared.trashVaultFile(file)
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .vaultFile, trashItem: trashItem))
                    }
                },
                onToggleLabelBulk: onToggleLabelBulk,
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item) }
            )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "folder",
            title: "This folder is empty",
            subtitle: "Drag bookmarks or notes into this folder to organize them"
        )
    }

    // MARK: - Selection Helpers

    private func itemID(for item: LibraryItemV2) -> String {
        item.id
    }

    private func isItemSelected(_ item: LibraryItemV2) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    /// Handles context menu delete: if the item is part of a multi-selection, delete all selected items.
    /// Otherwise delete just the single item.
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
        let items = folderItems
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

    private func openItem(_ item: LibraryItemV2) {
        switch item {
        case .bookmark(let bookmark): onShowBookmarkDetails?(bookmark)
        case .note(let note): openNoteInPanel(note)
        case .dateCard(let dateCard): onOpenDateCard?(dateCard)
        case .contact(let contact): onOpenContact?(contact)
        case .todo(let todoCard): onOpenTodo?(todoCard)
        case .vaultFile(let vaultFile): onOpenVaultFile?(vaultFile)
        }
    }

    // MARK: - Helpers

    private func folderName(for note: Note) -> String? {
        guard let fID = note.folderID else { return nil }
        return foldersByID[fID]?.name
    }

    // MARK: - Note Panel

    private func openNoteInPanel(_ note: Note) {
        onOpenNote?(note)
    }

    // MARK: - Drag Providers

    private func bookmarkDragProvider(for bookmark: Bookmark) -> () -> NSItemProvider {
        return {
            let bookmarkItemID = itemID(for: .bookmark(bookmark))

            let isOptionHeld = NSEvent.modifierFlags.contains(.option)
            let hasImage = bookmark.originalImageFileURL != nil || bookmark.thumbnailFileURL != nil

            // Option+drag = export image to external apps (Finder, iMessage, etc.)
            // Use NSItemProvider(contentsOf:) so the provider carries the image file
            // without text — prevents text fields (Facebook) from receiving the title.
            if isOptionHeld && hasImage {
                let fileURL = bookmark.originalImageFileURL ?? bookmark.thumbnailFileURL
                if let fileURL, let provider = NSItemProvider(contentsOf: fileURL) {
                    let ext = fileURL.pathExtension
                    let base = (bookmark.title as NSString).pathExtension.lowercased() == ext.lowercased()
                        ? (bookmark.title as NSString).deletingPathExtension
                        : bookmark.title
                    provider.suggestedName = base + "." + ext
                    return provider
                }
                // Fallback: raw image data
                let provider = NSItemProvider()
                BookmarkDragPayload.registerPublicImage(on: provider, bookmark: bookmark)
                return provider
            }

            if selectedItemIDs.contains(bookmarkItemID) && selectedItemIDs.count > 1 {
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
            let noteItemID = itemID(for: .note(note))

            if selectedItemIDs.contains(noteItemID) && selectedItemIDs.count > 1 {
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
                // NOTE: Do NOT register additional types (registerFileRepresentation,
                // registerDataRepresentation for markdown, or public.file-url) here —
                // any extra type registration breaks SwiftUI's .onDrop, causing providers
                // to arrive with empty registeredTypeIdentifiers (internal folder drops
                // silently fail). Finder drag-out is sacrificed for internal drag-to-folder.
                return provider
            }
        }
    }

    // MARK: - Multi-Drag Preview

    private func multiDragPreview(for item: LibraryItemV2) -> AnyView? {
        let id = item.id
        guard selectedItemIDs.contains(id), selectedItemIDs.count > 1 else { return nil }

        var previewItems: [MultiDragPreviewItem] = [multiDragPreviewItem(from: item)].compactMap { $0 }
        for libraryItem in folderItems where isItemSelected(libraryItem) && libraryItem.id != id {
            if let preview = multiDragPreviewItem(from: libraryItem) {
                previewItems.append(preview)
            }
            if previewItems.count >= 3 { break }
        }

        return AnyView(MultiDragPreview(items: previewItems, totalCount: selectedItemIDs.count))
    }

    private func multiDragPreviewItem(from item: LibraryItemV2) -> MultiDragPreviewItem? {
        switch item {
        case .bookmark(let b): return .bookmark(b)
        case .note(let n): return .note(n)
        case .dateCard, .contact, .todo, .vaultFile: return nil
        }
    }
}

// MARK: - Cover Reposition Overlay

/// Transparent NSView overlay that prevents `isMovableByWindowBackground` from
/// starting a window drag on the cover image, and handles drag-to-reposition
/// via AppKit mouse events (since SwiftUI DragGesture can't override
/// `mouseDownCanMoveWindow`).
private struct CoverRepositionOverlay: NSViewRepresentable {
    var maxOffset: CGFloat
    var baseOffsetY: Double
    var onOffsetChanged: (Double) -> Void
    var onDragEnded: (Double) -> Void
    var onHoverChanged: (Bool) -> Void

    func makeNSView(context: Context) -> CoverRepositionNSView {
        let view = CoverRepositionNSView()
        view.maxOffset = maxOffset
        view.baseOffsetY = baseOffsetY
        view.onOffsetChanged = onOffsetChanged
        view.onDragEnded = onDragEnded
        view.onHoverChanged = onHoverChanged
        return view
    }

    func updateNSView(_ nsView: CoverRepositionNSView, context: Context) {
        nsView.maxOffset = maxOffset
        nsView.baseOffsetY = baseOffsetY
        nsView.onOffsetChanged = onOffsetChanged
        nsView.onDragEnded = onDragEnded
        nsView.onHoverChanged = onHoverChanged
    }
}

private final class CoverRepositionNSView: NSView {
    var maxOffset: CGFloat = 0
    var baseOffsetY: Double = 0.5
    var onOffsetChanged: ((Double) -> Void)?
    var onDragEnded: ((Double) -> Void)?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Hover Tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    // MARK: - Drag Handling (event loop pattern — same as PanelEdgeResizeView)

    override func mouseDown(with event: NSEvent) {
        guard maxOffset > 0, let window else {
            super.mouseDown(with: event)
            return
        }

        let startY = event.locationInWindow.y
        let startBase = baseOffsetY
        var current = startBase

        var keepRunning = true
        while keepRunning {
            guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }

            switch next.type {
            case .leftMouseDragged:
                let deltaY = next.locationInWindow.y - startY
                // Dragging up (positive deltaY) → reveal more bottom → increase offsetY
                let newOffset = min(max(startBase + deltaY / maxOffset, 0), 1)
                current = newOffset
                onOffsetChanged?(newOffset)
            case .leftMouseUp:
                onDragEnded?(current)
                keepRunning = false
            default:
                break
            }
        }
    }
}
