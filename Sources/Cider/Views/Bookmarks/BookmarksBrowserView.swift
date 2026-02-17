import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BookmarksBrowserView: View {
    let bookmarks: [Bookmark]
    var folders: [Folder] = []
    @Binding var displayMode: BookmarkDisplayMode
    @Binding var cardSizeScale: Double
    @Binding var selectedItemIDs: Set<String>
    var searchText: String = ""
    var onOpenBookmark: (Bookmark) -> Void
    var onShowBookmarkDetails: ((Bookmark) -> Void)? = nil
    var onDeleteBookmark: ((Bookmark) -> Void)? = nil
    var onAddBookmark: (String, String?) -> Bool
    var onUpdateBookmarkDetails: ((Bookmark, String, String, [String]) -> Bool)? = nil
    var onAssignThumbnailFromDroppedString: ((Bookmark, String) -> Bool)? = nil
    var onAssignThumbnailFromLocalFileURL: ((Bookmark, URL) -> Bool)? = nil
    var onAssignThumbnailFromImageData: ((Bookmark, Data, String?) -> Bool)? = nil
    var onAssignBookmarkToFolder: ((Bookmark, UUID?) -> Bool)? = nil
    var onCreateFolder: ((String, UUID?) -> Folder?)? = nil
    var showsInternalFolderSidebar = true

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectionAnchorID: String?
    @State private var isAddFormVisible = false
    @State private var draftTitle = ""
    @State private var draftURL = ""
    @State private var addErrorMessage: String?
    @State private var isDropTargeted = false
    @State private var isFolderSidebarVisible = true
    @State private var isFolderCreationFieldVisible = false
    @State private var draftFolderName = ""
    @State private var draggedBookmarkID: UUID?
    @State private var selectedFolderID: UUID?
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var dragStateResetTask: DispatchWorkItem?

    private var hasVisibleBookmarks: Bool {
        !displayedBookmarks.isEmpty
    }

    private var displayedBookmarks: [Bookmark] {
        guard let folderID = selectedFolderID else { return bookmarks }
        return bookmarks.filter { $0.folderID == folderID }
    }

    private var supportsFolderShelf: Bool {
        onAssignBookmarkToFolder != nil
    }

    private var isDraggingBookmark: Bool {
        draggedBookmarkID != nil
    }

    private var shouldShowFolderSidebar: Bool {
        showsInternalFolderSidebar && supportsFolderShelf && (isFolderSidebarVisible || isDraggingBookmark)
    }

    private var topLevelFolders: [Folder] {
        childFolders(of: nil)
    }

    private var folderDropTypeIdentifiers: [String] {
        [
            MultiDragPayload.typeIdentifier,
            BookmarkDragPayload.typeIdentifier,
            UTType.text.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
        ]
    }

    private var foldersFingerprint: String {
        folders
            .map { "\($0.id.uuidString):\($0.parentID?.uuidString ?? "root"):\($0.name)" }
            .joined(separator: "|")
    }

    private var cardSizing: CardSizing {
        CardSizing(scale: cardSizeScale)
    }

    private var cardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if isAddFormVisible {
                addForm
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(alignment: .top, spacing: Spacing.md) {
                if shouldShowFolderSidebar {
                    folderSidebar
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                if hasVisibleBookmarks {
                    ScrollView(showsIndicators: false) {
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? CiderColors.dropTargetBorderStrong : Color.clear,
                    lineWidth: CiderBorder.innerStrokeWidth
                )
        )
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .onDrop(
            of: [UTType.url.identifier, UTType.plainText.identifier],
            isTargeted: $isDropTargeted,
            perform: handleBrowserDrop(providers:)
        )
        .onChange(of: foldersFingerprint) { _, _ in
            normalizeFolderState()
        }
        .onDisappear {
            cancelDragStateReset()
        }
        .animation(reduceMotion ? .none : .snappy, value: shouldShowFolderSidebar)
        .onReceive(NotificationCenter.default.publisher(for: .showBookmarkAddForm)) { _ in
            withAnimation(reduceMotion ? .none : .snappy) {
                isAddFormVisible = true
            }
        }
        .help("Drop a URL to save bookmark")
    }

    @ViewBuilder
    private var addForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            TextField("Title (optional)", text: $draftTitle)
                .textFieldStyle(.roundedBorder)

            TextField("https://example.com", text: $draftURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commitAddBookmark() }

            HStack(spacing: Spacing.sm) {
                Button("Save") {
                    commitAddBookmark()
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.controlAccent)

                Button("Cancel") {
                    closeAddForm(resetFields: true)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.secondary)

                Spacer(minLength: Spacing.sm)

                if let addErrorMessage {
                    Text(addErrorMessage)
                        .font(CiderFont.body(scale: textScale))
                        .foregroundColor(CiderColors.destructive)
                        .lineLimit(1)
                }
            }
        }
        .padding(Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceElevated)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch displayMode {
        case .list:
            LazyVStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(displayedBookmarks) { bookmark in
                    BookmarkListRow(
                        bookmark: bookmark,
                        searchText: searchText,
                        cardSizing: cardSizing,
                        folders: folders,
                        dragProvider: bookmarkDragProvider(for: bookmark),
                        dragPreviewOverride: multiDragPreview(for: bookmark),
                        onShowDetails: { handleNormalAction { onShowBookmarkDetails?(bookmark) } },
                        onOpen: { handleNormalAction { onOpenBookmark(bookmark) } },
                        onDelete: { onDeleteBookmark?(bookmark) },
                        onMoveToFolder: { _ = onAssignBookmarkToFolder?(bookmark, $0) },
                        isSelected: isBookmarkSelected(bookmark),
                        onSelect: { handleSelect(bookmark: bookmark) },
                        onShiftSelect: { handleShiftSelect(bookmark: bookmark) }
                    )
                }
            }

        case .grid:
            LazyVGrid(
                columns: cardColumns,
                spacing: Spacing.md
            ) {
                ForEach(displayedBookmarks) { bookmark in
                    BookmarkCard(
                        bookmark: bookmark,
                        searchText: searchText,
                        mode: .grid,
                        cardSizing: cardSizing,
                        folders: folders,
                        dragProvider: bookmarkDragProvider(for: bookmark),
                        dragPreviewOverride: multiDragPreview(for: bookmark),
                        onShowDetails: { handleNormalAction { onShowBookmarkDetails?(bookmark) } },
                        onOpen: { handleNormalAction { onOpenBookmark(bookmark) } },
                        onDelete: { onDeleteBookmark?(bookmark) },
                        onMoveToFolder: { _ = onAssignBookmarkToFolder?(bookmark, $0) },
                        isSelected: isBookmarkSelected(bookmark),
                        onSelect: { handleSelect(bookmark: bookmark) },
                        onShiftSelect: { handleShiftSelect(bookmark: bookmark) },
                        onAssignThumbnailFromDroppedString: onAssignThumbnailFromDroppedString,
                        onAssignThumbnailFromLocalFileURL: onAssignThumbnailFromLocalFileURL,
                        onAssignThumbnailFromImageData: onAssignThumbnailFromImageData
                    )
                }
            }

        case .masonry:
            MasonryLayout(
                minimumColumnWidth: cardSizing.cardMinWidth,
                itemSpacing: Spacing.md
            ) {
                ForEach(displayedBookmarks) { bookmark in
                    BookmarkCard(
                        bookmark: bookmark,
                        searchText: searchText,
                        mode: .masonry,
                        cardSizing: cardSizing,
                        folders: folders,
                        dragProvider: bookmarkDragProvider(for: bookmark),
                        dragPreviewOverride: multiDragPreview(for: bookmark),
                        onShowDetails: { handleNormalAction { onShowBookmarkDetails?(bookmark) } },
                        onOpen: { handleNormalAction { onOpenBookmark(bookmark) } },
                        onDelete: { onDeleteBookmark?(bookmark) },
                        onMoveToFolder: { _ = onAssignBookmarkToFolder?(bookmark, $0) },
                        isSelected: isBookmarkSelected(bookmark),
                        onSelect: { handleSelect(bookmark: bookmark) },
                        onShiftSelect: { handleShiftSelect(bookmark: bookmark) },
                        onAssignThumbnailFromDroppedString: onAssignThumbnailFromDroppedString,
                        onAssignThumbnailFromLocalFileURL: onAssignThumbnailFromLocalFileURL,
                        onAssignThumbnailFromImageData: onAssignThumbnailFromImageData
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, Spacing.xs)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "bookmark")
                .font(CiderFont.heroDisplay(scale: textScale))
                .foregroundColor(CiderColors.tertiary)

            Text(selectedFolderID == nil ? "No bookmarks yet" : "No bookmarks in this folder")
                .font(CiderFont.subheadingMedium(scale: textScale))
                .foregroundColor(CiderColors.secondary)

            Text(selectedFolderID == nil
                ? "Add one with the + button or paste from clipboard"
                : "Try another folder or drag bookmarks into this one")
                .font(CiderFont.body(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xxl)
    }

    @ViewBuilder
    private var folderSidebar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Label("Folders", systemImage: "folder")
                    .font(CiderFont.bodySemibold(scale: textScale))
                    .foregroundColor(CiderColors.secondary)

                Spacer(minLength: Spacing.sm)

                Button(action: toggleFolderCreationField) {
                    Image(systemName: isFolderCreationFieldVisible ? "xmark" : "folder.badge.plus")
                        .font(CiderFont.bodySemibold(scale: textScale))
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                }
                .buttonStyle(.plain)
                .foregroundColor(CiderColors.secondary)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .help(isFolderCreationFieldVisible ? "Cancel new folder" : "Create folder")
            }

            BookmarkFolderSidebarRow(
                title: "All Bookmarks",
                bookmarkCount: bookmarks.count,
                depth: 0,
                hasChildren: !topLevelFolders.isEmpty,
                isExpanded: true,
                isSelected: selectedFolderID == nil,
                dropTypeIdentifiers: folderDropTypeIdentifiers,
                onTap: { selectFolder(nil) },
                onToggleExpand: nil,
                onHoverChanged: { _ in },
                onDropTargetChanged: { _ in },
                onDropProviders: { providers in
                    handleFolderDrop(providers: providers, targetFolderID: nil)
                }
            )

            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: Spacing.xxs) {
                    ForEach(topLevelFolders) { folder in
                        folderSidebarBranch(folder, depth: 0)
                    }
                }
                .padding(.bottom, Spacing.xs)
            }

            if topLevelFolders.isEmpty {
                Text("No folders yet. Create one and drag bookmarks into it.")
                    .font(CiderFont.body(scale: textScale))
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.bottom, Spacing.xs)
            }

            if isFolderCreationFieldVisible {
                HStack(spacing: Spacing.sm) {
                    TextField("New folder name", text: $draftFolderName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            commitFolderCreation()
                        }

                    Button("Create") {
                        commitFolderCreation()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(CiderColors.controlAccent)
                }
            }
        }
        .padding(Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .sectionContainer()
    }

    private func folderSidebarBranch(_ folder: Folder, depth: Int) -> AnyView {
        let children = childFolders(of: folder.id)
        let isExpanded = expandedFolderIDs.contains(folder.id)
        return AnyView(
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                BookmarkFolderSidebarRow(
                    title: folder.name,
                    bookmarkCount: bookmarksInFolder(folder.id).count,
                    depth: depth,
                    hasChildren: !children.isEmpty,
                    isExpanded: isExpanded,
                    isSelected: selectedFolderID == folder.id,
                    dropTypeIdentifiers: folderDropTypeIdentifiers,
                    onTap: { selectFolder(folder.id) },
                    onToggleExpand: !children.isEmpty ? {
                        if isExpanded {
                            expandedFolderIDs.remove(folder.id)
                        } else {
                            expandedFolderIDs.insert(folder.id)
                        }
                    } : nil,
                    onHoverChanged: { hovering in
                        guard hovering, isDraggingBookmark, !children.isEmpty else { return }
                        expandedFolderIDs.insert(folder.id)
                    },
                    onDropTargetChanged: { targeted in
                        guard targeted, !children.isEmpty else { return }
                        expandedFolderIDs.insert(folder.id)
                    },
                    onDropProviders: { providers in
                        handleFolderDrop(providers: providers, targetFolderID: folder.id)
                    }
                )

                if isExpanded {
                    ForEach(children) { child in
                        folderSidebarBranch(child, depth: depth + 1)
                    }
                }
            }
        )
    }

    private func toggleFolderSidebar() {
        guard supportsFolderShelf else { return }
        withAnimation(reduceMotion ? .none : .snappy) {
            isFolderSidebarVisible.toggle()
            if !isFolderSidebarVisible {
                isFolderCreationFieldVisible = false
                draftFolderName = ""
            }
        }
    }

    private func toggleFolderCreationField() {
        guard supportsFolderShelf else { return }
        withAnimation(reduceMotion ? .none : .snappy) {
            isFolderCreationFieldVisible.toggle()
            if isFolderCreationFieldVisible {
                isFolderSidebarVisible = true
            } else {
                draftFolderName = ""
            }
        }
    }

    private func scheduleDragStateReset() {
        cancelDragStateReset()
        let task = DispatchWorkItem {
            draggedBookmarkID = nil
        }
        dragStateResetTask = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + BookmarksDesign.folderShelfDragStateTimeout,
            execute: task
        )
    }

    private func cancelDragStateReset() {
        dragStateResetTask?.cancel()
        dragStateResetTask = nil
    }

    private func normalizeFolderState() {
        let validFolderIDs = Set(folders.map(\.id))
        if let selectedFolderID, !validFolderIDs.contains(selectedFolderID) {
            self.selectedFolderID = nil
        }
        expandedFolderIDs = expandedFolderIDs.filter { validFolderIDs.contains($0) }
    }

    private func selectFolder(_ folderID: UUID?) {
        guard selectedFolderID != folderID else { return }
        selectedFolderID = folderID
        if let folderID {
            expandPath(to: folderID)
        }
    }

    private func commitFolderCreation() {
        guard let onCreateFolder else { return }
        let trimmed = draftFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let created = onCreateFolder(trimmed, selectedFolderID)
        guard let created else { return }

        draftFolderName = ""
        isFolderCreationFieldVisible = false
        selectFolder(created.id)
    }

    private func bookmarksInFolder(_ folderID: UUID) -> [Bookmark] {
        bookmarks.filter { $0.folderID == folderID }
    }

    private func hasChildFolders(_ folderID: UUID) -> Bool {
        folders.contains(where: { $0.parentID == folderID })
    }

    private func childFolders(of parentID: UUID?) -> [Folder] {
        folders
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                let nameComparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameComparison != .orderedSame {
                    return nameComparison == .orderedAscending
                }
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private func folderPath(to folderID: UUID) -> [Folder] {
        let folderByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var path: [Folder] = []
        var cursorID: UUID? = folderID
        var visited = Set<UUID>()

        while let currentID = cursorID,
              !visited.contains(currentID),
              let folder = folderByID[currentID] {
            visited.insert(currentID)
            path.append(folder)
            cursorID = folder.parentID
        }

        return path.reversed()
    }

    private func expandPath(to folderID: UUID) {
        let path = folderPath(to: folderID)
        for folder in path.dropLast() {
            expandedFolderIDs.insert(folder.id)
        }
    }

    private func bookmarkDragProvider(for bookmark: Bookmark) -> (() -> NSItemProvider)? {
        guard supportsFolderShelf else { return nil }
        return {
            beginBookmarkDrag(for: bookmark.id)
            let bookmarkItemID = itemID(for: bookmark)

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

    private func multiDragPreview(for bookmark: Bookmark) -> AnyView? {
        guard isBookmarkSelected(bookmark), selectedItemIDs.count > 1 else { return nil }

        var items: [MultiDragPreviewItem] = [.bookmark(bookmark)]
        for b in displayedBookmarks where isBookmarkSelected(b) && b.id != bookmark.id {
            items.append(.bookmark(b))
            if items.count >= 3 { break }
        }

        return AnyView(MultiDragPreview(items: items, totalCount: selectedItemIDs.count))
    }

    private func beginBookmarkDrag(for bookmarkID: UUID) {
        draggedBookmarkID = bookmarkID
        scheduleDragStateReset()
    }

    private func handleFolderDrop(providers: [NSItemProvider], targetFolderID: UUID?) -> Bool {
        for provider in providers where provider.registeredTypeIdentifiers.contains(MultiDragPayload.typeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: MultiDragPayload.typeIdentifier) { data, _ in
                guard let data, let items = MultiDragPayload.decode(from: data) else { return }
                DispatchQueue.main.async {
                    for item in items where item.type == "bookmark" {
                        assignDraggedBookmark(bookmarkID: item.id, toFolder: targetFolderID)
                    }
                }
            }
            return true
        }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(BookmarkDragPayload.typeIdentifier) {
            provider.loadDataRepresentation(forTypeIdentifier: BookmarkDragPayload.typeIdentifier) { data, _ in
                guard let data,
                      let rawID = String(data: data, encoding: .utf8),
                      let bookmarkID = BookmarkDragPayload.bookmarkID(from: rawID) else {
                    return
                }
                DispatchQueue.main.async {
                    assignDraggedBookmark(bookmarkID: bookmarkID, toFolder: targetFolderID)
                }
            }
            return true
        }

        for provider in providers where provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let raw = item as? String else { return }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

                if let items = MultiDragPayload.decodeFromText(trimmed) {
                    DispatchQueue.main.async {
                        for item in items where item.type == "bookmark" {
                            assignDraggedBookmark(bookmarkID: item.id, toFolder: targetFolderID)
                        }
                    }
                    return
                }

                guard let bookmarkID = BookmarkDragPayload.bookmarkID(from: trimmed) else { return }
                DispatchQueue.main.async {
                    assignDraggedBookmark(bookmarkID: bookmarkID, toFolder: targetFolderID)
                }
            }
            return true
        }

        if let draggedBookmarkID {
            assignDraggedBookmark(bookmarkID: draggedBookmarkID, toFolder: targetFolderID)
            return true
        }

        return false
    }

    private func assignDraggedBookmark(bookmarkID: UUID, toFolder targetFolderID: UUID?) {
        guard let bookmark = bookmarks.first(where: { $0.id == bookmarkID }) else { return }
        let assigned = onAssignBookmarkToFolder?(bookmark, targetFolderID) ?? false
        guard assigned else {
            addErrorMessage = "Could not move bookmark to folder."
            return
        }

        addErrorMessage = nil
        draggedBookmarkID = nil
        cancelDragStateReset()
    }

    private func toggleAddForm() {
        withAnimation(reduceMotion ? .none : .snappy) {
            isAddFormVisible.toggle()
        }

        if !isAddFormVisible {
            closeAddForm(resetFields: false)
        }
    }

    private func closeAddForm(resetFields: Bool) {
        withAnimation(reduceMotion ? .none : .snappy) {
            isAddFormVisible = false
        }

        addErrorMessage = nil
        guard resetFields else { return }

        draftTitle = ""
        draftURL = ""
    }

    private func commitAddBookmark() {
        let saved = onAddBookmark(draftURL, draftTitle.isEmpty ? nil : draftTitle)
        if saved {
            closeAddForm(resetFields: true)
        } else {
            addErrorMessage = "Enter a valid URL to save the bookmark."
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if loadDroppedValue(from: provider) {
                return true
            }
        }
        return false
    }

    private func handleBrowserDrop(providers: [NSItemProvider]) -> Bool {
        // Internal bookmark drags should be owned by folder drop targets.
        if isDraggingBookmark || providers.contains(where: {
            $0.hasItemConformingToTypeIdentifier(BookmarkDragPayload.typeIdentifier) ||
            $0.registeredTypeIdentifiers.contains(MultiDragPayload.typeIdentifier)
        }) {
            return false
        }
        return handleDrop(providers: providers)
    }

    private func loadDroppedValue(from provider: NSItemProvider) -> Bool {
        if provider.hasItemConformingToTypeIdentifier(BookmarkDragPayload.typeIdentifier) {
            return false
        }

        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { item, _ in
                guard let droppedURL = item as? URL else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as a URL."
                    }
                    return
                }
                DispatchQueue.main.async {
                    saveDroppedString(droppedURL.absoluteString)
                }
            }
            return true
        }

        if provider.canLoadObject(ofClass: NSString.self) {
            provider.loadObject(ofClass: NSString.self) { item, _ in
                guard let droppedString = item as? String else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as text."
                    }
                    return
                }
                DispatchQueue.main.async {
                    saveDroppedString(droppedString)
                }
            }
            return true
        }

        let preferredIdentifiers = [
            UTType.url.identifier,
            UTType.fileURL.identifier,
            UTType.plainText.identifier,
            UTType.utf8PlainText.identifier,
        ]

        for identifier in preferredIdentifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as a URL."
                    }
                    return
                }

                if let droppedString = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) {
                    DispatchQueue.main.async {
                        saveDroppedString(droppedString)
                    }
                    return
                }

                if let droppedURL = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async {
                        saveDroppedString(droppedURL.absoluteString)
                    }
                    return
                }

                DispatchQueue.main.async {
                    addErrorMessage = "Drop could not be parsed as a URL."
                }
            }
            return true
        }

        for identifier in provider.registeredTypeIdentifiers {
            provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                guard let data, let droppedString = String(data: data, encoding: .utf8) else {
                    DispatchQueue.main.async {
                        addErrorMessage = "Drop could not be parsed as a URL."
                    }
                    return
                }
                DispatchQueue.main.async {
                    saveDroppedString(droppedString)
                }
            }
            return true
        }

        return false
    }

    // MARK: - Selection Helpers

    private func itemID(for bookmark: Bookmark) -> String {
        "bookmark-\(bookmark.id.uuidString)"
    }

    private func isBookmarkSelected(_ bookmark: Bookmark) -> Bool {
        selectedItemIDs.contains(itemID(for: bookmark))
    }

    private func handleSelect(bookmark: Bookmark) {
        let id = itemID(for: bookmark)
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
        selectionAnchorID = id
    }

    private func handleShiftSelect(bookmark: Bookmark) {
        let id = itemID(for: bookmark)
        let items = displayedBookmarks
        guard let anchorID = selectionAnchorID,
              let anchorIndex = items.firstIndex(where: { itemID(for: $0) == anchorID }),
              let clickedIndex = items.firstIndex(where: { $0.id == bookmark.id }) else {
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

    private func selectAllBookmarks() {
        for bookmark in displayedBookmarks {
            selectedItemIDs.insert(itemID(for: bookmark))
        }
    }

    private func saveDroppedString(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(BookmarkDragPayload.textPrefix) ||
           trimmed.hasPrefix(NoteDragPayload.textPrefix) ||
           trimmed.hasPrefix(MultiDragPayload.textPrefix) {
            // Internal drag payload; ignore when dropped outside folder targets.
            return
        }

        let saved = onAddBookmark(rawValue, nil)
        if saved {
            addErrorMessage = nil
        } else {
            addErrorMessage = "Drop does not contain a valid URL."
        }
    }
}

private struct BookmarkFolderSidebarRow: View {
    let title: String
    let bookmarkCount: Int
    let depth: Int
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let dropTypeIdentifiers: [String]
    let onTap: () -> Void
    let onToggleExpand: (() -> Void)?
    let onHoverChanged: (Bool) -> Void
    let onDropTargetChanged: (Bool) -> Void
    let onDropProviders: ([NSItemProvider]) -> Bool

    @Environment(\.textScale) private var textScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            if hasChildren {
                Button(action: { onToggleExpand?() }) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(CiderFont.micro(scale: textScale))
                        .foregroundColor(CiderColors.quaternary)
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear
                    .frame(width: 12, height: 12)
            }

            Image(systemName: "folder")
                .font(CiderFont.bodySemibold(scale: textScale))
                .foregroundColor(iconColor)

            Text(title)
                .font(CiderFont.bodyMedium(scale: textScale))
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            Text("\(bookmarkCount)")
                .font(CiderFont.captionMedium(scale: textScale))
                .foregroundColor(CiderColors.tertiary)
        }
        .padding(.leading, Spacing.xs + CGFloat(depth) * BookmarksDesign.folderSidebarIndent)
        .padding(.trailing, Spacing.xs)
        .frame(minHeight: BookmarksDesign.folderSidebarRowMinHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(borderColor, lineWidth: CiderBorder.innerStrokeWidth)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(reduceMotion ? .none : .snappy, value: isDropTargeted)
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            onHoverChanged(hovering)
        }
        .onDrop(
            of: dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: onDropProviders
        )
        .onChange(of: isDropTargeted) { _, targeted in
            onDropTargetChanged(targeted)
        }
    }

    private var iconColor: Color {
        if isDropTargeted || isSelected {
            return CiderColors.controlAccent
        }
        return CiderColors.secondary
    }

    private var backgroundColor: Color {
        if isDropTargeted {
            return CiderColors.dropTargetFill
        }
        if isSelected {
            return CiderColors.selectedFill
        }
        if isHovered {
            return CiderColors.surfaceHover
        }
        return CiderColors.surfaceElevated
    }

    private var borderColor: Color {
        if isDropTargeted {
            return CiderColors.dropTargetBorder
        }
        if isSelected {
            return CiderColors.selectedBorder
        }
        return CiderColors.borderDefault
    }
}

