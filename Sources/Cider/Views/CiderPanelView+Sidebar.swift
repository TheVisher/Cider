import SwiftUI
import AppKit

extension CiderPanelView {

    // MARK: - Section Toggles

    var folderHasSubFolders: Bool {
        guard let folderID = selectedFolderID else { return false }
        return bookmarksViewModel.folders.contains(where: { $0.parentID == folderID })
    }

    // MARK: - Sidebar Content

    var workspaceSidebar: some View {
        WorkspaceDomainSidebarView(
            selectedDomain: $selectedNavigationDomain,
            expandedDomains: $expandedNavigationDomains,
            searchText: $sidebarSearchText,
            domains: WorkspaceNavigationDomain.allCases,
            spaces: spaceStorage.spaces,
            selectedSpaceID: selectedSpaceID,
            isSpacesManagerSelected: selectedTab == .spacesManager,
            onTriggerSearch: { isSearchPaletteVisible = true },
            onSelectDomain: openNavigationDomain,
            onSelectSpace: openSpace,
            onCreateSpace: createSpace,
            onOpenSpacesManager: openSpacesManager
        ) { domain in
            domainSidebarContent(for: domain)
        }
    }

    var selectedSpaceID: String? {
        guard case .spaceOverview(let id, _) = selectedTab else { return nil }
        return id
    }

    @ViewBuilder
    func domainSidebarContent(for domain: WorkspaceNavigationDomain) -> some View {
        if domain == .aiAssistant {
            AIAssistantDomainSidebarView(
                isChatListActive: selectedNavigationDomain == .aiAssistant && selectedTab == .aiAssistant,
                onOpenAssistant: openOrSelectAIAssistantTab
            )
        } else if domain == .projects {
            ProjectsDomainSidebarView(
                catalog: projectWorkspaceCatalog,
                boards: kanbanStorage.boards,
                selectedWorkspaceID: $selectedProjectWorkspaceID,
                selectedTab: selectedTab,
                onSelectWorkspace: selectProjectWorkspace,
                onSelectDestination: selectProjectWorkspaceDestination
            )
        } else if domain == .spaces {
            EmptyView()
        } else {
            WorkspaceDomainRouteSidebarView(
                domain: domain,
                selectedRouteKind: selectedNavigationDomain == domain ? selectedDomainRouteKind : nil,
                onSelectRoute: selectWorkspaceDomainRoute
            )
        }
    }

    var contextualFolders: [Folder] {
        WorkspaceDomainFolderPolicy.folders(bookmarksViewModel.folders, for: selectedNavigationDomain)
    }

    func folderSidebar(folders visibleFolders: [Folder]) -> some View {
        FolderSidebarView(
            folders: visibleFolders,
            bookmarks: bookmarksViewModel.bookmarks,
            notes: notesViewModel.notes,
            selectedFolderID: $selectedFolderID,
            expandedFolderIDs: $expandedFolderIDs,
            onCreateFolder: { bookmarksViewModel.createFolder(name: $0, parentID: $1) },
            onAssignBookmarkToFolder: { bookmarksViewModel.assign($0, toFolder: $1) },
            onAssignNoteToFolder: { notesViewModel.assignNote($0, toFolder: $1) },
            onRenameFolder: { bookmarksViewModel.renameFolder($0, to: $1) },
            onSetFolderIcon: { VaultFolderService.shared.setIcon($1, for: $0) },
            onDeleteFolder: deleteFolder,
            searchText: $sidebarSearchText,
            onTriggerSearch: { isSearchPaletteVisible = true },
            showsSearchField: false,
            showBackground: false,
            contentEntityTypes: folderContentScope.entityTypes(for: selectedNavigationDomain),
            labels: labelStorage.labels,
            selectedTagIDs: $selectedTagIDs,
            tagsCollapsed: $tagsCollapsed,
            onToggleTag: { id in
                if selectedTagIDs.contains(id) {
                    selectedTagIDs.remove(id)
                } else {
                    navigateToWorkspaceRoute(.library(.tag(id)))
                }
            },
            onClearTags: {
                selectedTagIDs.removeAll()
            },
            onOpenTagManager: {
                openOrSelectTagTab()
            }
        )
    }

