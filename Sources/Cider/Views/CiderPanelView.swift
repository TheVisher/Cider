import SwiftUI
import AppKit
import WebKit

struct CiderPanelView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel
    @ObservedObject var savedViewStorage = SavedViewStorage.shared
    @ObservedObject var externalSourceStorage = ExternalSourceStorage.shared
    @StateObject var libraryViewModel = LibraryViewModel()
    @StateObject var whiteboardViewModel = WhiteboardViewModel()
    @State var selectedTab: CiderTab?
    @State var isCollapsed = false
    @State var selectedFolderID: UUID?
    @State var selectedSourceID: UUID?
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
    @StateObject var detailWebViewStore = DetailWebViewStore()
    @State var detailWidthSaveTask: Task<Void, Never>?
    @State var selectedDateCard: DateCard?
    @State var selectedContact: ContactCard?
    @State var selectedTodoCard: TodoCard?
    @State var selectedVaultFile: VaultFile?
    @State var selectedSession: BrowserSession?
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
    @State var enableLinkedSources: Bool = CiderConfig.load().enableLinkedSources
    @State var selectedTagIDs: Set<UUID> = []
    @State var tagsCollapsed: Bool = CiderConfig.load().tagsCollapsed
    @ObservedObject var labelStorage = CardLabelStorage.shared
    @State var focusedItemID: String?
    @State var selectionAnchorID: String?
    @State var scrollToItemID: String?
    @State var keyboardMonitor: Any?

    var allTabs: [CiderTab] {
        savedViewTabs + sourceTabs + dynamicTabs
    }

    private var sourceTabs: [CiderTab] {
        guard enableLinkedSources else { return [] }
        return externalSourceStorage.pinnedSources().map {
            .externalSource(id: $0.id, name: $0.displayName)
        }
    }

    private var savedViewTabs: [CiderTab] {
        savedViewStorage.tabOrderedViews().map { savedView in
            .savedView(id: savedView.id, name: savedView.name)
        }
    }

    @Environment(\.accessibilityReduceMotion) var reduceMotion

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
        }
        .animation(reduceMotion ? .none : .snappy, value: isSearchPaletteVisible)
        .animation(reduceMotion ? .none : .snappy, value: isDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isGenericDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isGenericDetailSlideOut)
        .animation(reduceMotion ? .none : .snappy, value: isNoteDetailFullPanel)
        .animation(reduceMotion ? .none : .snappy, value: isNoteDetailSlideOut)
        .ciderCardEnvironment(textScale: textScale, hideFooters: hideCardFooters, detailsOnHover: showCardDetailsOnHover)
        .task { ensureDefaultTabs() }
        .onAppear { installKeyboardMonitor() }
        .onDisappear { removeKeyboardMonitor() }
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
            // Flush any pending whiteboard save before switching
            whiteboardViewModel.flushSave()
            selectedFolderID = nil
            selectedSourceID = nil
            selectedTagIDs.removeAll()
            selectedItemIDs.removeAll()
            focusedItemID = nil
            selectionAnchorID = nil
            searchDebounceTask?.cancel()
            sidebarSearchText = ""
            debouncedSearchText = ""
            closeAllDetails()
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
            // Update AI context with folder info
            if let fid = newFolderID,
               let folder = VaultFolderService.shared.folder(for: fid) {
                let itemCount = BookmarksStorage.shared.bookmarks.filter { $0.folderID == fid }.count
                    + NotesStorage.shared.notes.filter { $0.folderID == fid }.count
                AIAssistantViewModel.shared.updateContext(
                    folder: (name: folder.name, itemCount: itemCount)
                )
            } else {
                AIAssistantViewModel.shared.clearContext()
            }
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
            enableLinkedSources = config.enableLinkedSources
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
        .sheet(item: $newEventEditorContext) { context in
            DateCardEditorSheet(
                existingCard: context.existingCard,
                defaultDate: context.defaultDate,
                onSave: { title, details, startAt, endAt, allDay, location, amount, labelIDs, recurrenceRule, rules in
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
                        recurrenceRule: recurrenceRule,
                        rules: rules
                    )
                },
                onDelete: { dateCard in
                    if let trashItem = DateCardStorage.shared.deleteDateCard(dateCard.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .dateCard, trashItem: trashItem))
                    }
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
                    if let trashItem = ContactStorage.shared.deleteContact(contact.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .contact, trashItem: trashItem))
                    }
                }
            )
        }
        .sheet(item: $newTodoEditorContext) { context in
            TodoEditorSheet(
                existingCard: context.existingCard,
                onSave: { card in
                    if context.existingCard != nil {
                        _ = TodoCardStorage.shared.updateTodoCard(card)
                    } else {
                        // New card — create via storage so it gets a fresh ID and timestamps
                        var created = TodoCardStorage.shared.createTodoCard(
                            title: card.title,
                            dueDate: card.dueDate,
                            priority: card.priority
                        )
                        created.details = card.details
                        created.checklist = card.checklist
                        created.labelIDs = card.labelIDs
                        _ = TodoCardStorage.shared.updateTodoCard(created)
                    }
                },
                onDelete: { todoCard in
                    if let trashItem = TodoCardStorage.shared.deleteTodoCard(todoCard.id) {
                        CiderUndoManager.shared.record(.deletedToTrash(itemType: .todo, trashItem: trashItem))
                    }
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
    }
}
