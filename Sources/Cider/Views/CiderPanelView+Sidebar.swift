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
            onTriggerSearch: { isSearchPaletteVisible = true },
            onSelectDomain: openNavigationDomain
        ) { domain in
            domainSidebarContent(for: domain)
        }
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
                    selectedTagIDs.insert(id)
                    selectedFolderID = nil
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
            selectedNavigationDomain = nil
            selectedProjectWorkspaceID = nil
            selectedDomainRouteKind = .overview
            folderContentScope = .allItems
            selectedTab = dashboardTab ?? allTabs.first
            return
        }

        if selectedNavigationDomain != domain {
            selectedNavigationDomain = domain
        }

        selectedProjectWorkspaceID = nil
        selectedDomainRouteKind = defaultRouteKind(for: domain)

        folderContentScope = WorkspaceDomainContentScope.defaultScope(for: domain)

        if domain == .browse {
            openLibraryView(onlyUnassigned: true)
            return
        }

        if domain == .aiAssistant {
            if allTabs.contains(.aiAssistant) == false {
                dynamicTabs.append(.aiAssistant)
                CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(true)
            }
            selectedTab = .domainDashboard(.aiAssistant)
            return
        }

        if domain == .mainDashboard {
            normalizeSelectedTabForCurrentDomain()
        } else {
            selectedTab = .domainDashboard(domain)
        }
    }

    func selectWorkspaceDomainRoute(_ route: WorkspaceDomainRoute, in domain: WorkspaceNavigationDomain) {
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
        case .recent, .savedViews:
            selectedTab = .domainDashboard(domain)
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
        let name = explicitName ?? (onlyUnassigned ? "Inbox" : "Library")

        if let savedView = savedViewStorage.savedViews.first(where: {
            $0.kind == .library
                && $0.filterSpec.onlyUnassigned == onlyUnassigned
                && $0.filterSpec.entityTypes == entityTypes
        }) {
            selectedTab = .savedView(id: savedView.id, name: savedView.name)
            return
        }

        if onlyUnassigned {
            homeDisplayMode = LibraryInboxPresentationPolicy.preferredDisplayMode
        }

        let savedView = savedViewStorage.createSavedView(
            name: name,
            filterSpec: SavedViewFilterSpec(
                entityTypes: entityTypes,
                onlyUnassigned: onlyUnassigned
            ),
            layoutSpec: SavedViewLayoutSpec(
                displayMode: onlyUnassigned ? LibraryInboxPresentationPolicy.preferredDisplayMode : .list
            )
        )
        savedViewStorage.addToTabOrder(savedView.id)
        selectedTab = .savedView(id: savedView.id, name: savedView.name)
    }

    var dashboardTab: CiderTab? {
        guard let savedView = savedViewStorage.savedViews.first(where: { $0.kind == .dashboard }) else {
            return nil
        }
        return .savedView(id: savedView.id, name: savedView.name)
    }

    func selectProjectWorkspace(_ workspace: ProjectWorkspace) {
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()
        selectedDomainRouteKind = .overview

        switch workspace.kind {
        case .home:
            selectedProjectWorkspaceID = nil
            selectedNavigationDomain = .projects
            selectedTab = .domainDashboard(.projects)
        case .project:
            selectedProjectWorkspaceID = workspace.id
            selectedNavigationDomain = .projects
            selectedTab = .projectOverview(projectID: workspace.id, name: "Overview")
        case .browseAllBoards:
            selectedProjectWorkspaceID = workspace.id
            selectedNavigationDomain = .projects
            selectedTab = .projectOverview(projectID: workspace.id, name: "All Boards")
        }
    }

    func selectProjectWorkspaceDestination(_ destination: ProjectWorkspaceSidebarDestination, in workspace: ProjectWorkspace) {
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()
        selectedProjectWorkspaceID = workspace.id
        selectedNavigationDomain = .projects
        selectedDomainRouteKind = .overview

        switch destination.kind {
        case .overview:
            selectedTab = .projectOverview(projectID: workspace.id, name: "Overview")
        case .boardsGroup:
            break
        case .board(let boardID):
            openProjectBoard(boardID)
        case .references:
            selectedTab = .projectReferences(projectID: workspace.id, name: "References")
        }
    }

    func normalizeSelectedTabForCurrentDomain() {
        let tabs = contextualTabs
        if let selectedTab, tabs.contains(selectedTab) { return }
        selectedTab = tabs.first
    }
}
