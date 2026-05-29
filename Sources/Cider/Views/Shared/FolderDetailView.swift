import AppKit
import SwiftUI

struct FolderDetailView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    let folderID: UUID
    var navigationDomain: WorkspaceNavigationDomain? = nil
    @Binding var contentScope: WorkspaceDomainContentScope
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
    @ObservedObject private var todoCardStorage = TodoCardStorage.shared
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

    private var allFolderContentItems: [LibraryItemV2] {
        let bookmarks = bookmarksViewModel.bookmarks
            .map { LibraryItemV2.bookmark($0) }
        let notes = notesViewModel.notes
            .map { LibraryItemV2.note($0) }
        let dateCards = dateCardStorage.dateCards
            .map { LibraryItemV2.dateCard($0) }
        let contacts = contactStorage.contacts
            .map { LibraryItemV2.contact($0) }
        let todos = todoCardStorage.todoCards
            .map { LibraryItemV2.todo($0) }
        let vaultFiles = vaultFileService.files
            .map { LibraryItemV2.vaultFile($0) }
        return (bookmarks + notes + dateCards + contacts + todos + vaultFiles)
            .sorted { $0.createdDate > $1.createdDate }
    }

    private var allScopedItems: [LibraryItemV2] {
        var all = allFolderContentItems
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

    private var domainScopedItems: [LibraryItemV2] {
        let entityTypes = contentScope.entityTypes(for: navigationDomain)
        return allScopedItems.filter { entityTypes.contains($0.entityType) }
    }

    private var folderItems: [LibraryItemV2] {
        domainScopedItems.filter { $0.folderID == folderID }
    }

    private var childOverviewSections: [FolderOverviewSection] {
        FolderOverviewSection.buildSections(
            parentFolderID: folderID,
            folders: bookmarksViewModel.folders,
            items: domainScopedItems
        )
    }

    private var cardSizing: LibraryCardSizing {
        LibraryCardSizing(scale: cardSizeScale)
    }

    private var subfolderPreviewCardWidth: CGFloat {
        min(max(cardSizing.cardMinWidth * 0.78, 170), 220)
    }

    private var foldersByID: [UUID: Folder] {
        bookmarksViewModel.foldersByID
    }

    /// Ancestors of the current folder (excluding itself), from root → parent.
    private var breadcrumbPath: [Folder] {
        let fullPath = bookmarksViewModel.folderPath(to: folderID)
        return Array(fullPath.dropLast())
    }

    private var isSubfolderOverviewCollapsed: Bool {
        folderConfig.folderOverviewCollapsedByParentID[folderID.uuidString] ?? !folderItems.isEmpty
    }

    private var subfolderOverviewCollapsedBinding: Binding<Bool> {
        Binding(
            get: { isSubfolderOverviewCollapsed },
            set: { isCollapsed in
                folderConfig.folderOverviewCollapsedByParentID[folderID.uuidString] = isCollapsed
                folderConfig.save()
            }
        )
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
                                    let feedWidth = FolderDetailFeedLayout.availableWidth(
                                        contentWidth: contentProxy.size.width,
                                        appliesCardPadding: !noPadding
                                    )
                                    libraryFeed(items: folderItems, folderID: folderID, availableWidth: feedWidth)
                                        .frame(width: feedWidth, alignment: .leading)
                                        .padding(noPadding ? 0 : Spacing.xxs)
                                        .padding(.horizontal, noPadding ? 0 : Spacing.md)
                                        .padding(.vertical, noPadding ? 0 : Spacing.md)
                                } else if childOverviewSections.isEmpty {
                                    EmptyStateView(
                                        icon: "tray",
                                        title: "No items yet",
                                        subtitle: "Drag bookmarks or notes here, or add them from the sidebar"
                                    )
                                    .frame(minHeight: BookmarksDesign.detailsSheetNotesHeight)
                                } else {
                                    noDirectItemsHint
                                }

                                if !childOverviewSections.isEmpty {
                                    childOverviewFeed(contentWidth: contentProxy.size.width)
                                }
                            }
                            .frame(width: contentProxy.size.width, alignment: .leading)
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

            if showsContentScopeToggle {
                Picker("Folder contents", selection: $contentScope) {
                    Text(contentScope.focusedTitle(for: navigationDomain)).tag(WorkspaceDomainContentScope.domainOnly)
                    Text("All Items").tag(WorkspaceDomainContentScope.allItems)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260, alignment: .leading)
                .padding(.top, Spacing.xs)
                .help("Switch between this domain's items and everything in the folder")
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

    private var showsContentScopeToggle: Bool {
        WorkspaceDomainContentScope.defaultScope(for: navigationDomain) == .domainOnly
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
        NoteDragPayload.markdownTypeIdentifier,
        "public.utf8-plain-text"
    ]

    private func subFolderCard(_ folder: Folder) -> some View {
        let summary = FolderCardSummary.build(
            folderID: folder.id,
            folders: bookmarksViewModel.folders,
            items: allFolderContentItems
        )

        return Button {
            onSelectSubFolder?(folder.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    folderIconView(for: folder, filled: true)

                    Spacer()

                    if let badgeCount = summary.badgeCount {
                        Text("\(badgeCount)")
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
                    ForEach(summary.metrics, id: \.systemImage) { metric in
                        Label("\(metric.count)", systemImage: metric.systemImage)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                    if summary.isEmpty {
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
                                guard bvm.assign(bookmark, toFolder: targetFolderID) else { continue }
                            } else if item.type == "note",
                                      let note = nvm.notes.first(where: { $0.id == item.id }) {
                                guard nvm.assignNote(note, toFolder: targetFolderID) else { continue }
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
                        guard bvm.assign(bookmark, toFolder: targetFolderID) else { return }
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
                        guard nvm.assignNote(note, toFolder: targetFolderID) else { return }
                    }
                }
                handled = true
                continue
            }

            // Markdown file fallback for note drags that SwiftUI exposes as a file
            // representation instead of Cider's custom note ID.
            if provider.hasItemConformingToTypeIdentifier(NoteDragPayload.markdownTypeIdentifier) {
                provider.loadFileRepresentation(forTypeIdentifier: NoteDragPayload.markdownTypeIdentifier) { fileURL, _ in
                    guard let fileURL else { return }
                    let filename = fileURL.lastPathComponent
                    Task { @MainActor in
                        guard let note = nvm.notes.first(where: { note in
                            note.absoluteFileURL.lastPathComponent == filename
                                || (note.relativePath as NSString).lastPathComponent == filename
                        }) else { return }
                        guard nvm.assignNote(note, toFolder: targetFolderID) else { return }
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
                                guard bvm.assign(bookmark, toFolder: targetFolderID) else { continue }
                            } else if item.type == "note",
                                      let note = nvm.notes.first(where: { $0.id == item.id }) {
                                guard nvm.assignNote(note, toFolder: targetFolderID) else { continue }
                            }
                        }
                    } else if let bookmarkID = BookmarkDragPayload.bookmarkID(from: text),
                              let bookmark = bvm.bookmarks.first(where: { $0.id == bookmarkID }) {
                        guard bvm.assign(bookmark, toFolder: targetFolderID) else { return }
                    } else if let noteID = NoteDragPayload.noteID(from: text),
                              let note = nvm.notes.first(where: { $0.id == noteID }) {
                        guard nvm.assignNote(note, toFolder: targetFolderID) else { return }
                    }
                }
            }
            handled = true
        }

        return handled
    }

    // MARK: - Library Feed

    @ViewBuilder
    private func libraryFeed(
        items: [LibraryItemV2],
        folderID: UUID,
        availableWidth: CGFloat
    ) -> some View {
        switch displayMode {
        case .list:
            LibraryTableRows(
                items: items,
                labels: labelStorage.labels,
                folders: bookmarksViewModel.folders,
                columnConfig: tableColumnConfig,
                selectedItemIDs: selectedItemIDs,
                focusedItemID: focusedItemID,
                onOpen: { item in handleNormalAction { openItem(item) } },
                onSelect: { item in handleSelect(item: item) },
                onShiftSelect: { item in handleShiftSelect(item: item, within: items) }
            )

        case .grid:
            let columns = [GridItem(.adaptive(minimum: cardSizing.cardMinWidth), spacing: Spacing.md)]
            LazyVGrid(columns: columns, spacing: Spacing.md) {
                ForEach(items) { item in
                    libraryCard(item, mode: .grid, selectionItems: items)
                        .id(item.id)
                }
            }
            .frame(width: availableWidth, alignment: .leading)
            .id(FolderDetailFeedLayout.layoutIdentity(
                displayMode: displayMode,
                availableWidth: availableWidth,
                minimumCardWidth: cardSizing.cardMinWidth
            ))

        case .masonry:
            LazyMasonryView(
                items: items,
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
                libraryCard(item, mode: .masonry, selectionItems: items, masonryCardWidth: columnWidth)
            }
            .frame(width: availableWidth, alignment: .leading)
            .id(FolderDetailFeedLayout.layoutIdentity(
                displayMode: displayMode,
                availableWidth: availableWidth,
                minimumCardWidth: cardSizing.cardMinWidth
            ))
            .padding(.bottom, Spacing.xs)

        case .kanban:
            FolderKanbanView(
                folderID: folderID,
                items: items,
                onOpen: { item in handleNormalAction { openItem(item) } }
            )
        }
    }

    // MARK: - Child Overview Feed

    private var noDirectItemsHint: some View {
        Text("No items directly in this folder yet")
            .font(CiderFont.caption)
            .foregroundColor(CiderColors.tertiary)
            .padding(.horizontal, Spacing.md + Spacing.xxs)
            .padding(.top, Spacing.sm)
    }

    private func childOverviewFeed(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Divider()
                HStack(alignment: .center, spacing: Spacing.sm) {
                    Text("Subfolders")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                        .textCase(.uppercase)

                    Spacer()

                    SectionCollapseToggle(
                        label: "Preview",
                        isCollapsed: subfolderOverviewCollapsedBinding,
                        collapsedHelp: "Show subfolder previews",
                        expandedHelp: "Hide subfolder previews"
                    )
                }
            }
            .padding(.horizontal, Spacing.md + Spacing.xxs)
            .padding(.top, Spacing.md)

            if !isSubfolderOverviewCollapsed {
                ForEach(childOverviewSections) { section in
                    childOverviewSection(section, contentWidth: contentWidth)
                        .padding(.horizontal, Spacing.md + Spacing.xxs)
                }
            }
        }
        .padding(.bottom, Spacing.md)
    }

    private func childOverviewSection(_ section: FolderOverviewSection, contentWidth: CGFloat) -> some View {
        let summary = FolderCardSummary.build(
            folderID: section.folder.id,
            folders: bookmarksViewModel.folders,
            items: allFolderContentItems
        )
        let previewWidth = childOverviewPreviewWidth(contentWidth: contentWidth)
        let previewLayout = FolderOverviewSection.previewLayout(
            items: section.items,
            availableWidth: previewWidth,
            preferredCardWidth: subfolderPreviewCardWidth,
            itemSpacing: Spacing.sm
        )
        let previewItems = Array(section.items.prefix(previewLayout.visibleItemCount))

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        folderIconView(for: section.folder, filled: false)
                            .padding(.top, 1)

                        Button {
                            onSelectSubFolder?(section.folder.id)
                        } label: {
                            Text(section.folder.name)
                                .font(CiderFont.labelMedium)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(2)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: Spacing.sm) {
                        ForEach(summary.metrics, id: \.systemImage) { metric in
                            Label("\(metric.count)", systemImage: metric.systemImage)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.tertiary)
                        }
                        if summary.isEmpty {
                            Text("Empty")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }
                .frame(width: FolderDetailDesign.subfolderPreviewLabelWidth, alignment: .leading)

                if section.items.isEmpty {
                    HStack {
                        if summary.childFolderCount > 0 {
                            Label(
                                "\(summary.childFolderCount) subfolder\(summary.childFolderCount == 1 ? "" : "s")",
                                systemImage: "folder"
                            )
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                        } else {
                            Text("Empty")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                } else {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        ForEach(previewItems) { item in
                            libraryCard(item, mode: .grid, selectionItems: previewItems)
                                .frame(width: subfolderPreviewCardWidth, alignment: .topLeading)
                                .id(item.id)
                        }

                        if previewLayout.showsMoreCard {
                            childOverviewMoreCard(
                                remainingItemCount: previewLayout.remainingItemCount,
                                folder: section.folder
                            )
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(Spacing.md)
        }
        .sectionContainer()
    }

    private func childOverviewMoreCard(remainingItemCount: Int, folder: Folder) -> some View {
        Button {
            onSelectSubFolder?(folder.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Image(systemName: "arrow.right.circle")
                    .font(CiderFont.titleMedium)
                    .foregroundColor(CiderColors.controlAccent)

                Spacer(minLength: 0)

                Text("+\(remainingItemCount) more")
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Text("Open \(folder.name)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(2)
            }
            .padding(Spacing.sm)
            .frame(width: subfolderPreviewCardWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)
            .sectionContainer()
        }
        .buttonStyle(.plain)
    }

    private func childOverviewPreviewWidth(contentWidth: CGFloat) -> CGFloat {
        let outerSectionPadding = (Spacing.md + Spacing.xxs) * 2
        let sectionContentPadding = Spacing.md * 2
        let labelColumnWidth = FolderDetailDesign.subfolderPreviewLabelWidth
        let interColumnSpacing = Spacing.md
        return max(
            0,
            contentWidth - outerSectionPadding - sectionContentPadding - labelColumnWidth - interColumnSpacing
        )
    }

    @ViewBuilder
    private func folderIconView(for folder: Folder, filled: Bool) -> some View {
        if let icon = folder.icon, folder.iconIsEmoji {
            Text(icon)
                .font(CiderFont.titleMedium)
        } else if let icon = folder.icon {
            Image(systemName: icon)
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.controlAccent)
        } else {
            Image(systemName: filled ? "folder.fill" : "folder")
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.controlAccent)
        }
    }

    // MARK: - Card (Grid / Masonry)

    @ViewBuilder
    private func libraryCard(
        _ item: LibraryItemV2,
        mode: BookmarkCard.CardMode,
        selectionItems: [LibraryItemV2],
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
                dragPreviewOverride: multiDragPreview(for: item, in: selectionItems),
                onShowDetails: { handleNormalAction { onShowBookmarkDetails?(bookmark) } },
                onOpen: { handleNormalAction { bookmarksViewModel.open(bookmark) } },
                onDelete: { handleContextMenuDelete(item: item) { bookmarksViewModel.deleteBookmarks([bookmark]) } },
                onMoveToFolder: { folderID in
                    guard bookmarksViewModel.assign(bookmark, toFolder: folderID) else { return }
                },
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item, within: selectionItems) },
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
                dragPreviewOverride: multiDragPreview(for: item, in: selectionItems),
                isSelected: isItemSelected(item),
                isFocused: focusedItemID == item.id,
                onSelect: { handleSelect(item: item) },
                onShiftSelect: { handleShiftSelect(item: item, within: selectionItems) },
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
                onShiftSelect: { handleShiftSelect(item: item, within: selectionItems) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .contact(let contact):
            ContactCardCardView(
                contact: contact,
                onOpen: { (onOpenContact ?? onEditContact)?(contact) },
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
                onShiftSelect: { handleShiftSelect(item: item, within: selectionItems) },
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
                onShiftSelect: { handleShiftSelect(item: item, within: selectionItems) },
                onToggleLabelBulk: onToggleLabelBulk
            )
        case .vaultFile(let file):
            VaultFileCardView(
                file: file,
                masonryCardWidth: masonryCardWidth,
                onOpen: { onOpenVaultFile?(file) },
                folders: bookmarksViewModel.folders,
                onMoveToFolder: { folderID in
                    let oldFolderID = file.folderID
                    guard VaultFileService.shared.assignFile(file.id, toFolder: folderID) else { return }
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
                onShiftSelect: { handleShiftSelect(item: item, within: selectionItems) }
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
        handleShiftSelect(item: item, within: folderItems)
    }

    private func handleShiftSelect(item: LibraryItemV2, within items: [LibraryItemV2]) {
        let id = item.id
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
                    provider.suggestedName = BookmarkDragPayload.suggestedImageExportName(
                        title: bookmark.title,
                        fileURL: fileURL
                    )
                    return provider
                }
            }

            if selectedItemIDs.contains(bookmarkItemID) && selectedItemIDs.count > 1 {
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
            let noteItemID = itemID(for: .note(note))

            if selectedItemIDs.contains(noteItemID) && selectedItemIDs.count > 1 {
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

    private func multiDragPreview(for item: LibraryItemV2, in items: [LibraryItemV2]) -> AnyView? {
        let id = item.id
        guard selectedItemIDs.contains(id), selectedItemIDs.count > 1 else { return nil }

        var previewItems: [MultiDragPreviewItem] = [multiDragPreviewItem(from: item)].compactMap { $0 }
        for libraryItem in items where isItemSelected(libraryItem) && libraryItem.id != id {
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

enum FolderDetailFeedLayout {
    static func availableWidth(contentWidth: CGFloat, appliesCardPadding: Bool) -> CGFloat {
        guard contentWidth.isFinite, contentWidth > 0 else { return 1 }
        let horizontalPadding = appliesCardPadding ? (Spacing.md + Spacing.xxs) * 2 : 0
        return max(contentWidth - horizontalPadding, 1)
    }

    static func layoutIdentity(
        displayMode: LibraryDisplayMode,
        availableWidth: CGFloat,
        minimumCardWidth: CGFloat
    ) -> String {
        let widthBucket = Int(max(availableWidth, 1).rounded(.down))
        let cardWidthBucket = Int(max(minimumCardWidth, 1).rounded(.down))
        return "\(displayMode.rawValue)-\(widthBucket)-\(cardWidthBucket)"
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
