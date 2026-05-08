import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    var surface: CiderWorkspaceSurface = .mainWindow
    @ObservedObject var savedViewStorage = SavedViewStorage.shared
    @StateObject var libraryViewModel = LibraryViewModel()
    @State var selectedTab: CiderTab?
    @State var isCollapsed = false
    @State var selectedFolderID: UUID?
    @State var selectedItemIDs: Set<String> = []
    @State var expandedFolderIDs: Set<UUID> = []
    @State var isSearchPaletteVisible = false
    @State var dynamicTabs: [CiderTab] = []
    @State var isHomeViewOptionsVisible = false
    @State var showNewItemPicker = false
    @State var homeDisplayMode: LibraryDisplayMode = CiderConfig.load().homeDisplayMode
    @State var homeCardSizeScale: Double = CiderConfig.load().homeCardSizeScale ?? 1.0
    @State var hideCardFooters: Bool = CiderConfig.load().hideCardFooters
    @State var showCardDetailsOnHover: Bool = CiderConfig.load().showCardDetailsOnHover
    @State var homeSort: LibrarySortMode = CiderConfig.load().homeSort
    @State var homeEntityFilter: Set<LibraryEntityType> = CiderConfig.load().homeEntityFilter
    @State var subFoldersCollapsed: Bool = CiderConfig.load().subFoldersCollapsed
    @State var textScale: CGFloat = CiderConfig.load().textSize.scale
    // Detail view state (centralized)
    @State var detailBookmarkID: UUID?
    @State var bookmarkDetailViewMode: DetailViewMode = {
        let config = CiderConfig.load()
        return config.bookmarkDetailViewMode ?? config.detailViewMode
    }()
    @State var noteDetailViewMode: DetailViewMode = {
        let config = CiderConfig.load()
        return config.noteDetailViewMode ?? config.detailViewMode
    }()
    @State var detailSlideOutWidth: CGFloat = CiderConfig.load().detailSlideOutWidth ?? 400
    @State var detailsDraft: BookmarkDetailsDraft?
    @State var detailsErrorMessage: String?
    @State var bookmarkHeroMode: BookmarkHeroMode = .thumbnail
    @State var bookmarkMetadataVisible: Bool = true
    @State var genericMetadataVisible: Bool = true
    @StateObject var detailWebViewStore = DetailWebViewStore()
    @State var detailWidthSaveTask: Task<Void, Never>?
    @State var selectedDateCard: DateCard?
    @State var selectedContact: ContactCard?
    @State var selectedTodoCard: TodoCard?
    @State var selectedVaultFile: VaultFile?
    @State var selectedKanbanBoardID: String?
    @State var selectedKanbanCardID: String?
    @State var kanbanCardDraft: KanbanCardDraft?
    @State var kanbanMetadataVisible: Bool = true
    @State var cardScaleSaveTask: Task<Void, Never>?
    @State var sidebarSearchText: String = ""
    @State var debouncedSearchText: String = ""
    @State var searchDebounceTask: Task<Void, Never>?
    @State var selectedNote: Note?
    @State var isEditingNoteTitle = false
    @State var newEventEditorContext: DateCardEditorContext?
    @State var newContactEditorContext: ContactEditorContext?
    @State var newTodoEditorContext: TodoEditorContext?
    @State var contentAreaWidth: CGFloat = 800
    @State var isURLDropTargeted = false

    @State var selectedTagIDs: Set<UUID> = []
    @State var tagsCollapsed: Bool = CiderConfig.load().tagsCollapsed
    @ObservedObject var labelStorage = CardLabelStorage.shared
    @State var focusedItemID: String?
    @State var selectionAnchorID: String?
    @State var scrollToItemID: String?
    @State var keyboardMonitor: Any?
    @State var aiSectionExpanded: Bool = false
    @AppStorage("cider.sidebarProfileExpanded") var sidebarProfileExpanded: Bool = true

    var allTabs: [CiderTab] {
        savedViewTabs + dynamicTabs
    }

    private var savedViewTabs: [CiderTab] {
        savedViewStorage.tabOrderedViews().map { savedView in
            .savedView(id: savedView.id, name: savedView.name)
        }
    }

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        panelBase
            .sheet(item: $newEventEditorContext) { context in
                eventEditorSheet(context: context)
            }
            .sheet(item: $newContactEditorContext) { context in
                contactEditorSheet(context: context)
            }
            .sheet(item: $newTodoEditorContext) { context in
                todoEditorSheet(context: context)
            }
            .background(keyboardShortcutBackground)
    }

    private var panelBase: some View {
        CiderPanelShell(
            isCollapsed: isCollapsed,
            suppressSidebarAutoExpand: isAnyDetailOpen,
            blurRightColumn: isDetailSlideOut || isGenericDetailSlideOut || isNoteDetailSlideOut || isKanbanDetailSlideOut,
            showsPanelControls: true,
            onClose: { closeSurface() },
            onCollapse: { minimizeSurface() },
            onMaximize: { maximizeSurface() }
        ) {
            folderSidebar
        } sidebarFooter: {
            sidebarFooterView
        } titleBar: {
            titleBarContent
        } content: {
            contentArea
        } overlay: {
            panelOverlay
        }
        .onDrop(
            of: Self.urlDropTypeIdentifiers,
            delegate: CiderPanelURLDropDelegate(
                isTargeted: $isURLDropTargeted,
                targetFolderID: selectedFolderID,
                onSaveDroppedURL: saveDroppedURL(_:folderID:)
            )
        )
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .animation(reduceMotion ? .none : .snappy, value: isDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isGenericDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isGenericDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isNoteDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isNoteDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isKanbanDetailSlideOut)
        .ciderCardEnvironment(textScale: textScale, hideFooters: hideCardFooters, detailsOnHover: showCardDetailsOnHover)
        .task { ensureDefaultTabs() }
        .onAppear {
            installKeyboardMonitor()
            updateLivePerformanceContext()
        }
        .onDisappear {
            CiderLivePerformanceRecorder.shared.flushSession(reason: "panel_disappear")
            removeKeyboardMonitor()
        }
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
            selectedTagIDs.removeAll()
            selectedItemIDs.removeAll()
            focusedItemID = nil
            selectionAnchorID = nil
            searchDebounceTask?.cancel()
            sidebarSearchText = ""
            debouncedSearchText = ""
            closeAllDetails()
            updateLivePerformanceContext()
        }
        .onChange(of: selectedFolderID) { _, newFolderID in
            selectedTagIDs.removeAll()
            selectedItemIDs.removeAll()
            focusedItemID = nil
            selectionAnchorID = nil
            searchDebounceTask?.cancel()
            sidebarSearchText = ""
            debouncedSearchText = ""
            closeAllDetails()
            if let folderContext = aiFolderContext(for: newFolderID) {
                AIAssistantViewModel.shared.updateContext(folder: folderContext)
            } else {
                AIAssistantViewModel.shared.clearContext()
            }
            updateLivePerformanceContext()
        }
        .onChange(of: tagsCollapsed) { _, newVal in
            var config = CiderConfig.load()
            config.tagsCollapsed = newVal
            config.save()
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
        .onChange(of: libraryViewModel.items.count) { _, _ in
            updateLivePerformanceContext()
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
            let config = CiderConfig.load()
            textScale = config.textSize.scale

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
        .onReceive(NotificationCenter.default.publisher(for: .openCiderSurfaceInMainWindow)) { notification in
            guard surface == .mainWindow,
                  let floatableSurface = CiderFloatingPanelManager.SurfaceNotificationPayload.surface(from: notification) else {
                return
            }
            openSurfaceInMainWindow(floatableSurface)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openNewItemPopover)) { notification in
            let ui = notification.userInfo
            let step = ui?["initialStep"] as? String

            // Screen capture routes bypass the +New popover and open full editor sheets
            if step == "event" {
                let title = ui?["suggestedTitle"] as? String ?? ""
                let date = (ui?["detectedDates"] as? [Date])?.first ?? Date()
                let ocrText = ui?["ocrText"] as? String ?? ""
                let location = ui?["suggestedLocation"] as? String ?? ""
                var card = DateCardStorage.shared.createDateCard(title: title, startAt: date, allDay: false)
                if !ocrText.isEmpty { card.details = ocrText }
                if !location.isEmpty { card.location = location }
                _ = DateCardStorage.shared.updateDateCard(card)
                newEventEditorContext = DateCardEditorContext(existingCard: card, defaultDate: date)
                return
            }
            if step == "contact" {
                let name = ui?["suggestedTitle"] as? String ?? ""
                let email = (ui?["detectedEmails"] as? [String])?.first ?? ""
                let phone = (ui?["detectedPhones"] as? [String])?.first ?? ""
                var contact = ContactStorage.shared.createContact(displayName: name)
                if !email.isEmpty { contact.email = email }
                if !phone.isEmpty { contact.phone = phone }
                _ = ContactStorage.shared.updateContact(contact)
                newContactEditorContext = ContactEditorContext(existingContact: contact)
                return
            }

            showNewItemPicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showOnboarding)) { _ in
            openOrCreateOnboardingTab()
        }
    }

    private func eventEditorSheet(context: DateCardEditorContext) -> AnyView {
        AnyView(DateCardEditorSheet(
            existingCard: context.existingCard,
            defaultDate: context.defaultDate,
            onSave: { title, details, startAt, endAt, allDay, location, amount, actionURLString, labelIDs, recurrenceRule, rules in
                LibraryItemEditor.saveDateCard(
                    existingCard: context.existingCard,
                    title: title,
                    details: details,
                    startAt: startAt,
                    endAt: endAt,
                    allDay: allDay,
                    location: location,
                        amount: amount,
                        actionURLString: actionURLString,
                        labelIDs: labelIDs,
                    recurrenceRule: recurrenceRule,
                    rules: rules
                )
            },
            onDelete: { dateCard in
                if let trashItem = DateCardStorage.shared.deleteDateCard(dateCard.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                }
            }
        ))
    }

    private func contactEditorSheet(context: ContactEditorContext) -> AnyView {
        AnyView(ContactEditorSheet(
            existingContact: context.existingContact,
            onSave: { draftContactID, displayName, relationshipLabel, birthday, notes, labelIDs, addBirthdayDateCard, email, phone, address, hasAvatar, customFields in
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
                    hasAvatar: hasAvatar,
                    customFields: customFields
                )
            },
            onDelete: { contact in
                if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                }
            }
        ))
    }

    private func todoEditorSheet(context: TodoEditorContext) -> AnyView {
        AnyView(TodoEditorSheet(
            existingCard: context.existingCard,
            onSave: { card in
                if context.existingCard != nil {
                    _ = TodoCardStorage.shared.updateTodoCard(card)
                } else {
                    var created = TodoCardStorage.shared.createTodoCard(
                        title: card.title,
                        dueDate: card.dueDate,
                        priority: card.priority
                    )
                    created.details = card.details
                    created.checklist = card.checklist
                    created.labelIDs = card.labelIDs
                    created.rules = card.rules
                    _ = TodoCardStorage.shared.updateTodoCard(created)
                }
            },
            onDelete: { todoCard in
                if let trashItem = TodoCardStorage.shared.deleteTodoCard(todoCard.id) {
                    CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
                }
            }
        ))
    }

    @ViewBuilder
    private var panelOverlay: some View {
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
                onOpenDateCard: { openDateCardDetail($0) },
                onOpenContact: { openContactDetail($0) },
                onOpenTodo: { openTodoDetail($0) },
                onSpawnSearchTab: spawnSearchTab,
                onDismiss: { isSearchPaletteVisible = false },
                onAction: { action in
                    handleQuickAction(action)
                },
                onSelectTag: { tag in
                    let filter = SavedViewFilterSpec(labelIDs: [tag.id])
                    let savedView = savedViewStorage.createSavedView(name: tag.name, filterSpec: filter)
                    savedViewStorage.addToTabOrder(savedView.id)
                    selectedFolderID = nil
                    selectedTab = .savedView(id: savedView.id, name: savedView.name)
                }
            )
        }

        if isDetailFullPanel {
            detailFullPanelOverlay
        }

        if isDetailSlideOut, detailsDraft != nil {
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
                .frame(width: isTodoDetailOpen ? BookmarksDesign.detailsSlideOutMinWidth : min(detailSlideOutWidth, maxSlideOutWidth))
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

        if isKanbanDetailSlideOut {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { closeKanbanDetail() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            kanbanDetailSlideOutContainer
                .frame(width: min(detailSlideOutWidth, maxSlideOutWidth))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(BookmarksDesign.detailsSlideOutFloatInset)
                .transition(.move(edge: .trailing).combined(with: .opacity))
        }

        if isURLDropTargeted {
            urlDropOverlay
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    @ViewBuilder
    private var keyboardShortcutBackground: some View {
        Button("") { isSearchPaletteVisible = true }
            .keyboardShortcut("k", modifiers: .command)
            .hidden()

        Button("") { selectAllVisibleItems() }
            .keyboardShortcut("a", modifiers: .command)
            .hidden()

        Button("") {
            // If a sheet is presented, let it handle Escape.
            if let keyWindow = NSApp.keyWindow, keyWindow.isSheet {
                keyWindow.close()
                return
            }
            if isEditingNoteTitle {
                isEditingNoteTitle = false
            } else if isSearchPaletteVisible {
                isSearchPaletteVisible = false
            } else if !sidebarSearchText.isEmpty {
                searchDebounceTask?.cancel()
                sidebarSearchText = ""
                debouncedSearchText = ""
            } else if isDetailOpen {
                closeBookmarkDetails()
            } else if isGenericDetailOpen {
                closeGenericDetail()
            } else if isNoteDetailOpen {
                closeNoteDetail()
            } else if isKanbanDetailOpen {
                closeKanbanDetail()
            } else if !selectedItemIDs.isEmpty || focusedItemID != nil {
                withAnimation(reduceMotion ? .none : .snappy) {
                    selectedItemIDs.removeAll()
                }
                focusedItemID = nil
                selectionAnchorID = nil
            }
        }
        .keyboardShortcut(.escape, modifiers: [])
        .hidden()
    }

    private func aiFolderContext(for folderID: UUID?) -> (name: String, directItemCount: Int, childFolderCount: Int)? {
        guard let folderID,
              let folder = VaultFolderService.shared.folder(for: folderID) else {
            return nil
        }

        let bookmarkCount = VaultBookmarkService.shared.bookmarks.filter { $0.folderID == folderID }.count
        let noteCount = NotesStorage.shared.notes.filter { $0.folderID == folderID }.count
        let todoCount = TodoCardStorage.shared.todoCards.filter { $0.folderID == folderID }.count
        let eventCount = DateCardStorage.shared.dateCards.filter { $0.folderID == folderID }.count
        let contactCount = ContactStorage.shared.contacts.filter { $0.folderID == folderID }.count
        let fileCount = VaultFileService.shared.files.filter { $0.folderID == folderID }.count
        let directItemCount = bookmarkCount + noteCount + todoCount + eventCount + contactCount + fileCount
        let childFolderCount = VaultFolderService.shared.folders.filter {
            $0.parentRelativePath == folder.relativePath
        }.count

        return (
            name: folder.name,
            directItemCount: directItemCount,
            childFolderCount: childFolderCount
        )
    }
}
