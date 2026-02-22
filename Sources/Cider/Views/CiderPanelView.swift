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
    @State private var suppressSidebarAutoExpandForDetails = false
    @State private var cardScaleSaveTask: Task<Void, Never>?
    @State private var editingNoteID: UUID?
    @State private var isEditingNoteTitle = false
    @State private var showRestoreSnapshotAlert = false
    @State private var pendingSnapshotChoice: NotesRecoverySnapshotChoice?
    @State private var newEventEditorContext: DateCardEditorContext?
    @State private var newContactEditorContext: ContactEditorContext?

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
            suppressSidebarAutoExpand: suppressSidebarAutoExpandForDetails,
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
                            selectedFolderID = nil
                            selectedTab = .home
                            bookmarksViewModel.pendingDetailBookmarkID = bookmark.id
                        }
                    },
                    onOpenNote: { note in
                        openNoteInline(note)
                    },
                    onSpawnSearchTab: spawnSearchTab,
                    onDismiss: { isSearchPaletteVisible = false }
                )
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .environment(\.textScale, textScale)
        .onChange(of: selectedTab) { _, _ in
            selectedFolderID = nil
            selectedSourceID = nil
            selectedItemIDs.removeAll()
        }
        .onChange(of: selectedFolderID) { _, _ in
            selectedItemIDs.removeAll()
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
        .onReceive(NotificationCenter.default.publisher(for: .expandCiderPanelForDetailModal)) { _ in
            suppressSidebarAutoExpandForDetails = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .restoreCiderPanelAfterDetailModal)) { _ in
            suppressSidebarAutoExpandForDetails = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .dismissCiderPanel)) { _ in
            suppressSidebarAutoExpandForDetails = false
            if isEditorActive {
                closeNoteEditor()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ciderConfigChanged)) { _ in
            textScale = CiderConfig.load().textSize.scale
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleNoteEditor)) { notification in
            if isEditorActive {
                closeNoteEditor()
            } else if let note = notification.object as? Note {
                openNoteInline(note)
            } else {
                let note = NotesStorage.shared.createNew()
                openNoteInline(note)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureBookmark)) { _ in
            _ = bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .editorRequestClose)) { _ in
            if isEditorActive {
                closeNoteEditor()
            }
        }
        .sheet(item: $newEventEditorContext) { context in
            DateCardEditorSheet(
                existingCard: context.existingCard,
                defaultDate: context.defaultDate,
                onSave: { title, details, startAt, endAt, allDay, location, amount, labelIDs in
                    LibraryItemEditor.saveDateCard(
                        existingCard: context.existingCard,
                        title: title,
                        details: details,
                        startAt: startAt,
                        endAt: endAt,
                        allDay: allDay,
                        location: location,
                        amount: amount,
                        labelIDs: labelIDs
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
                if isEditorActive {
                    closeNoteEditor()
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
        if isEditorActive {
            noteEditorTitleBar
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

    // MARK: - Note Editor Title Bar

    @ViewBuilder
    private var noteEditorTitleBar: some View {
        // Back button
        Button {
            closeNoteEditor()
        } label: {
            Image(systemName: "chevron.left")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back")

        // Editable title
        if isEditingNoteTitle {
            TextField("Note title", text: $notesViewModel.editingTitle, onCommit: {
                notesViewModel.renameCurrentNote(to: notesViewModel.editingTitle)
                isEditingNoteTitle = false
            })
            .textFieldStyle(.plain)
            .font(CiderFont.subheadingSemibold)
            .foregroundColor(CiderColors.primary)
        } else {
            let displayTitle = notesViewModel.activeExternalFile?.title ?? notesViewModel.selectedNote?.title ?? "Note"
            Text(displayTitle)
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    if notesViewModel.selectedNote != nil {
                        isEditingNoteTitle = true
                    }
                }
        }

        Spacer(minLength: Spacing.sm)

        // Note switcher dropdown
        Menu {
            Button {
                let note = NotesStorage.shared.createNew()
                openNoteInline(note)
            } label: {
                Label("New Note", systemImage: "plus")
            }

            if !notesViewModel.notes.isEmpty {
                Divider()
                ForEach(notesViewModel.notes) { note in
                    Button {
                        openNoteInline(note)
                    } label: {
                        if note.id == notesViewModel.selectedNote?.id {
                            Label(note.title, systemImage: "checkmark")
                        } else {
                            Text(note.title)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "doc.text")
                .font(CiderFont.label)
                .foregroundColor(CiderColors.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .help("Switch note")

        // Formatting menu
        noteFormattingMenu
    }

    @ViewBuilder
    private var noteFormattingMenu: some View {
        Menu {
            Button {
                notesViewModel.toggleFormattingToolbarPinned()
            } label: {
                Label(
                    notesViewModel.isFormattingToolbarPinned ? "Unpin Toolbar" : "Pin Toolbar",
                    systemImage: notesViewModel.isFormattingToolbarPinned ? "pin.slash" : "pin"
                )
            }

            Divider()

            Section("History") {
                Button {
                    notesViewModel.showFindBar()
                } label: {
                    Label("Find in Note", systemImage: "magnifyingglass")
                }

                Divider()

                Button {
                    notesViewModel.editorUndo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                Button {
                    notesViewModel.editorRedo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
            }

            Section("Recovery") {
                if notesViewModel.recoverySnapshotChoices.isEmpty {
                    Button("No snapshots yet") {}
                        .disabled(true)
                } else {
                    Menu {
                        ForEach(notesViewModel.recoverySnapshotChoices) { choice in
                            Button {
                                pendingSnapshotChoice = choice
                                showRestoreSnapshotAlert = true
                            } label: {
                                Text(
                                    "\(choice.title) (\(choice.snapshotDate.formatted(.relative(presentation: .named))))"
                                )
                            }
                        }
                    } label: {
                        Label("Quick Restore", systemImage: "clock.arrow.circlepath")
                    }

                    Menu {
                        ForEach(Array(notesViewModel.allRecoverySnapshotChoices.prefix(12))) { choice in
                            Button {
                                pendingSnapshotChoice = choice
                                showRestoreSnapshotAlert = true
                            } label: {
                                Text(choice.title)
                            }
                        }

                        if notesViewModel.allRecoverySnapshotChoices.count > 12 {
                            Divider()
                            Text("Showing 12 newest snapshots")
                        }
                    } label: {
                        Label("All Snapshots", systemImage: "clock")
                    }
                }
            }

            Section("Alignment") {
                Button { notesViewModel.editorAlignLeft() } label: {
                    Label("Align Left", systemImage: "text.alignleft")
                }
                Button { notesViewModel.editorAlignCenter() } label: {
                    Label("Align Center", systemImage: "text.aligncenter")
                }
                Button { notesViewModel.editorAlignRight() } label: {
                    Label("Align Right", systemImage: "text.alignright")
                }
            }

            Section("Text Style") {
                Button { notesViewModel.editorToggleBold() } label: { Label("Bold", systemImage: "bold") }
                Button { notesViewModel.editorToggleItalic() } label: { Label("Italic", systemImage: "italic") }
                Button { notesViewModel.editorToggleUnderline() } label: { Label("Underline", systemImage: "underline") }
                Button { notesViewModel.editorPromptForLink() } label: { Label("Add Link", systemImage: "link.badge.plus") }
                Button { notesViewModel.editorRemoveLink() } label: { Label("Remove Link", systemImage: "link") }
            }

            Section("Selection Text Size") {
                Button("Small") { notesViewModel.editorSetTextSizeSmall() }
                Button("Normal") { notesViewModel.editorSetTextSizeNormal() }
                Button("Large") { notesViewModel.editorSetTextSizeLarge() }
                Button("Extra Large") { notesViewModel.editorSetTextSizeExtraLarge() }
                Button("Reset Size") { notesViewModel.editorResetTextSize() }
            }

            Section("Note Text Size") {
                ForEach(NotesEditorTextSize.allCases, id: \.self) { size in
                    Button {
                        notesViewModel.setNotesEditorTextSize(size)
                    } label: {
                        if notesViewModel.notesEditorTextSize == size {
                            Label(size.displayName, systemImage: "checkmark")
                        } else {
                            Text(size.displayName)
                        }
                    }
                }
            }

            Section("Lists") {
                Button { notesViewModel.editorToggleBulletList() } label: { Label("Bullet List", systemImage: "list.bullet") }
                Button { notesViewModel.editorToggleOrderedList() } label: { Label("Numbered List", systemImage: "list.number") }
                Button { notesViewModel.editorToggleTaskList() } label: { Label("Task List", systemImage: "checklist") }
            }

            Section("Table") {
                Button("Insert Table") { notesViewModel.editorInsertTable() }
                Button("Add Row Above") { notesViewModel.editorAddRowBefore() }
                Button("Add Row Below") { notesViewModel.editorAddRowAfter() }
                Button("Delete Row") { notesViewModel.editorDeleteRow() }
                Button("Add Column Left") { notesViewModel.editorAddColumnBefore() }
                Button("Add Column Right") { notesViewModel.editorAddColumnAfter() }
                Button("Delete Column") { notesViewModel.editorDeleteColumn() }
                Button("Merge Cells") { notesViewModel.editorMergeCells() }
                Button("Split Cell") { notesViewModel.editorSplitCell() }
                Button("Toggle Header Row") { notesViewModel.editorToggleHeaderRow() }
                Button("Toggle Header Column") { notesViewModel.editorToggleHeaderColumn() }
                Button("Delete Table") { notesViewModel.editorDeleteTable() }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(CiderFont.labelMedium)
                .foregroundColor(CiderColors.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .disabled(notesViewModel.selectedNote == nil)
        .help("Formatting")
        .alert("Restore snapshot?", isPresented: $showRestoreSnapshotAlert) {
            Button("Restore", role: .destructive) {
                if let choice = pendingSnapshotChoice {
                    notesViewModel.restoreSnapshot(choice)
                }
                pendingSnapshotChoice = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSnapshotChoice = nil
            }
        } message: {
            if let choice = pendingSnapshotChoice {
                Text(
                    "This replaces the current note with the \(choice.title.lowercased()) snapshot from \(choice.snapshotDate.formatted(date: .abbreviated, time: .shortened))."
                )
            } else {
                Text("This replaces the current note with the latest saved snapshot.")
            }
        }
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
        editingNoteID != nil || notesViewModel.activeExternalFile != nil
    }

    private var contentArea: some View {
        ZStack {
            tabContentBody
                .opacity(isEditorActive ? 0 : 1)
                .allowsHitTesting(!isEditorActive)

            if isEditorActive {
                InlineNoteEditorView(viewModel: notesViewModel)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isHomeActive: Bool {
        selectedTab == .home && selectedFolderID == nil && selectedSourceID == nil && !isEditorActive
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
                onSelectSubFolder: { subFolderID in
                    selectedFolderID = subFolderID
                    expandPathToFolder(subFolderID)
                },
                onOpenNote: { note in openNoteInline(note) }
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
                    onOpenNote: { note in openNoteInline(note) },
                    onEditDateCard: { dateCard in
                        newEventEditorContext = DateCardEditorContext(
                            existingCard: dateCard,
                            defaultDate: dateCard.startAt
                        )
                    },
                    onEditContact: { contact in
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    }
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
                                        selectedFolderID = nil
                                        selectedTab = .home
                                        bookmarksViewModel.pendingDetailBookmarkID = bookmark.id
                                    }
                                },
                                onOpenNote: { note in
                                    openNoteInline(note)
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
                                    selectedFolderID = nil
                                    selectedTab = .home
                                    bookmarksViewModel.pendingDetailBookmarkID = bookmark.id
                                }
                            },
                            onOpenNote: { note in
                                openNoteInline(note)
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

        openNoteInline(note)
    }

    // MARK: - Inline Note Editor

    private func openNoteInline(_ note: Note) {
        notesViewModel.selectNote(note)
        editingNoteID = note.id
        isEditingNoteTitle = false

        DispatchQueue.main.async {
            notesViewModel.focusEditorIfFindBarHidden()
        }
    }

    private func closeNoteEditor() {
        notesViewModel.flushSave()
        editingNoteID = nil
        notesViewModel.activeExternalFile = nil
        isEditingNoteTitle = false
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
