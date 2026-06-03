import SwiftUI

extension CiderPanelView {

    // MARK: - Route Compatibility Management

    func openSearchRoute(_ query: String) {
        navigateToWorkspaceRoute(.library(.search(query)))
    }

    func openOrSelectTagTab() {
        navigateToWorkspaceRoute(.library(.tags))
    }

    func openOrSelectAIAssistantTab() {
        CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(true)
        navigateToWorkspaceRoute(.ai)
    }

    func reorderVisibleTabs(from sourceIndex: Int, to destinationIndex: Int) {
    }

    func closeTab(_ tab: CiderTab) {
        if removeBoardFromSelectedProject(tab) {
            return
        }

        let wasSelected = workspaceRouteMatchesLegacyTab(tab)

        if tab == .aiAssistant {
            CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(false)
        }

        if wasSelected {
            navigateToWorkspaceRoute(.home)
        }
    }

    func projectBoardRemovalTitle(for tab: CiderTab) -> String? {
        guard let association = selectedProjectBoardAssociation(for: tab) else { return nil }
        return "Remove \(association.boardName) from \(association.project.title)"
    }

    @discardableResult
    func removeBoardFromSelectedProject(_ tab: CiderTab) -> Bool {
        guard let association = selectedProjectBoardAssociation(for: tab) else { return false }
        projectAssociationStore.exclude(
            boardID: association.boardID,
            fromProjectID: association.project.id
        )
        if workspaceRouteMatchesLegacyTab(tab) {
            navigateToWorkspaceRoute(ProjectWorkspaceRoutePolicy.route(for: association.project))
        }
        return true
    }

    private func selectedProjectBoardAssociation(for tab: CiderTab) -> (
        project: ProjectWorkspace,
        boardID: String,
        boardName: String
    )? {
        guard selectedNavigationDomain == .projects,
              let project = selectedProjectWorkspace,
              project.kind == .project,
              case .projectBoard(_, let boardID, let tabName) = tab,
              project.boardIDs.contains(boardID) else {
            return nil
        }

        let boardName = kanbanStorage.boards.first(where: { $0.id == boardID })?.name ?? tabName
        return (project, boardID, boardName)
    }

    var projectAddableBoards: [KanbanBoard]? {
        guard selectedNavigationDomain == .projects,
              let project = selectedProjectWorkspace,
              project.kind == .project else {
            return nil
        }
        return kanbanStorage.boards.filter { !project.boardIDs.contains($0.id) }
    }

    func addBoardToSelectedProject(_ board: KanbanBoard) {
        guard selectedNavigationDomain == .projects,
              let project = selectedProjectWorkspace,
              project.kind == .project else {
            return
        }

        projectAssociationStore.include(boardID: board.id, inProjectID: project.id)

        navigateToWorkspaceRoute(
            ProjectWorkspaceRoutePolicy.route(forBoardID: board.id, milestoneCardID: nil, in: project)
        )
    }

    func deleteTab(_ tab: CiderTab) {
        closeTab(tab)
    }

    func ensureDefaultTabs() {
        if let restoredRoute = CiderWorkspaceTabStateStore.shared.restoredWorkspaceRoute() {
            navigateToWorkspaceRoute(restoredRoute)
            return
        }
        navigateToWorkspaceRoute(.home)
    }

    private func workspaceRouteMatchesLegacyTab(_ tab: CiderTab) -> Bool {
        WorkspaceRouterCompatibility.route(from: WorkspaceRouterCompatibilityState(
            selectedTab: tab,
            selectedNavigationDomain: selectedNavigationDomain,
            selectedDomainRouteKind: selectedDomainRouteKind,
            selectedFolderID: selectedFolderID,
            selectedTagIDs: selectedTagIDs,
            selectedProjectWorkspaceID: selectedProjectWorkspaceID
        )) == workspaceRouter.currentRoute
    }

    func expandPathToFolder(_ folderID: UUID) {
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

    func isRootFolder(_ folderID: UUID) -> Bool {
        bookmarksViewModel.folders.first(where: { $0.id == folderID })?.parentID == nil
    }

    func deleteFolder(_ folderID: UUID) {
        // Collect all IDs that will be removed (root + descendants)
        var deletedIDs: Set<UUID> = [folderID]
        if let vf = VaultFolderService.shared.folder(for: folderID) {
            let prefix = vf.relativePath + "/"
            for f in VaultFolderService.shared.folders where f.relativePath.hasPrefix(prefix) {
                deletedIDs.insert(f.id)
            }
        }
        if let sel = selectedFolderID, deletedIDs.contains(sel) {
            selectedFolderID = nil
        }
        expandedFolderIDs.subtract(deletedIDs)
        bookmarksViewModel.deleteFolder(folderID)
    }
}
