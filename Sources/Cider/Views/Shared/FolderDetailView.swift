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
    var onEditDateCard: ((DateCard) -> Void)?
    var onEditContact: ((ContactCard) -> Void)?

    @ObservedObject private var dateCardStorage = DateCardStorage.shared
    @ObservedObject private var contactStorage = ContactStorage.shared

    @State private var selectionAnchorID: String?
    @State private var detailsDraft: BookmarkDetailsDraft?
    @State private var detailsPresentationMode: DetailModalMode?
    @State private var detailsErrorMessage: String?
    @State private var coverImage: NSImage?
    @State private var coverOffsetY: Double = 0.5
    @State private var isHoveringCover = false

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
        var all = (bookmarks + notes + dateCards + contacts)
            .sorted { $0.createdDate > $1.createdDate }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            all = all.filter { LibraryViewModel.matchesTextQuery(query, in: $0) }
        }

        return all
    }

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private var foldersByID: [UUID: Folder] {
        bookmarksViewModel.foldersByID
    }

    private var selectedDetailsBookmark: Bookmark? {
        guard let detailsDraft else { return nil }
        return bookmarksViewModel.bookmarks.first(where: { $0.id == detailsDraft.id })
    }

    private var isExpandMode: Bool {
        (detailsPresentationMode ?? CiderConfig.load().detailModalMode) == .expand
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
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if coverImage != nil {
                            folderCoverBanner
                        }

                        folderHeaderSection

                        if !folderItems.isEmpty {
                            libraryFeed
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Spacing.xxs)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.md)
                        } else {
                            EmptyStateView(
                                icon: "tray",
                                title: "No items yet",
                                subtitle: "Drag bookmarks or notes here, or add them from the sidebar"
                            )
                            .frame(minHeight: 200)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(.bottom, Spacing.md)
            }

            if isExpandMode, detailsDraft != nil {
                detailsOverlay
            }
        }
        .blur(radius: (isExpandMode && detailsDraft != nil) ? BookmarksDesign.detailsContentBlurRadius : 0)
        .animation(reduceMotion ? .none : .snappy, value: detailsDraft != nil)
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
                                .foregroundColor(.white)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
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
            columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: Spacing.sm)],
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
    private var libraryFeed: some View {
        switch displayMode {
        case .list:
            LazyVStack(spacing: Spacing.xxs) {
                ForEach(folderItems) { item in
                    libraryListRow(item)
                }
            }

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(folderItems) { item in
                    libraryCard(item, mode: .grid)
                }
            }

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(folderItems) { item in
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
                onOpen: { onEditDateCard?(dateCard) },
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
                onOpen: { onEditContact?(contact) },
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
        case .externalFile:
            EmptyView()
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
                onOpen: { onEditDateCard?(dateCard) },
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
                onOpen: { onEditContact?(contact) },
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
        case .externalFile:
            EmptyView()
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

    // MARK: - Helpers

    private func folderName(for note: Note) -> String? {
        guard let fID = note.folderID else { return nil }
        return foldersByID[fID]?.name
    }

    // MARK: - Note Panel

    private func openNoteInPanel(_ note: Note) {
        onOpenNote?(note)
    }

    // MARK: - Bookmark Details

    private func presentDetails(for bookmark: Bookmark) {
        let draft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsDraft = draft
        detailsErrorMessage = nil

        let presentationMode = CiderConfig.load().detailModalMode
        detailsPresentationMode = presentationMode

        if presentationMode == .popover {
            showDetailsPopover(draft: draft)
        } else {
            requestPanelExpansionForDetails()
        }
    }

    private func closeDetails() {
        let presentationMode = detailsPresentationMode ?? CiderConfig.load().detailModalMode
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

    // MARK: - Drag Providers

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
        case .dateCard, .contact, .externalFile: return nil
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