struct BookmarkThumbnailView: View {
    enum ThumbnailMode {
        case list
        case grid
        case masonry
    }

    let bookmark: Bookmark
    let mode: ThumbnailMode
    var onAspectRatioResolved: ((CGFloat?) -> Void)? = nil

    @Environment(\.textScale) private var textScale
    @State private var thumbnailImage: NSImage?
    @State private var rendersAsIconOverlay = false
    @State private var loadedThumbnailPath: String?

    private var palette: (Color, Color) {
        BookmarkVisualStyle.gradient(for: bookmark)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Color.clear)
            .overlay(content: thumbnailContent)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .onAppear(perform: loadThumbnailIfNeeded)
            .onChange(of: bookmark.thumbnailRelativePath) { _, _ in
                loadThumbnailIfNeeded()
            }
    }

    @ViewBuilder
    private func thumbnailContent() -> some View {
        if let thumbnailImage, !shouldSuppressDownloadedThumbnail {
            if rendersAsIconOverlay {
                iconOverlayGradient(for: thumbnailImage)
            } else {
                Image(nsImage: thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: mode == .masonry ? .fit : .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if bookmark.isEnriching {
            BookmarkShimmerPlaceholder()
        } else {
            fallbackGradient
        }
    }

    private var shouldSuppressDownloadedThumbnail: Bool {
        let fingerprint = (bookmark.thumbnailRemoteURLString ?? "").lowercased()
        if fingerprint.isEmpty { return false }

        let blockedFragments = [
            "if-you-are-looking-for-an-image",
            "if_you_are_looking_for_an_image",
            "/removed.",
            "/deleted.",
            "/default.",
            "/self.",
            "/nsfw.",
            "/spoiler.",
            "preview.redd.it/default",
            "preview.redd.it/self",
            "preview.redd.it/nsfw",
            "preview.redd.it/spoiler",
        ]

        return blockedFragments.contains { fragment in
            fingerprint.contains(fragment)
        }
    }

    private var fallbackGradient: some View {
        gradientBackground
        .overlay {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Spacer(minLength: 0)

                Text(String(bookmark.hostDisplay.prefix(1)).uppercased())
                    .font(.system(size: (mode == .list ? BookmarksDesign.listFallbackLetterSize : BookmarksDesign.cardFallbackLetterSize) * textScale, weight: .black))
                    .foregroundColor(CiderColors.textOnColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(Spacing.sm)
        }
    }

    private var gradientBackground: some View {
        LinearGradient(
            colors: [palette.0.opacity(CiderColors.gradientTint), palette.1.opacity(CiderColors.gradientTint)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func iconOverlayGradient(for image: NSImage) -> some View {
        gradientBackground
            .overlay {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .aspectRatio(contentMode: .fit)
                    .frame(
                        width: iconOverlaySize * textScale,
                        height: iconOverlaySize * textScale
                    )
                    .padding(.top, mode == .list ? Spacing.xl : Spacing.sm)
                    .shadow(color: CiderColors.shadowLight, radius: 2, x: 0, y: 1)
            }
    }

    private var iconOverlaySize: CGFloat {
        switch mode {
        case .list:
            return BookmarksDesign.thumbnailIconOverlaySizeList
        case .grid, .masonry:
            return BookmarksDesign.thumbnailIconOverlaySizeGrid
        }
    }

    private func loadThumbnailIfNeeded() {
        let path = bookmark.thumbnailFileURL?.path
        guard loadedThumbnailPath != path else { return }
        loadedThumbnailPath = path

        guard let path else {
            thumbnailImage = nil
            rendersAsIconOverlay = false
            onAspectRatioResolved?(nil)
            return
        }

        thumbnailImage = NSImage(contentsOfFile: path)
        if shouldSuppressDownloadedThumbnail {
            rendersAsIconOverlay = false
            onAspectRatioResolved?(nil)
            return
        }
        rendersAsIconOverlay = shouldRenderAsIconOverlay(
            image: thumbnailImage,
            remoteURLString: bookmark.thumbnailRemoteURLString
        )
        onAspectRatioResolved?(rendersAsIconOverlay ? nil : resolvedAspectRatio(from: thumbnailImage))
    }

    private func resolvedAspectRatio(from image: NSImage?) -> CGFloat? {
        guard let image else { return nil }
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        return image.size.height / image.size.width
    }

    private func shouldRenderAsIconOverlay(image: NSImage?, remoteURLString: String?) -> Bool {
        guard let image else { return false }
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return false }

        let aspectRatio = width / height
        let isSquareish = abs(aspectRatio - 1) <= BookmarksDesign.thumbnailIconCandidateMaxAspectDelta
        let maxDimension = max(width, height)
        let minDimension = min(width, height)
        let isTinySquareAsset =
            isSquareish &&
            minDimension >= BookmarksDesign.thumbnailIconCandidateMinDimension &&
            maxDimension <= BookmarksDesign.thumbnailIconCandidateMaxDimension

        let remoteFingerprint = (remoteURLString ?? "").lowercased()
        let hasIconURLHint =
            remoteFingerprint.contains("favicon") ||
            remoteFingerprint.contains("apple-touch-icon") ||
            remoteFingerprint.contains("mask-icon") ||
            remoteFingerprint.hasSuffix(".ico")

        return hasIconURLHint || isTinySquareAsset
    }
}

struct BookmarkShimmerPlaceholder: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmerProgress: CGFloat = -0.9

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        CiderColors.surfaceInput,
                        CiderColors.borderSelected,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if !reduceMotion {
                    let bandWidth = max(
                        BookmarksDesign.thumbnailShimmerBandMinWidth,
                        proxy.size.width * BookmarksDesign.thumbnailShimmerBandWidthRatio
                    )
                    let travel = proxy.size.width + bandWidth
                    LinearGradient(
                        colors: [
                            Color.clear,
                            CiderColors.shimmerPeak,
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: bandWidth)
                    .rotationEffect(.degrees(20))
                    .offset(x: shimmerProgress * travel)
                    .blendMode(.plusLighter)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.smooth(duration: BookmarksDesign.thumbnailShimmerDuration).repeatForever(autoreverses: false)) {
                shimmerProgress = 1.2
            }
        }
        .onDisappear {
            shimmerProgress = -0.9
        }
    }
}

enum BookmarkVisualStyle {
    private static let gradientPairs: [(NSColor, NSColor)] = [
        (.systemBlue, .systemTeal),
        (.systemOrange, .systemYellow),
        (.systemPink, .systemRed),
        (.systemIndigo, .systemBlue),
        (.systemMint, .systemGreen),
        (.systemCyan, .systemBlue)
    ]

    static func gradient(for bookmark: Bookmark) -> (Color, Color) {
        let hashValue = abs(bookmark.urlString.hashValue)
        let index = hashValue % gradientPairs.count
        let pair = gradientPairs[index]
        return (Color(pair.0), Color(pair.1))
    }
}
