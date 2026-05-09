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
            searchText: $sidebarSearchText,
            domains: WorkspaceNavigationDomain.allCases,
            selectedAnchor: selectedSidebarAnchor,
            selectedDomainRowIsCurrent: selectedDomainRowIsCurrent,
            onTriggerSearch: { isSearchPaletteVisible = true },
            onSelectDomain: openNavigationDomain
        ) {
            domainSidebarContent
        }
    }

    @ViewBuilder
    var domainSidebarContent: some View {
        if selectedNavigationDomain == .aiAssistant {
            AIAssistantDomainSidebarView(
                isChatListActive: selectedTab == .aiAssistant,
                onOpenAssistant: openOrSelectAIAssistantTab
            )
        } else if selectedNavigationDomain == .projects {
            ProjectsDomainSidebarView(
                catalog: projectWorkspaceCatalog,
                boards: kanbanStorage.boards,
                selectedWorkspaceID: $selectedProjectWorkspaceID,
                selectedTab: selectedTab,
                onSelectWorkspace: selectProjectWorkspace,
                onSelectDestination: selectProjectWorkspaceDestination
            )
        } else {
            folderSidebar(folders: contextualFolders)
        }
    }

    var selectedSidebarAnchor: WorkspaceSidebarAnchor? {
        guard selectedFolderID == nil, selectedTagIDs.isEmpty else {
            return nil
        }

        if selectedNavigationDomain == nil || selectedNavigationDomain == .mainDashboard {
            return .home
        }
        if selectedNavigationDomain == .browse {
            return .library
        }
        return nil
    }

    var selectedDomainRowIsCurrent: Bool {
        guard let selectedNavigationDomain,
              selectedNavigationDomain != .browse,
              selectedFolderID == nil,
              selectedTagIDs.isEmpty
        else {
            return false
        }

        switch selectedNavigationDomain {
        case .projects:
            return selectedProjectWorkspaceID == nil && selectedTab == .domainDashboard(.projects)
        case .aiAssistant:
            return selectedTab == .domainDashboard(.aiAssistant)
        case .mainDashboard, .browse, .media, .bookmarks, .notes, .tasksEvents, .files, .people:
            return true
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

        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedItemIDs.removeAll()
        focusedItemID = nil
        selectionAnchorID = nil
        closeAllDetails()

        if domain == .mainDashboard {
            selectedNavigationDomain = nil
            selectedProjectWorkspaceID = nil
            folderContentScope = .allItems
            selectedTab = dashboardTab ?? allTabs.first
            return
        }

        if selectedNavigationDomain != domain {
            selectedNavigationDomain = domain
        }

        selectedProjectWorkspaceID = nil

        folderContentScope = WorkspaceDomainContentScope.defaultScope(for: domain)

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