    func openNavigationDomain(_ domain: WorkspaceNavigationDomain) {
        let navigationSnapshot = livePerformanceNavigationSnapshot
        defer {
            recordLivePerformanceNavigation(
                action: "open_navigation_domain:\(domain.title)",
                from: navigationSnapshot
            )
        }

        let previousDomain = selectedNavigationDomain
        if previousDomain != domain {
            expandedFolderIDs.removeAll()
        }
        if domain != .mainDashboard {
            expandedNavigationDomains.insert(domain)
        }

        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()

        if domain == .mainDashboard {
            workspaceRouter.navigate(to: .home)
            selectedNavigationDomain = nil
            selectedProjectWorkspaceID = nil
            selectedDomainRouteKind = .overview
            folderContentScope = .allItems
            selectedTab = dashboardTab ?? allTabs.first
            return
        }

        if domain == .browse {
            navigateToWorkspaceRoute(.library(.overview))
            return
        }

        if selectedNavigationDomain != domain {
            selectedNavigationDomain = domain
        }

        selectedProjectWorkspaceID = nil
        selectedDomainRouteKind = .overview

        folderContentScope = WorkspaceDomainContentScope.defaultScope(for: domain)

        if let headerTab = WorkspaceDomainRoutePolicy.headerDefaultTab(for: domain) {
            selectedTab = headerTab
        }
    }

    func openSpace(_ space: CiderSpace) {
        let navigationSnapshot = livePerformanceNavigationSnapshot
        defer {
            recordLivePerformanceNavigation(
                action: "open_space:\(space.name)",
                from: navigationSnapshot
            )
        }

        selectedNavigationDomain = .spaces
        selectedProjectWorkspaceID = nil
        selectedDomainRouteKind = .overview
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()
        selectedTab = .spaceOverview(id: space.id, name: space.name)
    }

    func openSpacesManager() {
        let navigationSnapshot = livePerformanceNavigationSnapshot
        defer {
            recordLivePerformanceNavigation(
                action: "open_spaces_manager",
                from: navigationSnapshot
            )
        }

        selectedNavigationDomain = .spaces
        selectedProjectWorkspaceID = nil
        selectedDomainRouteKind = .overview
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()
        selectedTab = .spacesManager
    }

    func createSpace(_ preset: CiderSpacePresetKind) {
        let defaults = CiderSpacePreset.defaults(for: preset)
        do {
            let space = try spaceStorage.createSpace(
                name: defaults.title,
                preset: preset,
                isPinned: true
            )
            openSpace(space)
        } catch {
            print("Failed to create Space: \(error.localizedDescription)")
        }
    }

    func togglePinnedSpace(_ space: CiderSpace) {
        do {
            try spaceStorage.setPinned(!space.isPinned, for: space.id)
        } catch {
            print("Failed to update Space pin state: \(error.localizedDescription)")
        }
    }

