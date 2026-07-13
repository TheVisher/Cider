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
                onOpenJournal: { openJournalDetail() },

                onSelectTag: { id in
                    navigateToWorkspaceRoute(.library(.tag(id)))
                },
                onBack: {
                    navigateToWorkspaceRoute(.library(.tags))
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
        } else if let libraryRouteFeed = selectedLibraryRouteFeed {
            HomeDashboardView(
                bookmarksViewModel: bookmarksViewModel,
                notesViewModel: notesViewModel,
                libraryViewModel: libraryViewModel,
                selectedFolderID: nil,
                displayMode: $homeDisplayMode,
                cardSizeScale: $homeCardSizeScale,
                continueSectionCollapsed: .constant(true),
                selectedItemIDs: $selectedItemIDs,
                sortMode: $homeSort,
                entityFilter: .constant(libraryRouteFeed.entityTypes),
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
                onOpenJournal: { openJournalDetail() },
                onlyUnassigned: libraryRouteFeed.onlyUnassigned,
                onToggleLabelBulk: { toggleTagOnSelected($0) },
                showComingUp: LibraryFeedPresentationPolicy.showsComingUpSection(on: .library),
                scrollToItemID: $scrollToItemID,
                focusedItemID: focusedItemID
            )
        } else if let standaloneDomain = selectedStandaloneDomainDashboard {
            WorkspaceDomainDashboardView(
                model: WorkspaceDomainDashboardProvider.model(
                    for: standaloneDomain,
                    bookmarks: bookmarksViewModel.bookmarks,
                    bookmarkFolders: bookmarksViewModel.folders
                ),
                onBrowseAll: {
                    openNavigationDomain(.browse)
                }
            )
        } else {
            switch WorkspaceRoutePresentation.presentation(for: workspaceRouter.currentRoute).contentKind {
            case .home:
                homeOverviewDashboard
            case .reviewQueue:
                reviewQueueDashboard
            case .libraryDashboard:
                WorkspaceDomainDashboardView(
                    model: WorkspaceDomainDashboardProvider.model(
                        for: .browse,
                        bookmarks: bookmarksViewModel.bookmarks,
                        bookmarkFolders: bookmarksViewModel.folders
                    ),
                    onBrowseAll: {
                        openNavigationDomain(.browse)
                    }
                )
            case .libraryFeed:
                emptyRouteState
            case .folder:
                if let selectedNavigationDomain {
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
                } else {
                    emptyRouteState
                }
            case .projectsHome:
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
                    onOpenMilestoneBoard: { milestone in
                        openProjectBoard(milestone.boardID, milestoneCardID: milestone.cardID)
                    },
                    onOpenMilestoneArtifact: { link in
                        openMilestoneArtifact(link)
                    },
                    onCreateBoard: {
                    }
                )
            case .projectOverview(let projectID):
                if let project = projectWorkspaceCatalog.workspace(id: projectID) {
                    projectWorkspaceContent(for: project, selectedKind: .overview) {
                        ProjectWorkspaceOverviewView(
                            model: ProjectWorkspaceOverviewProvider.model(
                                for: project,
                                catalog: projectWorkspaceCatalog,
                                boards: kanbanStorage.boards,
                                artifactRelations: projectArtifactRelations(for: project)
                            ),
                            onOpenProject: { _ in },
                            onOpenBoard: { boardID in
                                openProjectBoard(boardID)
                            },
                            onOpenMilestoneBoard: { milestone in
                                openProjectBoard(milestone.boardID, milestoneCardID: milestone.cardID)
                            },
                            onOpenMilestoneArtifact: { link in
                                openMilestoneArtifact(link)
                            },
                            onCreateBoard: {
                                createProjectBoard(in: project)
                            }
                        )
                    }
                } else {
                    EmptyStateView(
                        icon: "rectangle.3.group",
                        title: "Project not found"
                    )
                }
            case .projectInbox(let projectID):
                if let project = projectWorkspaceCatalog.workspace(id: projectID) {
                    projectWorkspaceContent(for: project, selectedKind: .inbox) {
                        ProjectWorkspaceInboxView(
                            workspace: project,
                            entries: ProjectWorkspaceInboxProvider.entries(
                                for: project,
                                boards: kanbanStorage.boards
                            ),
                            onOpenCard: { boardID, cardID in
                                kanbanStorage.markCardReviewed(boardID: boardID, cardID: cardID)
                                openKanbanCardDetail(boardID: boardID, cardID: cardID)
                            },
                            onMarkReviewed: { boardID, cardID in
                                kanbanStorage.markCardReviewed(boardID: boardID, cardID: cardID)
                            }
                        )
                    }
                } else {
                    EmptyStateView(
                        icon: "tray",
                        title: "Project Inbox not found"
                    )
                }
            case .projectBoard(let boardID, _):
                if let project = selectedProjectWorkspace,
                   kanbanStorage.boards.contains(where: { $0.id == boardID }) {
                    projectWorkspaceContent(for: project, selectedKind: .board(boardID)) {
                        KanbanBoardView(
                            boardID: boardID,
                            milestoneFilterCardID: kanbanMilestoneFilterByBoardID[boardID],
                            onOpenCard: openKanbanCardDetail
                        )
                    }
                } else {
                    EmptyStateView(
                        icon: "rectangle.split.3x1",
                        title: "Project board not found"
                    )
                }
            case .projectSurface(let projectID, let surface):
                if let project = projectWorkspaceCatalog.workspace(id: projectID) {
                    projectWorkspaceContent(for: project, selectedKind: .surface(surface)) {
                        if surface == .milestones {
                            ProjectWorkspaceMilestonesView(
                                workspace: project,
                                milestones: ProjectWorkspaceOverviewProvider.milestoneRows(
                                    for: project,
                                    boards: kanbanStorage.boards,
                                    artifactRelations: projectArtifactRelations(for: project)
                                ),
                                onOpenMilestoneBoard: { milestone in
                                    openProjectBoard(milestone.boardID, milestoneCardID: milestone.cardID)
                                },
                                onOpenMilestoneArtifact: { link in
                                    openMilestoneArtifact(link)
                                }
                            )
                        } else if surface == .assets {
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
                            ProjectWorkspaceSurfaceView(
                                model: ProjectWorkspaceSurfaceProvider.model(
                                    for: project,
                                    surface: surface,
                                    notes: notesStorage.notes,
                                    artifactRelations: ProjectWorkspaceSurfaceProvider.artifactRelations(for: notesStorage.notes)
                                ),
                                allNotes: notesStorage.notes,
                                artifactRelations: ProjectWorkspaceSurfaceProvider.artifactRelations(for: notesStorage.notes),
                                onOpenNote: { note in
                                    openNoteDetail(note)
                                }
                            )
                        }
                    }
                } else {
                    EmptyStateView(
                        icon: surface.systemImage,
                        title: "Project surface not found"
                    )
                }
            case .spacesOverview(let spaceID):
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
            case .agentRooms:
                let repository = ConversationRepository(database: CiderDatabase.shared)
                let canonical = AgentRoomsReadService(repository: repository)
                AgentRoomsWorkspaceView(
                    loadWorkspace: { request in
                        guard request.scope == .active,
                              request.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        else {
                            return canonical.loadWorkspace(request: request)
                        }
                        let paths = StoragePaths.legacyConversationPreviewDirectories()
                        let parityReader = ConversationRepositoryParityReader(repository: repository)
                        let eligible = LegacyConversationEligiblePreviewService(
                            registryDirectory: paths.registry,
                            conversationDirectory: paths.conversations,
                            parityReader: parityReader,
                            canonicalIsHonestlyEmpty: {
                                try repository.rooms(lifecycle: .active, limit: 1).isEmpty
                            }
                        )
                        let eligibleAdapter = EligibleLegacyAgentRoomsPreviewService(loadPreview: eligible.preview)
                        return AgentRoomsWorkspaceLoader(
                            loadCanonical: canonical.loadWorkspace,
                            loadLegacy: eligibleAdapter.loadWorkspace
                        ).loadWorkspace()
                    },
                    roomActions: AgentRoomsActionService(repository: repository),
                    session: agentRoomsSession,
                    onOpenLiveChat: {
                        requestFloat(.aiAssistant)
                    },
                    onOpenCiderReference: { route in
                        handleExternalOpenTarget(route.userInfo)
                    },
                    onExportRoom: { roomID, roomTitle in
                        AgentRoomsRoomExportPresenter.requestExport(
                            roomID: roomID,
                            roomTitle: roomTitle,
                            exporter: AgentRoomsRoomExportService(repository: repository)
                        )
                    }
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
            case .journal:
                journalDetailBody(projection: JournalLibraryReadModel.build(from: notesStorage.notes))
            case .search:
                let query: String = {
                    if case .library(.search(let query)) = workspaceRouter.currentRoute {
                        return query
                    }
                    return debouncedSearchText
                }()
                HomeDashboardView(
                    bookmarksViewModel: bookmarksViewModel,
                    notesViewModel: notesViewModel,
                    libraryViewModel: libraryViewModel,
                    selectedFolderID: nil,
                    displayMode: $homeDisplayMode,
                    cardSizeScale: $homeCardSizeScale,
                    continueSectionCollapsed: .constant(true),
                    selectedItemIDs: $selectedItemIDs,
                    sortMode: $homeSort,
                    entityFilter: $homeEntityFilter,
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
                    onOpenJournal: { openJournalDetail() },
    
                    onToggleLabelBulk: { toggleTagOnSelected($0) },
                    showComingUp: LibraryFeedPresentationPolicy.showsComingUpSection(on: .searchResults),
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
                    onOpenJournal: { openJournalDetail() },
    
                    onSelectTag: { id in
                        navigateToWorkspaceRoute(.library(.tag(id)))
                    },
                    onToggleLabelBulk: { toggleTagOnSelected($0) },
                    scrollToItemID: $scrollToItemID,
                    focusedItemID: focusedItemID
                )
            }
        }
    }

    var selectedStandaloneDomainDashboard: WorkspaceNavigationDomain? {
        guard let domain = selectedNavigationDomain else { return nil }
        switch domain {
        case .mainDashboard, .browse, .review, .projects, .spaces, .aiAssistant, .journal:
            return nil
        case .media, .bookmarks, .notes, .tasksEvents, .files, .people:
            break
        }
        guard WorkspaceRoutePresentation.presentation(for: workspaceRouter.currentRoute).sidebarDomain != domain else {
            return nil
        }
        guard WorkspaceDomainRoutePolicy.contentPresentation(
            for: selectedDomainRouteKind,
            in: domain
        ) == .dashboard else {
            return nil
        }
        return domain
    }

    var homeOverviewDashboard: some View {
        let reviewModel = homeDashboardReviewLoader.model
        let dateSuggestionResults = HomeOverviewDataProvider.bookmarkDateSuggestionResults(
            from: libraryViewModel.items
        )

        return HomeOverviewDashboardView(
            snapshot: HomeOverviewDataProvider.makeSnapshot(
                items: libraryViewModel.items,
                recentItems: libraryViewModel.recentItems,
                folders: bookmarksViewModel.folders,
                kanbanBoards: kanbanStorage.boards,
                reviewQueueItems: reviewModel?.items.items ?? [],
                reviewQueueSummary: reviewModel?.summary,
                bookmarkDateSuggestionResults: dateSuggestionResults,
                surfacingDays: CiderConfig.load().dateCardSurfacingDays
            ),
            onOpenItem: { item in openDashboardItem(item) },
            onOpenReviewSource: { reviewItem in openDashboardReviewSource(reviewItem) },
            onOpenTarget: { target in openDashboardTarget(target) },
            onOpenKanbanCard: { boardID, cardID in
                openKanbanCardDetail(boardID: boardID, cardID: cardID)
            },
            onPerformReviewAction: { reviewItem, action in
                performHomeReviewAction(reviewItem, action: action)
            },
            onEnrichReviewBatch: {
                enrichHomeReviewBatch()
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
        .task {
            await homeDashboardReviewLoader.loadIfNeeded()
        }
    }

    var reviewQueueDashboard: some View {
        let reviewQueue = CiderReviewQueueService()
        let reviewModel = try? reviewQueue.homeDashboardReviewModel(
            itemLimit: 60,
            batchEnrichmentSampleLimit: 8
        )
        let dateSuggestionResults = HomeOverviewDataProvider.bookmarkDateSuggestionResults(
            from: libraryViewModel.items
        )
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: libraryViewModel.items,
            recentItems: libraryViewModel.recentItems,
            folders: bookmarksViewModel.folders,
            kanbanBoards: kanbanStorage.boards,
            reviewQueueItems: reviewModel?.items.items ?? [],
            reviewQueueSummary: reviewModel?.summary,
            bookmarkDateSuggestionResults: dateSuggestionResults,
            surfacingDays: CiderConfig.load().dateCardSurfacingDays
        )

        return ReviewQueueDashboardView(
            items: snapshot.reviewCockpitItems,
            summary: snapshot.reviewCockpitSummary,
            onOpenItem: { item in openDashboardItem(item) },
            onOpenReviewSource: { reviewItem in openDashboardReviewSource(reviewItem) },
            onPerformReviewAction: { reviewItem, action in
                performHomeReviewAction(reviewItem, action: action)
            },
            onEnrichReviewBatch: {
                enrichHomeReviewBatch()
            }
        )
    }

    var selectedLibraryRouteFeed: (onlyUnassigned: Bool, entityTypes: Set<LibraryEntityType>)? {
        let routePresentation = WorkspaceRoutePresentation.presentation(for: workspaceRouter.currentRoute)
        if selectedNavigationDomain == .browse,
           routePresentation.sidebarDomain == .browse,
           case .libraryFeed(let entityTypes, let onlyUnassigned) = routePresentation.contentKind {
            return (onlyUnassigned, entityTypes)
        }

        guard let domain = selectedNavigationDomain, domain == .browse else { return nil }
        switch WorkspaceDomainRoutePolicy.contentPresentation(for: selectedDomainRouteKind, in: domain) {
        case .libraryFeed(let onlyUnassigned, let entityTypes):
            return (onlyUnassigned, entityTypes)
        case .homeOverviewDashboard, .dashboard, .folderBrowser, .tags, .assistantChats:
            return nil
        }
    }

    private func performHomeReviewAction(
        _ reviewItem: HomeReviewCockpitItem,
        action: HomeReviewCockpitAction
    ) -> Bool {
        let didChange: Bool
        switch action {
        case .accept:
            didChange = approveHomeReviewItem(reviewItem)
        case .reject:
            didChange = rejectHomeReviewItem(reviewItem)
        case .deferReview:
            didChange = deferHomeReviewItem(reviewItem)
        case .openSource:
            return openDashboardReviewSource(reviewItem)
        }
        if didChange {
            homeDashboardReviewLoader.invalidate()
            Task { await homeDashboardReviewLoader.loadIfNeeded() }
        }
        return didChange
    }

    private func approveHomeReviewItem(_ reviewItem: HomeReviewCockpitItem) -> Bool {
        do {
            if let approval = reviewItem.dateSuggestionApproval {
                _ = try CiderBookmarkDateSuggestionApprovalService().approve(
                    bookmarkID: approval.bookmarkID,
                    suggestionKey: approval.suggestionKey
                )
            } else if reviewItem.kindLabel == "Memory Candidate" {
                _ = try CiderReviewCandidateActionService().acceptMemoryCandidate(reviewItem.candidateID ?? reviewItem.candidateRef)
            } else if reviewItem.kindLabel == "Graph Candidate" {
                _ = try CiderReviewCandidateActionService().acceptGraphCandidateIfResolved(reviewItem.candidateID ?? reviewItem.candidateRef)
            } else {
                _ = try CiderReviewQueueService().approve(itemID: reviewItem.itemID, actor: "user")
            }
            return true
        } catch {
            print("Failed to approve Home review item: \(error.localizedDescription)")
            return false
        }
    }

    private func rejectHomeReviewItem(_ reviewItem: HomeReviewCockpitItem) -> Bool {
        do {
            if reviewItem.kindLabel == "Memory Candidate" {
                _ = try CiderReviewCandidateActionService().rejectMemoryCandidate(
                    reviewItem.candidateID ?? reviewItem.candidateRef,
                    reason: "Rejected from Home Review Queue."
                )
            } else if reviewItem.kindLabel == "Graph Candidate" {
                _ = try CiderReviewCandidateActionService().rejectGraphCandidate(
                    reviewItem.candidateID ?? reviewItem.candidateRef,
                    reason: "Rejected from Home Review Queue."
                )
            } else {
                return false
            }
            return true
        } catch {
            print("Failed to reject Home review item: \(error.localizedDescription)")
            return false
        }
    }

    private func deferHomeReviewItem(_ reviewItem: HomeReviewCockpitItem) -> Bool {
        do {
            if reviewItem.kindLabel == "Memory Candidate" {
                _ = try CiderReviewCandidateActionService().deferMemoryCandidate(
                    reviewItem.candidateID ?? reviewItem.candidateRef,
                    reason: "Deferred from Home Review Queue."
                )
            } else {
                _ = try CiderReviewQueueService().deferReview(
                    itemID: reviewItem.itemID,
                    reason: "Deferred from Home dashboard.",
                    actor: "user"
                )
            }
            return true
        } catch {
            print("Failed to defer Home review item: \(error.localizedDescription)")
            return false
        }
    }

    private func enrichHomeReviewBatch() -> Bool {
        do {
            _ = try CiderReviewQueueService().enrichBatch(actor: "user")
            homeDashboardReviewLoader.invalidate()
            Task { await homeDashboardReviewLoader.loadIfNeeded() }
            return true
        } catch {
            print("Failed to schedule Home review enrichment batch: \(error.localizedDescription)")
            return false
        }
    }

    func openOrCreateOnboardingTab() {
        navigateToWorkspaceRoute(.home)
    }

    // MARK: - Empty Route State

    var emptyRouteState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                .font(CiderFont.emptyStateIconLarge)
                .foregroundColor(CiderColors.tertiary)
            Text("No view selected")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)
            Text("Choose a workspace route from the sidebar")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
            Button("Open Home") { navigateToWorkspaceRoute(.home) }
                .buttonStyle(CiderAccentButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func openDashboardItem(_ item: LibraryItemV2) {
        switch item {
        case .journal:
            openJournalDetail()
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

    @discardableResult
    func openDashboardReviewSource(_ reviewItem: HomeReviewCockpitItem) -> Bool {
        guard let item = reviewItem.item else { return false }
        switch item {
        case .note(let note):
            let sourceContent = NotesStorage.shared.loadContent(for: note)
            openNoteDetail(
                note,
                sourceEvidenceFindQuery: reviewItem.bestSourceEvidenceFindQuery(in: sourceContent)
            )
        default:
            openDashboardItem(item)
        }
        return true
    }

    func openDashboardTarget(_ target: HomeOverviewActionTarget) {
        applyWorkspaceRouteIntent(WorkspaceRouteIntentPolicy.intent(forDashboardTarget: target))
    }

    func openProjectBoard(_ boardID: String, milestoneCardID: String? = nil) {
        guard let board = kanbanStorage.boards.first(where: { $0.id == boardID }) else { return }
        if let milestoneCardID {
            kanbanMilestoneFilterByBoardID[boardID] = milestoneCardID
        } else {
            kanbanMilestoneFilterByBoardID[boardID] = nil
        }
        navigateToWorkspaceRoute(
            ProjectWorkspaceRoutePolicy.route(
                forBoardID: board.id,
                milestoneCardID: milestoneCardID,
                in: selectedProjectWorkspace
            )
        )
    }

    func openMilestoneArtifact(_ link: ProjectWorkspaceMilestoneArtifactLink) {
        guard link.owner.ownerType == "note",
              let noteID = UUID(uuidString: link.owner.ownerID),
              let note = notesStorage.notes.first(where: { $0.id == noteID })
        else { return }
        openNoteDetail(note)
    }

    func projectHeaderTabs(
        for project: ProjectWorkspace,
        selectedKind: ProjectWorkspaceLocalTabKind
    ) -> [ProjectWorkspaceLocalTab] {
        guard project.kind == .project else { return [] }

        return ProjectWorkspaceLocalTabs.tabs(
            for: project,
            boards: kanbanStorage.boards,
            selectedKind: selectedKind
        )
    }

    @ViewBuilder
    func projectWorkspaceContent<Content: View>(
        for project: ProjectWorkspace,
        selectedKind: ProjectWorkspaceLocalTabKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let tabs = projectHeaderTabs(for: project, selectedKind: selectedKind)
        if tabs.isEmpty {
            content()
        } else {
            VStack(spacing: 0) {
                ProjectWorkspaceLocalTabStrip(
                    tabs: tabs,
                    onSelect: selectProjectHeaderTab
                )
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(CiderColors.separator)
                        .frame(height: 1)
                }

                content()
            }
        }
    }

    func selectProjectHeaderTab(_ kind: ProjectWorkspaceLocalTabKind) {
        guard let project = selectedProjectWorkspace else { return }
        navigateToWorkspaceRoute(ProjectWorkspaceRoutePolicy.route(for: kind, in: project))
    }

    func createProjectBoard(in project: ProjectWorkspace) {
        let board = kanbanStorage.createBoard(name: "Untitled Board")
        ProjectBoardRegistrationService.register(
            board: board,
            projectID: project.id,
            associationStore: projectAssociationStore
        )
        navigateToWorkspaceRoute(
            WorkspaceRouteIntentPolicy.projectBoardRoute(projectID: project.id, boardID: board.id)
        )
    }

    func projectArtifactRelations(for project: ProjectWorkspace) -> [SecondBrainRelation] {
        do {
            let context = try SecondBrainProjectGraphService(database: .shared).context(for: project.id)
            return context.artifactRelations
        } catch {
            return []
        }
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
        ProjectArtifactRelationService.recordCardRelation(
            boardID: boardID,
            boardName: found.board.name,
            card: updated,
            relationType: ProjectArtifactRelationType.derivesFrom,
            target: ref,
            targetTitle: title(for: ref),
            evidence: "Project reference linked to Kanban card \(updated.title)."
        )
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
        ProjectArtifactRelationService.recordCardRelation(
            boardID: board.id,
            boardName: board.name,
            card: card,
            relationType: ProjectArtifactRelationType.spawnedFrom,
            target: reference.ref,
            targetTitle: reference.item.title,
            evidence: "Promoted from \(project.title) reference \(reference.item.title)."
        )
        openKanbanCardDetail(boardID: board.id, cardID: card.id)
    }

    private func title(for ref: LibraryEntityRef) -> String? {
        ItemLinkService.shared.summaries(for: [ref]).first?.title
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
}
