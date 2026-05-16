import SwiftUI

extension CiderPanelView {

    // MARK: - Content Area

    var isEditorActive: Bool {
        selectedNote != nil
    }

    var isNoteDetailOpen: Bool { isEditorActive }
    var isNoteDetailSlideOut: Bool { isNoteDetailOpen && noteDetailViewMode == .slideOut }
    var isNoteDetailFullPanel: Bool { isNoteDetailOpen && noteDetailViewMode == .fullPanel }
    var isNoteDetailPageMode: Bool { isNoteDetailOpen && noteDetailViewMode == .page }

    /// Active detail view mode based on what's currently open
    var detailViewMode: DetailViewMode {
        if isNoteDetailOpen { return noteDetailViewMode }
        return bookmarkDetailViewMode
    }

    var contentArea: some View {
        VStack(spacing: 0) {
            ZStack {
                tabContentBody
                    .opacity(isAnyDetailPageMode ? 0 : 1)
                    .allowsHitTesting(!isAnyDetailPageMode)

                if isAnyDetailPageMode {
                    detailPageView
                }
            }

        }
        .animation(reduceMotion ? .none : .snappy, value: isAnyDetailOpen)
        .clipShape(RoundedRectangle(cornerRadius: CiderPanelDesign.cornerRadius, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        contentAreaWidth = proxy.size.width
                        CiderLivePerformanceRecorder.shared.recordFrame(
                            event: .layoutWidth,
                            windowSize: CGSize(width: proxy.size.width, height: proxy.size.height)
                        )
                    }
                    .onChange(of: proxy.size.width) { _, w in
                        contentAreaWidth = w
                        CiderLivePerformanceRecorder.shared.recordFrame(
                            event: .layoutWidth,
                            windowSize: CGSize(width: w, height: proxy.size.height)
                        )
                    }
            }
        )
    }

    @ViewBuilder
    var tabContentBody: some View {
        if !selectedTagIDs.isEmpty {
            TagDetailView(
                tagIDs: selectedTagIDs,
                showManager: false,
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                libraryViewModel: libraryViewModel,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale,
                selectedItemIDs: $selectedItemIDs,
                onOpenNote: { note in openNoteDetail(note) },
                onShowBookmarkDetails: { openBookmarkDetails($0) },
                onEditDateCard: { dateCard in
                    newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                },
                onEditContact: { contact in
                    newContactEditorContext = ContactEditorContext(existingContact: contact)
                },
                onOpenDateCard: { openDateCardDetail($0) },
                onOpenContact: { openContactDetail($0) },
                onOpenTodo: { openTodoDetail($0) },
                onOpenVaultFile: { openVaultFileDetail($0) },

                onSelectTag: { id in
                    selectedTagIDs = [id]
                },
                onBack: {
                    selectedTagIDs.removeAll()
                },
                onToggleLabelBulk: { toggleTagOnSelected($0) },
                scrollToItemID: $scrollToItemID,
                focusedItemID: focusedItemID
            )
        } else if let folderID = selectedFolderID {
                FolderDetailView(
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    folderID: folderID,
                    navigationDomain: selectedNavigationDomain,
                    contentScope: $folderContentScope,
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
                onOpenContact: { openContactDetail($0) },
                onOpenTodo: { openTodoDetail($0) },
                onOpenVaultFile: { openVaultFileDetail($0) },

                onToggleLabelBulk: { toggleTagOnSelected($0) },
                scrollToItemID: $scrollToItemID,
                focusedItemID: focusedItemID
            )
        } else if selectedDomainRouteKind == .folders,
                  let selectedNavigationDomain {
            FolderBrowserView(
                folders: contextualFolders,
                bookmarks: bookmarksViewModel.bookmarks,
                notes: notesViewModel.notes,
                navigationDomain: selectedNavigationDomain,
                searchText: debouncedSearchText,
                onSelectFolder: { folderID in
                    selectedFolderID = folderID
                    expandPathToFolder(folderID)
                }
            )
        } else if let tab = selectedTab {
            switch tab {
            case .domainDashboard(let domain):
                if domain == .projects {
                    ProjectWorkspaceOverviewView(
                        model: ProjectWorkspaceOverviewProvider.model(
                            for: projectWorkspaceCatalog.home,
                            catalog: projectWorkspaceCatalog,
                            boards: kanbanStorage.boards
                        ),
                        onOpenProject: { row in
                            if let project = projectWorkspaceCatalog.workspace(id: row.projectID) {
                                selectProjectWorkspace(project)
                            }
                        },
                        onOpenBoard: { boardID in
                            openProjectBoard(boardID)
                        },
                        onCreateBoard: {
                        }
                    )
                } else {
                    WorkspaceDomainDashboardView(
                        model: WorkspaceDomainDashboardProvider.model(
                            for: domain,
                            savedViews: savedViewStorage.savedViews,
                            allTabs: allTabs,
                            bookmarks: bookmarksViewModel.bookmarks,
                            bookmarkFolders: bookmarksViewModel.folders
                        ),
                        onOpenTab: { tab in
                            openDomainDashboardTab(tab)
                        },
                        onBrowseAll: {
                            openNavigationDomain(.browse)
                        }
                    )
                }
            case .projectOverview(let projectID, _):
                if let project = projectWorkspaceCatalog.workspace(id: projectID) {
                    ProjectWorkspaceOverviewView(
                        model: ProjectWorkspaceOverviewProvider.model(
                            for: project,
                            catalog: projectWorkspaceCatalog,
                            boards: kanbanStorage.boards
                        ),
                        onOpenProject: { _ in },
                        onOpenBoard: { boardID in
                            openProjectBoard(boardID)
                        },
                        onCreateBoard: {
                            createProjectBoard(in: project)
                        }
                    )
                } else {
                    EmptyStateView(
                        icon: "rectangle.3.group",
                        title: "Project not found"
                    )
                }
            case .projectReferences(let projectID, _):
                if let project = projectWorkspaceCatalog.workspace(id: projectID) {
                    ProjectReferencesView(
                        project: project,
                        references: ProjectReferenceProvider.references(
                            for: project,
                            items: libraryViewModel.items,
                            boards: kanbanStorage.boards
                        ),
                        boards: kanbanStorage.boards,
                        onOpenItem: { item in
                            openDashboardItem(item)
                        },
                        onOpenCard: { boardID, cardID in
                            openKanbanCardDetail(boardID: boardID, cardID: cardID)
                        },
                        onLinkReferenceToCard: { ref, boardID, cardID in
                            linkProjectReference(ref, toCardID: cardID, boardID: boardID)
                        },
                        onPromoteReference: { reference in
                            promoteProjectReference(reference, in: project)
                        }
                    )
                } else {
                    EmptyStateView(
                        icon: "photo.on.rectangle",
                        title: "Project references not found"
                    )
                }
            case .spaceOverview(let spaceID, _):
                if let space = spaceStorage.space(id: spaceID) {
                    let captureDashboard = try? CiderSpaceCaptureDashboardService().dashboard(for: space)
                    CiderSpaceOverviewView(
                        space: space,
                        rootURL: spaceStorage.rootURL(for: space),
                        captureDashboard: captureDashboard,
                        bookmarks: bookmarksViewModel.bookmarks,
                        mediaItems: mediaItemStorage.items,
                        notes: notesViewModel.notes,
                        onTogglePinned: {
                            togglePinnedSpace(space)
                        },
                        onOpenBookmark: { bookmark in
                            openBookmarkDetails(bookmark)
                        },
                        onOpenNote: { note in
                            openNoteDetail(note)
                        }
                    )
                } else {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "Space not found"
                    )
                }
            case .spacesManager:
                CiderSpacesManagerView(
                    spaces: spaceStorage.spaces,
                    loadIssues: spaceStorage.loadIssues,
                    onCreateSpace: createSpace,
                    onOpenSpace: openSpace
                )
            case .aiAssistant:
                AIAssistantPanelView(
                    viewModel: AIAssistantViewModel.shared,
                    onClose: { closeTab(.aiAssistant) },
                    onFloat: {
                        requestFloat(.aiAssistant)
                    },
                    showsResizeOverlay: false,
                    presentationStyle: .embedded
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .savedView(let id, _):
                if let savedView = savedViewStorage.savedView(for: id) {
                    if case .kanban(let boardID) = savedView.kind {
                        KanbanBoardView(boardID: boardID, onOpenCard: openKanbanCardDetail)
                    } else if case .dashboard = savedView.kind {
                        let reviewQueueService = CiderReviewQueueService()
                        let reviewQueueItems = (try? reviewQueueService.list(limit: 8).items) ?? []
                        let reviewQueueSummary = try? reviewQueueService.summary()
                        let bookmarkDateSuggestionResults = HomeOverviewDataProvider.bookmarkDateSuggestionResults(
                            from: libraryViewModel.items
                        )
                        DashboardHubView(showsTopicSwitcher: false, onOpenSourceURL: { url in
                            openURLSafely(url)
                        }) {
                            HomeOverviewDashboardView(
                                snapshot: HomeOverviewDataProvider.makeSnapshot(
                                    items: libraryViewModel.items,
                                    recentItems: libraryViewModel.recentItems,
                                    folders: bookmarksViewModel.folders,
                                    savedViews: savedViewStorage.savedViews,
                                    tabOrder: savedViewStorage.tabOrder,
                                    kanbanBoards: kanbanStorage.boards,
                                    reviewQueueItems: reviewQueueItems,
                                    reviewQueueSummary: reviewQueueSummary,
                                    bookmarkDateSuggestionResults: bookmarkDateSuggestionResults,
                                    surfacingDays: CiderConfig.load().dateCardSurfacingDays
                                ),
                                onOpenItem: { item in openDashboardItem(item) },
                                onOpenTarget: { target in openDashboardTarget(target) },
                                onOpenTab: { tab in openDashboardTab(tab) },
                                onOpenKanbanCard: { boardID, cardID in
                                    selectedKanbanBoardID = boardID
                                    selectedKanbanCardID = cardID
                                },
                                onApproveReview: { reviewItem in
                                    do {
                                        if let approval = reviewItem.dateSuggestionApproval {
                                            _ = try CiderBookmarkDateSuggestionApprovalService().approve(
                                                bookmarkID: approval.bookmarkID,
                                                suggestionKey: approval.suggestionKey
                                            )
                                        } else {
                                            try CiderReviewQueueService().approve(itemID: reviewItem.itemID, actor: "user")
                                        }
                                        return true
                                    } catch {
                                        print("Dashboard review approve failed: \(error.localizedDescription)")
                                        return false
                                    }
                                },
                                onDeferReview: { reviewItem in
                                    do {
                                        try CiderReviewQueueService().deferReview(
                                            itemID: reviewItem.itemID,
                                            reason: "Deferred from Dashboard review cockpit.",
                                            actor: "user"
                                        )
                                        return true
                                    } catch {
                                        print("Dashboard review defer failed: \(error.localizedDescription)")
                                        return false
                                    }
                                },
                                onOpenSettings: {
                                    NotificationCenter.default.post(name: .openCiderSettings, object: nil)
                                },
                                onSyncNow: {
                                    SyncService.shared.syncNow()
                                },
                                onCreateNew: {
                                    showNewItemPicker = true
                                }
                            )
                        }
                    } else if savedView.isOnboarding {
                        OnboardingTabView(onDismiss: {
                            dismissOnboardingTab(id: id)
                        })
                    } else if savedView.isBlank {
                        blankTabWelcome(savedViewID: id)
                    } else {
                        HomeDashboardView(
                            bookmarksViewModel: bookmarksViewModel,
                            notesViewModel: notesViewModel,
                            libraryViewModel: libraryViewModel,
                            selectedFolderID: nil,
                            displayMode: $homeDisplayMode,
                            cardSizeScale: $homeCardSizeScale,
                            continueSectionCollapsed: .constant(true),
                            selectedItemIDs: $selectedItemIDs,
                            sortMode: sortModeBinding(for: id),
                            entityFilter: entityFilterBinding(for: id),
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
                            onOpenContact: { openContactDetail($0) },
                            onOpenTodo: { openTodoDetail($0) },
                            onOpenVaultFile: { openVaultFileDetail($0) },
            
                            onlyUnassigned: savedView.filterSpec.onlyUnassigned,
                            activeLabelIDs: savedView.filterSpec.labelIDs,
                            maxVisibleItems: libraryFeedMaxVisibleItems(for: savedView),
                            onToggleLabelBulk: { toggleTagOnSelected($0) },
                            showComingUp: savedView.layoutSpec.showComingUpSection,
                            scrollToItemID: $scrollToItemID,
                            focusedItemID: focusedItemID
                        )
                    }
                } else {
                    EmptyStateView(
                        icon: "square.grid.2x2",
                        title: "Saved view not found"
                    )
                }
            case .search(let searchID, let query):
                HomeDashboardView(
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    libraryViewModel: libraryViewModel,
                    selectedFolderID: nil,
                    displayMode: $homeDisplayMode,
                    cardSizeScale: $homeCardSizeScale,
                    continueSectionCollapsed: .constant(true),
                    selectedItemIDs: $selectedItemIDs,
                    sortMode: sortModeBinding(for: searchID),
                    entityFilter: entityFilterBinding(for: searchID),
                    searchText: query,
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
                    onOpenContact: { openContactDetail($0) },
                    onOpenTodo: { openTodoDetail($0) },
                    onOpenVaultFile: { openVaultFileDetail($0) },
    
                    onToggleLabelBulk: { toggleTagOnSelected($0) },
                    scrollToItemID: $scrollToItemID,
                    focusedItemID: focusedItemID
                )
            case .tag:
                TagDetailView(
                    tagIDs: [],
                    showManager: true,
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    libraryViewModel: libraryViewModel,
                    displayMode: $homeDisplayMode,
                    cardSizeScale: $homeCardSizeScale,
                    selectedItemIDs: $selectedItemIDs,
                    onOpenNote: { note in openNoteDetail(note) },
                    onShowBookmarkDetails: { openBookmarkDetails($0) },
                    onEditDateCard: { dateCard in
                        newEventEditorContext = DateCardEditorContext(existingCard: dateCard, defaultDate: dateCard.startAt)
                    },
                    onEditContact: { contact in
                        newContactEditorContext = ContactEditorContext(existingContact: contact)
                    },
                    onOpenDateCard: { openDateCardDetail($0) },
                    onOpenContact: { openContactDetail($0) },
                    onOpenTodo: { openTodoDetail($0) },
                    onOpenVaultFile: { openVaultFileDetail($0) },
    
                    onSelectTag: { id in
                        selectedTagIDs = [id]
                    },
                    onToggleLabelBulk: { toggleTagOnSelected($0) },
                    scrollToItemID: $scrollToItemID,
                    focusedItemID: focusedItemID
                )
            }
        } else {
            if let domain = selectedNavigationDomain {
                WorkspaceDomainDashboardView(
                    model: WorkspaceDomainDashboardProvider.model(
                        for: domain,
                        savedViews: savedViewStorage.savedViews,
                        allTabs: allTabs,
                        bookmarks: bookmarksViewModel.bookmarks,
                        bookmarkFolders: bookmarksViewModel.folders
                    ),
                    onOpenTab: { tab in
                        openDomainDashboardTab(tab)
                    },
                    onBrowseAll: {
                        openNavigationDomain(.browse)
                    }
                )
            } else {
                noTabsEmptyState
            }
        }
    }

    @ViewBuilder
    func blankTabWelcome(savedViewID: UUID) -> some View {
        let closed = savedViewStorage.savedViews.filter {
            !savedViewStorage.tabOrder.contains($0.id) && !$0.isOnboarding
        }

        VStack(spacing: Spacing.xl) {
            Spacer()

            Image(systemName: "square.grid.2x2.fill")
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)

            VStack(spacing: Spacing.sm) {
                Text("New Tab")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)

                Text("Configure this tab to show exactly what you need.")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }

            VStack(alignment: .leading, spacing: Spacing.md) {
                blankTabHint(icon: "line.3.horizontal.decrease.circle", text: "Filter by bookmarks, notes, events, or contacts")
                blankTabHint(icon: "arrow.up.arrow.down", text: "Sort by date added, modified, title, or event date")
                blankTabHint(icon: "tray", text: "Toggle \"Unassigned Only\" to create an inbox")
                blankTabHint(icon: "square.grid.2x2", text: "Switch between list, grid, and masonry layouts")
                blankTabHint(icon: "textformat.size", text: "Adjust card size with the slider")
            }

            Button("Open View Options") {
                isHomeViewOptionsVisible = true
            }
            .buttonStyle(CiderAccentButtonStyle())

            Button("Show All Items") {
                activateBlankTab(savedViewID)
            }
            .buttonStyle(.plain)
            .font(CiderFont.labelMedium)
            .foregroundColor(CiderColors.controlAccent)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            closedTabsGrid(closed)
        }
    }

    @ViewBuilder
    private func closedTabsGrid(_ closed: [SavedView]) -> some View {
        VStack(spacing: Spacing.sm) {
            Divider()
                .padding(.horizontal, Spacing.lg)

            Text("Closed Tabs")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            if closed.isEmpty {
                Text("Closed tabs appear here")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(minHeight: 32)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 100, maximum: 160), spacing: Spacing.sm)],
                    spacing: Spacing.sm
                ) {
                    ForEach(closed) { sv in
                        ClosedTabCard(
                            savedView: sv,
                            onReopen: { reopenTab(sv.id) },
                            onDelete: { deleteClosedTab(sv) }
                        )
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
        .padding(.bottom, Spacing.md)
    }

    private func blankTabHint(icon: String, text: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 20, alignment: .center)
            Text(text)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
        }
    }

    func activateBlankTab(_ savedViewID: UUID) {
        guard var savedView = savedViewStorage.savedView(for: savedViewID) else { return }
        savedView.isBlank = false
        savedViewStorage.updateSavedView(savedView)
    }

    func dismissOnboardingTab(id: UUID) {
        savedViewStorage.removeFromTabOrder(id)
        savedViewStorage.deleteSavedView(id)
        var config = CiderConfig.load()
        config.hasCompletedOnboarding = true
        config.save()
        selectedTab = allTabs.first
    }

    func openOrCreateOnboardingTab() {
        // Check if an onboarding tab already exists in the tab bar
        if let existing = savedViewStorage.savedViews.first(where: { $0.isOnboarding }),
           savedViewStorage.tabOrder.contains(existing.id) {
            selectedTab = .savedView(id: existing.id, name: existing.name)
            selectedFolderID = nil
            return
        }
        // Create a new onboarding tab at the front
        let welcome = savedViewStorage.createSavedView(
            name: "Welcome",
            filterSpec: SavedViewFilterSpec(),
            isBlank: true,
            isOnboarding: true
        )
        savedViewStorage.insertInTabOrder(welcome.id, at: 0)
        selectedTab = .savedView(id: welcome.id, name: welcome.name)
        selectedFolderID = nil
    }

    // MARK: - noTabsEmptyState

    var noTabsEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(CiderFont.emptyStateIconLarge)
                .foregroundColor(CiderColors.tertiary)
            Text("No tabs open")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)
            Text("Create a tab to start organizing")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
            Button("New Tab") { showNewItemPicker = true }
                .buttonStyle(CiderAccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func openDashboardItem(_ item: LibraryItemV2) {
        switch item {
        case .bookmark(let bookmark):
            openBookmarkDetails(bookmark)
        case .note(let note):
            openNoteDetail(note)
        case .dateCard(let dateCard):
            openDateCardDetail(dateCard)
        case .contact(let contact):
            openContactDetail(contact)
        case .todo(let todoCard):
            openTodoDetail(todoCard)
        case .vaultFile(let file):
            openVaultFileDetail(file)
        }
    }

    func libraryFeedMaxVisibleItems(for savedView: SavedView) -> Int? {
        guard selectedNavigationDomain == .browse,
              selectedDomainRouteKind == .inbox,
              savedView.kind == .library,
              savedView.filterSpec.onlyUnassigned
        else { return nil }
        return LibraryInboxPresentationPolicy.maxVisibleItems
    }

    func openDashboardTab(_ tab: HomeOverviewClosedTabSummary) {
        reopenTab(tab.id)
    }

    func openDashboardTarget(_ target: HomeOverviewActionTarget) {
        switch target {
        case .inbox:
            if let inbox = savedViewStorage.savedViews.first(where: {
                $0.kind == .library && $0.filterSpec.onlyUnassigned
            }) {
                selectedFolderID = nil
                selectedTab = .savedView(id: inbox.id, name: inbox.name)
            } else {
                let inbox = savedViewStorage.createSavedView(
                    name: "Inbox",
                    filterSpec: SavedViewFilterSpec(onlyUnassigned: true)
                )
                selectedFolderID = nil
                selectedTab = .savedView(id: inbox.id, name: inbox.name)
            }
        case .savedView(let name, let filterSpec, let sortMode):
            openDashboardLibraryView(named: name, filterSpec: filterSpec, sortMode: sortMode)
        }
    }

    func openProjectBoard(_ boardID: String) {
        guard let board = kanbanStorage.boards.first(where: { $0.id == boardID }) else { return }
        let savedView = savedViewStorage.ensureKanbanView(name: board.name, boardID: board.id)
        selectedFolderID = nil
        selectedTab = .savedView(id: savedView.id, name: savedView.name)
    }

    func createProjectBoard(in project: ProjectWorkspace) {
        let board = kanbanStorage.createBoard(name: "Untitled Board")
        let savedView = ProjectBoardRegistrationService.register(
            board: board,
            projectID: project.id,
            savedViewStorage: savedViewStorage,
            associationStore: projectAssociationStore
        )
        selectedProjectWorkspaceID = project.id
        selectedFolderID = nil
        selectedTab = .savedView(id: savedView.id, name: savedView.name)
    }

    func linkProjectReference(_ ref: LibraryEntityRef, toCardID cardID: String, boardID: String) {
        guard let found = KanbanStorage.shared.findCard(id: cardID),
              found.board.id == boardID,
              !found.card.linkedEntities.contains(ref) else {
            return
        }
        var updated = found.card
        updated.linkedEntities.append(ref)
        KanbanStorage.shared.updateCard(boardID: boardID, card: updated)
    }

    func promoteProjectReference(_ reference: ProjectReferenceItem, in project: ProjectWorkspace) {
        guard let board = project.boardIDs.compactMap({ boardID in
            kanbanStorage.boards.first { $0.id == boardID }
        }).first,
              let columnID = preferredProjectWorkColumnID(in: board) else {
            return
        }
        let title = "Follow up: \(reference.item.title)"
        let notes = """
        Created from \(project.title) References.

        Linked reference: \(reference.ref.type.rawValue) \(reference.ref.entityID.uuidString)
        """
        guard var card = KanbanStorage.shared.addCard(
            boardID: board.id,
            columnID: columnID,
            title: title,
            notes: notes,
            tags: [project.id, "references"]
        ) else { return }
        card.linkedEntities = [reference.ref]
        KanbanStorage.shared.updateCard(boardID: board.id, card: card)
        openKanbanCardDetail(boardID: board.id, cardID: card.id)
    }

    private func preferredProjectWorkColumnID(in board: KanbanBoard) -> String? {
        if let queued = board.columns.first(where: { $0.name.localizedCaseInsensitiveContains("queued") }) {
            return queued.id
        }
        if let backlog = board.columns.first(where: { $0.name.localizedCaseInsensitiveContains("backlog") }) {
            return backlog.id
        }
        return board.columns.first?.id
    }

    private func openDashboardLibraryView(
        named name: String,
        filterSpec: SavedViewFilterSpec,
        sortMode: LibrarySortMode = .createdDescending
    ) {
        if let existing = savedViewStorage.savedViews.first(where: {
            $0.kind == .library && $0.name == name && $0.filterSpec == filterSpec
        }) {
            selectedFolderID = nil
            selectedTab = .savedView(id: existing.id, name: existing.name)
            return
        }

        let savedView = savedViewStorage.createSavedView(
            name: name,
            filterSpec: filterSpec,
            sortSpec: SavedViewSortSpec(mode: sortMode)
        )
        selectedFolderID = nil
        selectedTab = .savedView(id: savedView.id, name: savedView.name)
    }
}

// MARK: - ClosedTabCard

private struct ClosedTabCard: View {
    let savedView: SavedView
    let onReopen: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var icon: String {
        if case .kanban = savedView.kind { return "square.split.2x1" }
        return "square.grid.2x2"
    }

    var body: some View {
        Button(action: onReopen) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(isHovered ? CiderColors.primary : CiderColors.tertiary)
                Text(savedView.name)
                    .font(CiderFont.label)
                    .foregroundColor(isHovered ? CiderColors.primary : CiderColors.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isHovered {
                    Spacer(minLength: 0)
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.destructive)
                            .padding(Spacing.xxs)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(0.8)))
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isHovered ? CiderColors.separatorLight : CiderColors.surfaceInput)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
    }
}