    func selectWorkspaceDomainRoute(_ route: WorkspaceDomainRoute, in domain: WorkspaceNavigationDomain) {
        let navigationSnapshot = livePerformanceNavigationSnapshot
        defer {
            recordLivePerformanceNavigation(
                action: "select_domain_route:\(domain.title)/\(route.title)",
                from: navigationSnapshot
            )
        }

        if domain == .browse {
            navigateToWorkspaceRoute(
                WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
                    selectedTab: .domainDashboard(.browse),
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: route.kind
                ))
            )
            return
        }

        if selectedNavigationDomain != domain {
            selectedNavigationDomain = domain
            selectedProjectWorkspaceID = nil
            folderContentScope = WorkspaceDomainContentScope.defaultScope(for: domain)
            expandedNavigationDomains.insert(domain)
        }

        selectedDomainRouteKind = route.kind
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()

        switch route.kind {
        case .overview:
            selectedTab = .domainDashboard(domain)
        case .all:
            if domain == .browse {
                openLibraryView(onlyUnassigned: false)
            } else {
                selectedTab = .domainDashboard(domain)
            }
        case .bookmarks, .notes, .files:
            if domain == .browse, let entityTypes = route.kind.libraryEntityTypes {
                openLibraryView(
                    named: route.title,
                    onlyUnassigned: false,
                    entityTypes: entityTypes
                )
            } else {
                selectedTab = .domainDashboard(domain)
            }
        case .folders:
            selectedTab = .domainDashboard(domain)
        case .tags:
            openOrSelectTagTab()
        case .chats:
            openOrSelectAIAssistantTab()
        case .inbox:
            if domain == .browse {
                openLibraryView(onlyUnassigned: true)
            } else {
                selectedTab = .domainDashboard(domain)
            }
        case .recent:
            selectedTab = .domainDashboard(domain)
        }
    }

    func navigateToWorkspaceRoute(_ route: WorkspaceRoute) {
        workspaceRouter.navigate(to: route)

        let legacyState = WorkspaceRouteLegacyProjection.state(for: route)
        selectedNavigationDomain = legacyState.selectedNavigationDomain
        selectedProjectWorkspaceID = legacyState.selectedProjectWorkspaceID
        selectedDomainRouteKind = legacyState.selectedDomainRouteKind
        selectedFolderID = legacyState.selectedFolderID
        selectedTagIDs = legacyState.selectedTagIDs
        selectedTab = legacyState.selectedTab
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        sidebarSearchText = ""
        debouncedSearchText = ""
        searchDebounceTask?.cancel()
        closeAllDetails()
        if let selectedNavigationDomain {
            expandedNavigationDomains.insert(selectedNavigationDomain)
            folderContentScope = WorkspaceDomainContentScope.defaultScope(for: selectedNavigationDomain)
        }
        updateLivePerformanceContext()
    }

    func applyWorkspaceRouteIntent(_ intent: WorkspaceRouteIntent) {
        navigateToWorkspaceRoute(intent.route)
        switch intent.detail {
        case .kanbanCard(let boardID, let cardID):
            openKanbanCardDetail(boardID: boardID, cardID: cardID)
        case nil:
            break
        }
    }

    private func defaultRouteKind(for domain: WorkspaceNavigationDomain) -> WorkspaceDomainRouteKind {
        WorkspaceDomainRoutePolicy.routes(for: domain).first?.kind ?? .overview
    }

    private func openLibraryView(
        named explicitName: String? = nil,
        onlyUnassigned: Bool,
        entityTypes: Set<LibraryEntityType> = LibraryEntityType.activeCases
    ) {
        if onlyUnassigned {
            homeDisplayMode = LibraryInboxPresentationPolicy.preferredDisplayMode
        }
        selectedTab = .domainDashboard(.browse)
    }

    var dashboardTab: CiderTab? {
        .domainDashboard(.mainDashboard)
    }

    func selectProjectWorkspace(_ workspace: ProjectWorkspace) {
        navigateToWorkspaceRoute(ProjectWorkspaceRoutePolicy.route(for: workspace))
    }

    func selectProjectWorkspaceDestination(_ destination: ProjectWorkspaceSidebarDestination, in workspace: ProjectWorkspace) {
        guard destination.isSelectable else { return }
        navigateToWorkspaceRoute(ProjectWorkspaceRoutePolicy.route(for: destination, in: workspace))
    }

    func normalizeSelectedTabForCurrentDomain() {
        let tabs = contextualTabs
        if let selectedTab, tabs.contains(selectedTab) { return }
        selectedTab = tabs.first
    }
}
