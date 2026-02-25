import SwiftUI
import AppKit

struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject private var savedViewStorage = SavedViewStorage.shared
    @ObservedObject private var externalSourceStorage = ExternalSourceStorage.shared
    @StateObject private var libraryViewModel = LibraryViewModel()
    @State private var selectedTab: CiderTab = .home
    @State private var isCollapsed = false
    @State private var selectedFolderID: UUID?
    @State private var selectedSourceID: UUID?
    @State private var selectedItemIDs: Set<String> = []
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var isSearchPaletteVisible = false
    @State private var dynamicTabs: [CiderTab] = []
    @State private var isHomeViewOptionsVisible = false
    @State private var showNewItemPicker = false
    @State private var homeDisplayMode: LibraryDisplayMode = CiderConfig.load().homeDisplayMode
    @State private var homeCardSizeScale: Double = CiderConfig.load().homeCardSizeScale ?? 1.0
    @State private var continueSectionCollapsed: Bool = CiderConfig.load().continueSectionCollapsed
    @State private var homeSort: LibrarySortMode = CiderConfig.load().homeSort
    @State private var homeEntityFilter: Set<LibraryEntityType> = CiderConfig.load().homeEntityFilter
    @State private var showContinueSection: Bool = CiderConfig.load().showContinueSection
    @State private var subFoldersCollapsed: Bool = CiderConfig.load().subFoldersCollapsed
    @State private var textScale: CGFloat = CiderConfig.load().textSize.scale
    // Detail view state (centralized)
    @State private var detailBookmarkID: UUID?
    @State private var detailViewMode: DetailViewMode = CiderConfig.load().detailViewMode
    @State private var detailSlideOutWidth: CGFloat = CiderConfig.load().detailSlideOutWidth ?? 400
    @State private var detailsDraft: BookmarkDetailsDraft?
    @State private var detailsErrorMessage: String?
    @State private var detailWidthSaveTask: Task<Void, Never>?
    @State private var selectedDateCard: DateCard?
    @State private var selectedContact: ContactCard?
    @State private var cardScaleSaveTask: Task<Void, Never>?
    @State private var sidebarSearchText: String = ""
    @State private var debouncedSearchText: String = ""
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var selectedNote: Note?
    @State private var isEditingNoteTitle = false
    @State private var newEventEditorContext: DateCardEditorContext?
    @State private var newContactEditorContext: ContactEditorContext?
    @State private var contentAreaWidth: CGFloat = 800

    private var allTabs: [CiderTab] {
        CiderTab.fixedTabs + savedViewTabs + sourceTabs + dynamicTabs
    }

    private var sourceTabs: [CiderTab] {
        guard CiderConfig.load().enableLinkedSources else { return [] }
        return externalSourceStorage.pinnedSources().map {
            .externalSource(id: $0.id, name: $0.displayName)
        }
    }

    private var savedViewTabs: [CiderTab] {
        guard CiderConfig.load().enableSavedViewTabs else { return [] }
        return savedViewStorage.pinnedSavedViews().map { savedView in
            .savedView(id: savedView.id, name: savedView.name)
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        CiderPanelShell(
            isCollapsed: isCollapsed,
            suppressSidebarAutoExpand: isAnyDetailOpen,
            blurRightColumn: isDetailSlideOut || isGenericDetailSlideOut || isNoteDetailSlideOut,
            onClose: { NotificationCenter.default.post(name: .dismissCiderPanel, object: nil) },
            onCollapse: { NotificationCenter.default.post(name: .toggleCiderPanelCollapse, object: nil) },
            onMaximize: { NotificationCenter.default.post(name: .maximizeCiderPanel, object: nil) }
        ) {
            folderSidebar
        } sidebarFooter: {
            sidebarFooterView
        } titleBar: {
            titleBarContent
        } content: {
            contentArea
        } overlay: {
            if isSearchPaletteVisible {
                SearchPaletteView(
                    bookmarks: bookmarksViewModel.bookmarks,
                    notes: notesViewModel.notes,
                    onOpenBookmark: { bookmark in
                        if NSEvent.modifierFlags.contains(.command) {
                            bookmarksViewModel.open(bookmark)
                        } else {
                            openBookmarkDetails(bookmark)
                        }
                    },
                    onOpenNote: { note in
                        openNoteDetail(note)
                    },
                    onSpawnSearchTab: spawnSearchTab,
                    onDismiss: { isSearchPaletteVisible = false }
                )
            }
            if isDetailFullPanel {
                detailFullPanelOverlay
            }
            if isDetailSlideOut, let _ = detailsDraft {
                // Transparent dismiss area — covers the blurred content to the left
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closeBookmarkDetails() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                detailSlideOutContainer
                    .frame(width: min(detailSlideOutWidth, maxSlideOutWidth))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(BookmarksDesign.detailsSlideOutFloatInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if isGenericDetailFullPanel {
                genericDetailFullPanelOverlay
            }
            if isGenericDetailSlideOut {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closeGenericDetail() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                genericDetailSlideOutContainer
                    .frame(width: min(detailSlideOutWidth, maxSlideOutWidth))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(BookmarksDesign.detailsSlideOutFloatInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            if isNoteDetailFullPanel {
                noteDetailFullPanelOverlay
            }
            if isNoteDetailSlideOut {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { closeNoteDetail() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                noteDetailSlideOutContainer
                    .frame(width: min(detailSlideOutWidth, maxSlideOutWidth))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .padding(BookmarksDesign.detailsSlideOutFloatInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .animation(reduceMotion ? .none : .snappy, value: isDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isGenericDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isGenericDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isNoteDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isNoteDetailSlideOut)
        .environment(\.textScale, textScale)
        .onChange(of: sidebarSearchText) { _, newValue in
            searchDebounceTask?.cancel()
            if newValue.isEmpty {
                debouncedSearchText = ""
            } else {
                searchDebounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(150))
                    guard !Task.isCancelled else { return }
                    debouncedSearchText = newValue
                }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            selectedFolderID = nil
            selectedSourceID = nil
            selectedItemIDs.removeAll()
            searchDebounceTask?.cancel()
            sidebarSearchText = ""
            debouncedSearchText = ""
            closeAllDetails()
        }
        .onChange(of: selectedFolderID) { _, _ in
            selectedItemIDs.removeAll()
            searchDebounceTask?.cancel()
            sidebarSearchText = ""
            debouncedSearchText = ""
            closeAllDetails()
        }
        .onChange(of: bookmarksViewModel.bookmarks.map(\.id)) { _, bookmarkIDs in
            guard let detailBookmarkID else { return }
            if !bookmarkIDs.contains(detailBookmarkID) {
                closeBookmarkDetails()
            }
        }
        .onChange(of: homeDisplayMode) { _, newValue in
            var config = CiderConfig.load()
            config.homeDisplayMode = newValue
            config.save()
        }
        .onChange(of: homeCardSizeScale) { _, newValue in
            cardScaleSaveTask?.cancel()
            cardScaleSaveTask = Task {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                var config = CiderConfig.load()
                config.homeCardSizeScale = newValue
                config.save()
            }
        }
        .onChange(of: continueSectionCollapsed) { _, newValue in
            var config = CiderConfig.load()
            config.continueSectionCollapsed = newValue
            config.save()
        }
        .onChange(of: subFoldersCollapsed) { _, newValue in
            var config = CiderConfig.load()
            config.subFoldersCollapsed = newValue
            config.save()
        }
        .onChange(of: homeSort) { _, newValue in
            var config = CiderConfig.load()
            config.homeSort = newValue
            config.save()
        }
        .onChange(of: homeEntityFilter) { _, newValue in
            var config = CiderConfig.load()
            config.homeEntityFilter = newValue
            config.save()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissCiderPanel)) { _ in
            closeAllDetails()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ciderConfigChanged)) { _ in
            textScale = CiderConfig.load().textSize.scale
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNoteEditor)) { notification in
            if isNoteDetailOpen {
                closeNoteDetail()
            } else if let note = notification.object as? Note {
                openNoteDetail(note)
            } else {
                let note = NotesStorage.shared.createNew()
                openNoteDetail(note)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureBookmark)) { _ in
            _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorRequestClose)) { _ in
            if isNoteDetailOpen {
                closeNoteDetail()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openBookmarkDetails)) { notification in
            guard let bookmarkID = notification.userInfo?["bookmarkID"] as? UUID,
                  let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == bookmarkID }) else { return }
            openBookmarkDetails(bookmark)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewItemPopover)) { _ in
            showNewItemPicker = true
        }
        .sheet(item: $newEventEditorContext) { context in
            DateCardEditorSheet(
                existingCard: context.existingCard,
                defaultDate: context.defaultDate,
                onSave: { title, details, startAt, endAt, allDay, location, amount, labelIDs, recurrenceRule in
                    LibraryItemEditor.saveDateCard(
                        existingCard: context.existingCard,
                        title: title,
                        details: details,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        location: location,
                        amount: amount,
                        labelIDs: labelIDs,
                        recurrenceRule: recurrenceRule
                    )
                },
                onDelete: { dateCard in
                    _ = DateCardStorage.shared.deleteDateCard(dateCard.id)
                    let trashItem = TrashStorage.shared.trashDateCard(dateCard, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                }
            )
        }
        .sheet(item: $newContactEditorContext) { context in
            ContactEditorSheet(
                existingContact: context.existingContact,
                onSave: { draftContactID, displayName, relationshipLabel, birthday, notes, labelIDs, addBirthdayDateCard, email, phone, address, hasAvatar in
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
                        hasAvatar: hasAvatar
                    )
                },
                onDelete: { contact in
                    _ = ContactStorage.shared.deleteContact(contact.id)
                    let trashItem = TrashStorage.shared.trashContact(contact, ciderDir: StoragePaths.ciderDataDirectoryURL())
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                }
            )
        }
        .background {
            Button("") { isSearchPaletteVisible = true }
                .keyboardShortcut("k", modifiers: .command)
                .hidden()

            Button("") { selectAllVisibleItems() }
                .keyboardShortcut("a", modifiers: .command)
                .hidden()

            Button("") {
                if !sidebarSearchText.isEmpty {
                    searchDebounceTask?.cancel()
                    sidebarSearchText = ""
                    debouncedSearchText = ""
                } else if isDetailOpen {
                    closeBookmarkDetails()
                } else if isGenericDetailOpen {
                    closeGenericDetail()
                } else if isNoteDetailOpen {
                    closeNoteDetail()
                } else if !selectedItemIDs.isEmpty {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        selectedItemIDs.removeAll()
                    }
                }
            }
            .keyboardShortcut(.escape, modifiers: [])
            .hidden()
        }
    }

    // MARK: - Title Bar Content

    @ViewBuilder
    private var titleBarContent: some View {
        if isAnyDetailPageMode {
            detailPageTitleBar
        } else if !selectedItemIDs.isEmpty {
            selectionTitleBar
        } else {
            normalTitleBar
        }
    }

    @ViewBuilder
    private var normalTitleBar: some View {
        CiderTabBar(
            selectedTab: $selectedTab,
            tabs: allTabs,
            selectedFolderID: $selectedFolderID,
            selectedSourceID: $selectedSourceID,
            onCloseTab: closeTab
        )
        .frame(maxWidth: .infinity)

        Image(systemName: "safari")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
            }
            .help("Capture active browser tab")

        Image(systemName: "camera.viewfinder")
            .font(CiderFont.bodySemibold)
            .foregroundColor(CiderColors.secondary)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: .requestScreenCapture, object: nil)
            }
            .help("Capture screen region (⌥⌘2)")

        if selectedTab == .home && selectedFolderID == nil {
            Image(systemName: "plus.square.on.square")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .onTapGesture {
                    createSavedViewFromCurrentHomeState()
                }
                .help("Save current view as tab")

            if showContinueSection {
                SectionCollapseToggle(
                    label: "Recents",
                    isCollapsed: $continueSectionCollapsed,
                    collapsedHelp: "Show recent items",
                    expandedHelp: "Hide recent items"
                )
            }
        } else if selectedFolderID != nil && folderHasSubFolders {
            SectionCollapseToggle(
                label: "Folders",
                isCollapsed: $subFoldersCollapsed,
                collapsedHelp: "Show sub-folders",
                expandedHelp: "Hide sub-folders"
            )
        }
    }

    @ViewBuilder
    private var selectionTitleBar: some View {
        Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                selectedItemIDs.removeAll()
            }
        } label: {
            Image(systemName: "xmark")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Clear selection")

        Text("\(selectedItemIDs.count) item\(selectedItemIDs.count == 1 ? "" : "s") selected")
            .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.primary)
            .lineLimit(1)

        Spacer(minLength: Spacing.sm)

        Menu {
            ForEach(bookmarksViewModel.folders) { folder in
                Button(folder.name) {
                    moveSelectedToFolder(folder.id)
                }
            }
            if !bookmarksViewModel.folders.isEmpty {
                Divider()
            }
            Button("Remove from Folder") {
                moveSelectedToFolder(nil)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(CiderFont.captionSemibold)
                Text("Move")
                    .font(CiderFont.bodyMedium)
            }
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .frame(height: 28)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Move selected items to folder")

        Button {
            deleteSelectedItems()
        } label: {
            Image(systemName: "trash")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.destructive)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delete selected items")
    }

    // MARK: - Section Toggles

    private var folderHasSubFolders: Bool {
        guard let folderID = selectedFolderID else { return false }
        return bookmarksViewModel.folders.contains(where: { $0.parentID == folderID })
    }


    // MARK: - Sidebar Content

    private var folderSidebar: some View {
        FolderSidebarView(
            folders: bookmarksViewModel.folders,
            bookmarks: bookmarksViewModel.bookmarks,
            notes: notesViewModel.notes,
            selectedFolderID: $selectedFolderID,
            expandedFolderIDs: $expandedFolderIDs,
            onCreateFolder: { bookmarksViewModel.createFolder(name: $0, parentID: $1) },
            onAssignBookmarkToFolder: { bookmarksViewModel.assign($0, toFolder: $1) },
            onAssignNoteToFolder: { notesViewModel.assignNote($0, toFolder: $1) },
            onRenameFolder: { bookmarksViewModel.renameFolder($0, to: $1) },
            onDeleteFolder: deleteFolder,
            searchText: $sidebarSearchText,
            onTriggerSearch: { isSearchPaletteVisible = true },
            showBackground: false,
            sources: externalSourceStorage.sources,
            selectedSourceID: $selectedSourceID,
            onAddSource: addLinkedSource,
            onSelectSource: { id in
                selectedSourceID = id
                selectedFolderID = nil
            },
            onToggleSourceTab: { id in
                guard var source = externalSourceStorage.source(for: id) else { return }
                source.isTabPinned.toggle()
                externalSourceStorage.updateSource(source)
            },
            onToggleSourceLibrary: { id in
                guard var source = externalSourceStorage.source(for: id) else { return }
                source.showInLibrary.toggle()
                externalSourceStorage.updateSource(source)
            },
            onRemoveSource: { id in
                if selectedSourceID == id { selectedSourceID = nil }
                externalSourceStorage.removeSource(id)
                // Also close any open tab for this source
                dynamicTabs.removeAll {
                    if case .externalSource(let tabID, _) = $0 { return tabID == id }
                    return false
                }
                if case .externalSource(let tabID, _) = selectedTab, tabID == id {
                    selectedTab = .home
                }
            }
        )
    }

    private func addLinkedSource() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.title = "Choose a Folder to Link"
        panel.prompt = "Link Folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = externalSourceStorage.addSource(path: url.path, displayName: url.lastPathComponent)
        selectedSourceID = source.id
        selectedFolderID = nil
    }

    // MARK: - Sidebar Footer

    private var sidebarFooterView: some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .background(CiderColors.separator)
                .padding(.bottom, Spacing.xs)

            HStack(spacing: Spacing.sm) {
                // Settings gear
                Button {
                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings")

                Spacer(minLength: 0)

                // + pill button
                Button {
                    showNewItemPicker.toggle()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "plus")
                            .font(CiderFont.captionSemibold)
                        Text("New")
                            .font(CiderFont.bodyMedium)
                    }
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.sm)
                    .frame(height: CiderPanelDesign.trafficLightTapTarget)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
                .help("Create new item")
                .popover(isPresented: $showNewItemPicker, arrowEdge: .bottom) {
                    newItemPickerContent
                }

                Spacer(minLength: 0)

                // View options
                viewOptionsButton
            }
        }
        .padding(.top, Spacing.sm)
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.sm)
        .frame(width: BookmarksDesign.folderSidebarWidth)
    }

    private var newItemPickerContent: some View {
        let bvm = bookmarksViewModel
        let eventContextSetter = _newEventEditorContext
        let contactContextSetter = _newContactEditorContext
        return NewItemPopover(
            folders: bvm.folders,
            onCreateBookmark: { urlString, title in
                _ = bvm.addBookmark(urlString: urlString, title: title)
            },
            onCreateNote: { [self] title, content in
                createNoteAndOpen(title: title, content: content)
            },
            onCreateEvent: { title, date, allDay in
                let card = DateCardStorage.shared.createDateCard(
                    title: title,
                    startAt: date,
                    allDay: allDay
                )
                DispatchQueue.main.async {
                    eventContextSetter.wrappedValue = DateCardEditorContext(
                        existingCard: card,
                        defaultDate: date
                    )
                }
            },
            onCreateContact: { name, relationship in
                var contact = ContactStorage.shared.createContact(displayName: name)
                if !relationship.isEmpty {
                    contact.relationshipLabel = relationship
                    ContactStorage.shared.updateContact(contact)
                }
                DispatchQueue.main.async {
                    contactContextSetter.wrappedValue = ContactEditorContext(existingContact: contact)
                }
            },
            onCreateFolder: { name, parentID in
                bvm.createFolder(name: name, parentID: parentID)
            },
            onCreateTab: { [self] name, entityTypes in
                let filter = SavedViewFilterSpec(entityTypes: entityTypes)
                let savedView = savedViewStorage.createSavedView(name: name, filterSpec: filter)
                selectedFolderID = nil
                selectedTab = .savedView(id: savedView.id, name: savedView.name)
            },
            onDismiss: { [self] in
                showNewItemPicker = false
            }
        )
    }

    private var showFolderViewOptions: Bool {
        selectedFolderID != nil && selectedTab.isFixed
    }

    @ViewBuilder
    private var viewOptionsButton: some View {
        if showFolderViewOptions {
            // Folder view uses home display mode
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isHomeViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
                .onTapGesture { isHomeViewOptionsVisible.toggle() }
                .help("View options")
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale
                    )
                }
        } else if selectedTab == .home {
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.bodySemibold)
                .foregroundColor(isHomeViewOptionsVisible ? CiderColors.controlAccent : CiderColors.secondary)
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
                .contentShape(Rectangle())
                .onTapGesture { isHomeViewOptionsVisible.toggle() }
                .help("View options")
                .popover(isPresented: $isHomeViewOptionsVisible) {
                    ViewOptionsDropdown(
                        displayMode: $homeDisplayMode,
                        cardSizeScale: $homeCardSizeScale,
                        sortMode: $homeSort,
                        entityFilter: $homeEntityFilter
                    )
                }
        } else {
            // Invisible spacer to keep layout stable
            Color.clear
                .frame(width: CiderPanelDesign.trafficLightTapTarget, height: CiderPanelDesign.trafficLightTapTarget)
        }
    }

    // MARK: - Content Area

    private var isEditorActive: Bool {
        selectedNote != nil || notesViewModel.activeExternalFile != nil
    }

    private var isNoteDetailOpen: Bool { isEditorActive }
    private var isNoteDetailSlideOut: Bool { isNoteDetailOpen && detailViewMode == .slideOut }
    private var isNoteDetailFullPanel: Bool { isNoteDetailOpen && detailViewMode == .fullPanel }
    private var isNoteDetailPageMode: Bool { isNoteDetailOpen && detailViewMode == .page }

    private var contentArea: some View {
        ZStack {
            tabContentBody
                .opacity(isAnyDetailPageMode ? 0 : 1)
                .allowsHitTesting(!isAnyDetailPageMode)

            if isAnyDetailPageMode {
                detailPageView
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isAnyDetailOpen)
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentAreaWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, w in contentAreaWidth = w }
            }
        )
    }

    private var isHomeActive: Bool {
        selectedTab == .home && selectedFolderID == nil && selectedSourceID == nil
    }

    @ViewBuilder
    private var tabContentBody: some View {
        if let sourceID = selectedSourceID,
           let source = externalSourceStorage.source(for: sourceID) {
            SourceDetailView(
                source: source,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale
            )
        } else if let folderID = selectedFolderID, selectedTab.isFixed {
            FolderDetailView(
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                folderID: folderID,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale,
                selectedItemIDs: $selectedItemIDs,
                subFoldersCollapsed: $subFoldersCollapsed,
                searchText: debouncedSearchText,
                onSelectSubFolder: { subFolderID in
                    selectedFolderID = subFolderID
                    expandPathToFolder(subFolderID)
                },
                onOpenNote: { note in openNoteDetail(note) },
                onShowBookmarkDetails: { openBookmarkDetails($0) },
                onEditDateCard: { dateCard in
                    newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                },
                onEditContact: { contact in
                    newContactEditorContext = ContactEditorContext(existingContact: contact)
                },
                onOpenDateCard: { openDateCardDetail($0) },
                onOpenContact: { openContactDetail($0) }
            )
        } else {
            ZStack {
                // Home is always alive — survives tab switches without resetting state
                HomeDashboardView(
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    libraryViewModel: libraryViewModel,
                    selectedFolderID: selectedFolderID,
                    displayMode: $homeDisplayMode,
                    cardSizeScale: $homeCardSizeScale,
                    continueSectionCollapsed: $continueSectionCollapsed,
                    selectedItemIDs: $selectedItemIDs,
                    sortMode: $homeSort,
                    entityFilter: $homeEntityFilter,
                    searchText: debouncedSearchText,
                    onOpenNote: { note in openNoteDetail(note) },
                    onShowBookmarkDetails: { openBookmarkDetails($0) },
                    onEditDateCard: { dateCard in
                        newEventEditorContext = DateCardEditorContext(
                            existingCard: dateCard,
                            defaultDate: dateCard.startAt
                        )
                    },
                    onEditContact: { contact in
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    },
                    onOpenDateCard: { openDateCardDetail($0) },
                    onOpenContact: { openContactDetail($0) }
                )
                .opacity(isHomeActive ? 1 : 0)
                .allowsHitTesting(isHomeActive)

                // Other tabs are created/destroyed on demand
                if !isHomeActive, selectedFolderID == nil, selectedSourceID == nil {
                    switch selectedTab {
                    case .home:
                        EmptyView()
                    case .savedView(let id, _):
                        if let savedView = savedViewStorage.savedView(for: id) {
                            SavedViewTabContent(
                                savedView: savedView,
                                libraryViewModel: libraryViewModel,
                                folders: bookmarksViewModel.folders,
                                onOpenBookmark: { bookmark in
                                    if NSEvent.modifierFlags.contains(.command) {
                                        bookmarksViewModel.open(bookmark)
                                    } else {
                                        openBookmarkDetails(bookmark)
                                    }
                                },
                                onOpenNote: { note in
                                    openNoteDetail(note)
                                },
                                onDeleteBookmark: { bookmark in
                                    bookmarksViewModel.deleteBookmarks([bookmark])
                                },
                                onDeleteNote: { note in
                                    notesViewModel.deleteNotes([note])
                                },
                                onRenameNote: { note, newTitle in
                                    NotesStorage.shared.rename(note: note, to: newTitle)
                                },
                                onMoveBookmarkToFolder: { bookmark, folderID in
                                    _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
                                },
                                onMoveNoteToFolder: { note, folderID in
                                    _ = notesViewModel.assignNote(note, toFolder: folderID)
                                },
                                onOpenDateCard: { openDateCardDetail($0) },
                                onOpenContact: { openContactDetail($0) },
                                searchText: debouncedSearchText,
                                onUpdateSavedView: { updated in
                                    _ = savedViewStorage.updateSavedView(updated)
                                    if case .savedView(let selectedID, _) = selectedTab,
                                       selectedID == updated.id {
                                        selectedTab = .savedView(id: updated.id, name: updated.name)
                                    }
                                },
                                onDeleteSavedView: { savedViewID in
                                    deleteSavedView(savedViewID)
                                }
                            )
                        } else {
                            EmptyStateView(
                                icon: "square.grid.2x2",
                                title: "Saved view not found"
                            )
                        }
                    case .search(_, let query):
                        SearchTabContent(
                            query: query,
                            bookmarks: bookmarksViewModel.bookmarks,
                            notes: notesViewModel.notes,
                            onOpenBookmark: { bookmark in
                                if NSEvent.modifierFlags.contains(.command) {
                                    bookmarksViewModel.open(bookmark)
                                } else {
                                    openBookmarkDetails(bookmark)
                                }
                            },
                            onOpenNote: { note in
                                openNoteDetail(note)
                            }
                        )
                    case .externalSource(let id, _):
                        if let source = externalSourceStorage.source(for: id) {
                            SourceDetailView(
                                source: source,
                                displayMode: $homeDisplayMode,
                                cardSizeScale: $homeCardSizeScale
                            )
                        } else {
                            EmptyStateView(
                                icon: "folder.badge.gear",
                                title: "Source not found"
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Note Creation

    private func createNoteAndOpen(title: String, content: String) {
        // Create on disk first so selectNote picks up the right path/content
        var note = NotesStorage.shared.createNew()

        if !title.isEmpty {
            NotesStorage.shared.rename(note: note, to: title)
            // Refresh from storage so we have the updated filename/title
            note = NotesStorage.shared.notes.first(where: { $0.id == note.id }) ?? note
        }

        if !content.isEmpty {
            note.content = content
            NotesStorage.shared.save(note: note)
        }

        openNoteDetail(note)
    }

    // MARK: - Note Detail

    private func openNoteDetail(_ note: Note) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        let wasExpanded = isAnyDetailOpen
        // Clear other detail state silently
        detailBookmarkID = nil; detailsDraft = nil; detailsErrorMessage = nil
        selectedDateCard = nil; selectedContact = nil
        // Open note
        notesViewModel.selectNote(note)
        selectedNote = note
        isEditingNoteTitle = false
        DispatchQueue.main.async { notesViewModel.focusEditorIfFindBarHidden() }
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    private func closeNoteDetail() {
        guard isNoteDetailOpen else { return }
        notesViewModel.flushSave()
        selectedNote = nil
        notesViewModel.activeExternalFile = nil
        isEditingNoteTitle = false
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    // MARK: - Bookmark Details (Centralized)

    private var isDetailOpen: Bool {
        detailBookmarkID != nil && detailsDraft != nil
    }

    private var isDetailSlideOut: Bool {
        isDetailOpen && detailViewMode == .slideOut
    }

    private var maxSlideOutWidth: CGFloat {
        let inset = BookmarksDesign.detailsSlideOutFloatInset
        return max(
            BookmarksDesign.detailsSlideOutMinWidth,
            contentAreaWidth - inset * 2
        )
    }

    private var isDetailFullPanel: Bool {
        isDetailOpen && detailViewMode == .fullPanel
    }

    private var isDetailPageMode: Bool {
        isDetailOpen && detailViewMode == .page
    }

    private var isGenericDetailOpen: Bool {
        selectedDateCard != nil || selectedContact != nil
    }

    private var isAnyDetailOpen: Bool {
        isDetailOpen || isGenericDetailOpen || isNoteDetailOpen
    }

    private var isGenericDetailSlideOut: Bool {
        isGenericDetailOpen && detailViewMode == .slideOut
    }

    private var isGenericDetailFullPanel: Bool {
        isGenericDetailOpen && detailViewMode == .fullPanel
    }

    private var isGenericDetailPageMode: Bool {
        isGenericDetailOpen && detailViewMode == .page
    }

    private var isAnyDetailPageMode: Bool {
        isDetailPageMode || isGenericDetailPageMode || isNoteDetailPageMode
    }

    private var selectedDetailsBookmark: Bookmark? {
        guard let detailBookmarkID else { return nil }
        return bookmarksViewModel.bookmarks.first(where: { $0.id == detailBookmarkID })
    }

    private func openBookmarkDetails(_ bookmark: Bookmark) {
        if isSearchPaletteVisible {
            isSearchPaletteVisible = false
        }
        if isNoteDetailOpen { closeNoteDetail() }
        detailBookmarkID = bookmark.id
        detailsDraft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsErrorMessage = nil
        if detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    private func closeBookmarkDetails() {
        guard isDetailOpen else { return }
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    private func openDateCardDetail(_ dateCard: DateCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        let wasExpanded = isAnyDetailOpen
        // Clear all detail state silently (no restore notification — we're about to show a new detail)
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedContact = nil
        selectedDateCard = dateCard
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    private func openContactDetail(_ contact: ContactCard) {
        if isSearchPaletteVisible { isSearchPaletteVisible = false }
        if isNoteDetailOpen { closeNoteDetail() }
        let wasExpanded = isAnyDetailOpen
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedContact = contact
        if !wasExpanded, detailViewMode == .slideOut {
            NotificationCenter.default.post(
                name: .expandCiderPanelForSlideOut,
                object: nil,
                userInfo: ["minimumWidth": BookmarksDesign.detailsSlideOutExpandedPanelMinWidth]
            )
        }
    }

    private func closeGenericDetail() {
        guard isGenericDetailOpen else { return }
        selectedDateCard = nil
        selectedContact = nil
        NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
    }

    private func closeAllDetails() {
        let anyOpen = isAnyDetailOpen
        if isNoteDetailOpen { notesViewModel.flushSave() }
        detailBookmarkID = nil
        detailsDraft = nil
        detailsErrorMessage = nil
        selectedDateCard = nil
        selectedContact = nil
        selectedNote = nil
        notesViewModel.activeExternalFile = nil
        isEditingNoteTitle = false
        if anyOpen {
            NotificationCenter.default.post(name: .restoreCiderPanelAfterSlideOut, object: nil)
        }
    }

    private func saveBookmarkDetails() {
        guard let detailsDraft else { return }
        guard let selectedBookmark = selectedDetailsBookmark else {
            detailsErrorMessage = "This bookmark is no longer available."
            return
        }

        let parsedTags = detailsDraft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceURL: String? = detailsDraft.sourceURL != detailsDraft.originalURLString
            ? detailsDraft.sourceURL
            : nil

        let didSave = bookmarksViewModel.updateDetails(
            for: selectedBookmark,
            title: detailsDraft.title,
            notes: detailsDraft.notes,
            tags: parsedTags,
            urlString: sourceURL
        )

        if !didSave {
            detailsErrorMessage = "Could not save bookmark details."
        }
    }

    private func deleteDetailBookmark() {
        guard let bookmark = selectedDetailsBookmark else { return }
        closeBookmarkDetails()
        bookmarksViewModel.deleteBookmarks([bookmark])
    }

    private func assignDetailBookmarkToFolder(_ folderID: UUID?) {
        guard let bookmark = selectedDetailsBookmark else { return }
        _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
    }

    private func copyDetailURL() {
        guard let detailsDraft else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(detailsDraft.sourceURL, forType: .string)
    }

    private func openDetailURL() {
        guard let detailsDraft,
              let url = URL(string: detailsDraft.sourceURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func changeDetailViewMode(_ mode: DetailViewMode) {
        withAnimation(reduceMotion ? .none : .snappy) {
            detailViewMode = mode
        }
        var config = CiderConfig.load()
        config.detailViewMode = mode
        config.save()
    }

    // MARK: - Detail Views

    private func makeDetailDraftBinding(fallback: BookmarkDetailsDraft) -> Binding<BookmarkDetailsDraft> {
        Binding(
            get: { self.detailsDraft ?? fallback },
            set: { next in
                self.detailsDraft = next
                self.detailsErrorMessage = nil
            }
        )
    }

    @ViewBuilder
    private var detailSlideOutContainer: some View {
        if let draft = detailsDraft {
        DetailSlideOutView(
            draft: makeDetailDraftBinding(fallback: draft),
            bookmark: selectedDetailsBookmark,
            errorMessage: detailsErrorMessage,
            folders: bookmarksViewModel.folders,
            width: min(detailSlideOutWidth, maxSlideOutWidth),
            maxWidth: maxSlideOutWidth,
            detailViewMode: detailViewMode,
            onResize: { newWidth in
                let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                detailSlideOutWidth = clamped
                detailWidthSaveTask?.cancel()
                detailWidthSaveTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    var config = CiderConfig.load()
                    config.detailSlideOutWidth = clamped
                    config.save()
                }
            },
            onDelete: deleteDetailBookmark,
            onFolderChanged: assignDetailBookmarkToFolder,
            onOpenURL: openDetailURL,
            onCopyURL: copyDetailURL,
            onSave: saveBookmarkDetails,
            onCancel: closeBookmarkDetails,
            onModeChange: changeDetailViewMode
        )
        }
    }

    @ViewBuilder
    private var detailFullPanelOverlay: some View {
        if let draft = detailsDraft {
            DetailSlideOutView(
                draft: makeDetailDraftBinding(fallback: draft),
                bookmark: selectedDetailsBookmark,
                errorMessage: detailsErrorMessage,
                folders: bookmarksViewModel.folders,
                detailViewMode: detailViewMode,
                onDelete: deleteDetailBookmark,
                onFolderChanged: assignDetailBookmarkToFolder,
                onOpenURL: openDetailURL,
                onCopyURL: copyDetailURL,
                onSave: saveBookmarkDetails,
                onCancel: closeBookmarkDetails,
                onModeChange: changeDetailViewMode,
                showDragHandle: false
            )
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        }
    }

    // MARK: - Generic Item Detail Views (Date Cards, Contacts)

    @ViewBuilder
    private var genericDetailSlideOutContainer: some View {
        if let dateCard = selectedDateCard {
            GenericItemDetailPanel(
                title: dateCard.title,
                detailViewMode: detailViewMode,
                width: min(detailSlideOutWidth, maxSlideOutWidth),
                maxWidth: maxSlideOutWidth,
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                DateCardDetailView(
                    dateCard: dateCard,
                    onEdit: {
                        closeGenericDetail()
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onDismiss: closeGenericDetail
                )
            }
        } else if let contact = selectedContact {
            GenericItemDetailPanel(
                title: contact.displayName,
                detailViewMode: detailViewMode,
                width: min(detailSlideOutWidth, maxSlideOutWidth),
                maxWidth: maxSlideOutWidth,
                onResize: { newWidth in
                    let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                    detailSlideOutWidth = clamped
                },
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        closeGenericDetail()
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    },
                    onDismiss: closeGenericDetail
                )
            }
        }
    }

    @ViewBuilder
    private var genericDetailFullPanelOverlay: some View {
        if let dateCard = selectedDateCard {
            GenericItemDetailPanel(
                title: dateCard.title,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                DateCardDetailView(
                    dateCard: dateCard,
                    onEdit: {
                        closeGenericDetail()
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        } else if let contact = selectedContact {
            GenericItemDetailPanel(
                title: contact.displayName,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        closeGenericDetail()
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(BookmarksDesign.detailsSlideOutFloatInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var detailPageView: some View {
        if let draft = detailsDraft {
            bookmarkDetailPageView(draft: draft)
        } else if selectedDateCard != nil || selectedContact != nil {
            genericDetailPageView
        } else if isNoteDetailPageMode {
            noteDetailPageView
        }
    }

    @ViewBuilder
    private var detailPageTitleBar: some View {
        Button {
            closeCurrentDetailForPageMode()
        } label: {
            Image(systemName: "chevron.left")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back")

        Text(currentDetailPageTitle)
            .font(CiderFont.subheadingSemibold)
            .foregroundColor(CiderColors.primary)
            .lineLimit(1)

        Spacer(minLength: Spacing.sm)

        ForEach(DetailViewMode.allCases, id: \.self) { mode in
            Button {
                changeDetailViewMode(mode)
            } label: {
                Image(systemName: detailModeIcon(mode))
                    .font(CiderFont.label)
                    .foregroundColor(detailViewMode == mode ? CiderColors.controlAccent : CiderColors.tertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(mode.displayName)
        }
    }

    private func detailModeIcon(_ mode: DetailViewMode) -> String {
        switch mode {
        case .slideOut: return "sidebar.trailing"
        case .fullPanel: return "rectangle"
        case .page: return "rectangle.fill"
        }
    }

    private var currentDetailPageTitle: String {
        if let draft = detailsDraft { return draft.title }
        if let dateCard = selectedDateCard { return dateCard.title }
        if let contact = selectedContact { return contact.displayName }
        if isNoteDetailPageMode {
            return notesViewModel.selectedNote?.title ?? selectedNote?.title ?? "Untitled"
        }
        return "Details"
    }

    private func closeCurrentDetailForPageMode() {
        if isDetailPageMode {
            closeBookmarkDetails()
        } else if isGenericDetailPageMode {
            closeGenericDetail()
        } else if isNoteDetailPageMode {
            closeNoteDetail()
        }
    }

    @ViewBuilder
    private func bookmarkDetailPageView(draft: BookmarkDetailsDraft) -> some View {
        DetailSlideOutView(
            draft: makeDetailDraftBinding(fallback: draft),
            bookmark: selectedDetailsBookmark,
            errorMessage: detailsErrorMessage,
            folders: bookmarksViewModel.folders,
            detailViewMode: detailViewMode,
            onDelete: deleteDetailBookmark,
            onFolderChanged: assignDetailBookmarkToFolder,
            onOpenURL: openDetailURL,
            onCopyURL: copyDetailURL,
            onSave: saveBookmarkDetails,
            onCancel: closeBookmarkDetails,
            onModeChange: changeDetailViewMode,
            showDragHandle: false
        )
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    @ViewBuilder
    private var genericDetailPageView: some View {
        if let dateCard = selectedDateCard {
            GenericItemDetailPanel(
                title: dateCard.title,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                DateCardDetailView(
                    dateCard: dateCard,
                    onEdit: {
                        closeGenericDetail()
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        } else if let contact = selectedContact {
            GenericItemDetailPanel(
                title: contact.displayName,
                detailViewMode: detailViewMode,
                showDragHandle: false,
                onClose: closeGenericDetail,
                onModeChange: changeDetailViewMode
            ) {
                ContactDetailView(
                    contact: contact,
                    onEdit: {
                        closeGenericDetail()
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    },
                    onDismiss: closeGenericDetail
                )
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.md)
        }
    }

    private var noteDetailPageView: some View {
        let title = notesViewModel.selectedNote?.title ?? selectedNote?.title ?? "Untitled"
        return GenericItemDetailPanel(
            title: title,
            detailViewMode: detailViewMode,
            showDragHandle: false,
            scrollsContent: false,
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode
        ) {
            InlineNoteEditorView(viewModel: notesViewModel)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Note Detail Views

    @ViewBuilder
    private var noteDetailSlideOutContainer: some View {
        let title = notesViewModel.selectedNote?.title ?? selectedNote?.title ?? "Untitled"
        GenericItemDetailPanel(
            title: title,
            detailViewMode: detailViewMode,
            width: min(detailSlideOutWidth, maxSlideOutWidth),
            maxWidth: maxSlideOutWidth,
            scrollsContent: false,
            onResize: { newWidth in
                let clamped = min(max(BookmarksDesign.detailsSlideOutMinWidth, newWidth), maxSlideOutWidth)
                detailSlideOutWidth = clamped
            },
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode
        ) {
            InlineNoteEditorView(viewModel: notesViewModel)
        }
    }

    @ViewBuilder
    private var noteDetailFullPanelOverlay: some View {
        let title = notesViewModel.selectedNote?.title ?? selectedNote?.title ?? "Untitled"
        GenericItemDetailPanel(
            title: title,
            detailViewMode: detailViewMode,
            showDragHandle: false,
            scrollsContent: false,
            onClose: closeNoteDetail,
            onModeChange: changeDetailViewMode
        ) {
            InlineNoteEditorView(viewModel: notesViewModel)
        }
        .padding(BookmarksDesign.detailsSlideOutFloatInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .transition(.opacity)
    }

    // MARK: - Search Tab Management

    private func spawnSearchTab(_ query: String) {
        let tab = CiderTab.search(id: UUID(), query: query)
        dynamicTabs.append(tab)
        selectedTab = tab
    }

    private func closeTab(_ tab: CiderTab) {
        guard tab.isCloseable else { return }
        if case .savedView(let id, _) = tab, var savedView = savedViewStorage.savedView(for: id) {
            savedView.isTabPinned = false
            _ = savedViewStorage.updateSavedView(savedView)
            if selectedTab == tab {
                selectedTab = .home
            }
            return
        }
        if case .externalSource(let id, _) = tab, var source = externalSourceStorage.source(for: id) {
            source.isTabPinned = false
            externalSourceStorage.updateSource(source)
            if selectedTab == tab {
                selectedTab = .home
            }
            return
        }
        dynamicTabs.removeAll { $0 == tab }
        if selectedTab == tab {
            selectedTab = .home
        }
    }

    private func createSavedViewFromCurrentHomeState() {
        var config = CiderConfig.load()
        if !config.enableSavedViewTabs {
            config.enableSavedViewTabs = true
            config.save()
        }

        let name = nextSavedViewName()
        let layout = SavedViewLayoutSpec(
            displayMode: homeDisplayMode,
            cardSizeScale: homeCardSizeScale,
            showsGhostCells: true,
            showsCalendarProjection: false
        )
        let savedView = savedViewStorage.createSavedView(
            name: name,
            layoutSpec: layout
        )
        selectedTab = .savedView(id: savedView.id, name: savedView.name)
    }

    private func deleteSavedView(_ id: UUID) {
        let wasSelected = selectedTab.savedViewID == id
        _ = savedViewStorage.deleteSavedView(id)
        if wasSelected {
            selectedTab = .home
        }
    }

    private func nextSavedViewName() -> String {
        let usedNames = Set(savedViewStorage.pinnedSavedViews().map(\.name))
        var index = 1
        while usedNames.contains("View \(index)") {
            index += 1
        }
        return "View \(index)"
    }

    private func expandPathToFolder(_ folderID: UUID) {
        let folderByID = Dictionary(uniqueKeysWithValues: bookmarksViewModel.folders.map { ($0.id, $0) })
        var cursorID: UUID? = folderID
        var visited = Set<UUID>()

        while let currentID = cursorID,
              !visited.contains(currentID),
              let folder = folderByID[currentID] {
            visited.insert(currentID)
            cursorID = folder.parentID
        }

        for id in visited {
            expandedFolderIDs.insert(id)
        }
    }

    private func isRootFolder(_ folderID: UUID) -> Bool {
        bookmarksViewModel.folders.first(where: { $0.id == folderID })?.parentID == nil
    }

    private func deleteFolder(_ folderID: UUID) {
        if selectedFolderID == folderID {
            selectedFolderID = nil
        }
        bookmarksViewModel.deleteFolder(folderID)
    }

    // MARK: - Select All

    private func selectAllVisibleItems() {
        if let folderID = selectedFolderID, selectedTab.isFixed {
            let bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
            let notes = notesViewModel.notes.filter { $0.folderID == folderID }
            for b in bookmarks { selectedItemIDs.insert("bookmark-\(b.id.uuidString)") }
            for n in notes { selectedItemIDs.insert("note-\(n.id.uuidString)") }
        } else {
            switch selectedTab {
            case .home:
                // TODO: CH-C04 — date cards and contacts visible in the feed are not selected here;
                // address once bulk-delete/move actions support all entity types.
                for b in bookmarksViewModel.bookmarks { selectedItemIDs.insert("bookmark-\(b.id.uuidString)") }
                for n in notesViewModel.notes { selectedItemIDs.insert("note-\(n.id.uuidString)") }
            default:
                break
            }
        }
    }

    // MARK: - Bulk Selection Actions

    private func deleteSelectedItems() {
        var bookmarksToDelete: [Bookmark] = []
        var notesToDelete: [Note] = []

        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    bookmarksToDelete.append(bookmark)
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    notesToDelete.append(note)
                }
            }
        }

        if !bookmarksToDelete.isEmpty {
            bookmarksViewModel.deleteBookmarks(bookmarksToDelete)
        }
        if !notesToDelete.isEmpty {
            notesViewModel.deleteNotes(notesToDelete)
        }

        selectedItemIDs.removeAll()
    }

    private func moveSelectedToFolder(_ folderID: UUID?) {
        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    _ = bookmarksViewModel.assign(bookmark, toFolder: folderID)
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    _ = notesViewModel.assignNote(note, toFolder: folderID)
                }
            }
        }

        selectedItemIDs.removeAll()
    }

    // MARK: - Collapse State Sync

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }
}
