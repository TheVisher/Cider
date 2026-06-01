import SwiftUI

extension CiderPanelView {

    // MARK: - Search Tab Management

    func spawnSearchTab(_ query: String) {
        let tab = CiderTab.search(id: UUID(), query: query)
        dynamicTabs.append(tab)
        selectedTab = tab
    }

    func openOrSelectTagTab() {
        // Check if a .tag tab already exists
        if let existing = allTabs.first(where: { if case .tag = $0 { return true }; return false }) {
            selectedFolderID = nil
            selectedTagIDs.removeAll()
            selectedTab = existing
        } else {
            let tab = CiderTab.tag(id: UUID())
            dynamicTabs.append(tab)
            selectedFolderID = nil
            selectedTagIDs.removeAll()
            selectedTab = tab
        }
    }

    func openOrSelectAIAssistantTab() {
        if let existing = allTabs.first(where: { $0 == .aiAssistant }) {
            CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(true)
            selectedFolderID = nil
            selectedTagIDs.removeAll()
            selectedTab = existing
        } else {
            dynamicTabs.append(.aiAssistant)
            CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(true)
            selectedFolderID = nil
            selectedTagIDs.removeAll()
            selectedTab = .aiAssistant
        }
    }

    func openDomainDashboardTab(_ tab: CiderTab) {
        selectedFolderID = nil
        selectedTagIDs.removeAll()
        selectedTab = tab
    }

    func reorderVisibleTabs(from sourceIndex: Int, to destinationIndex: Int) {
    }

    func closeTab(_ tab: CiderTab) {
        if removeBoardFromSelectedProject(tab) {
            return
        }

        let wasSelected = selectedTab == tab

        dynamicTabs.removeAll { $0 == tab }
        if tab == .aiAssistant {
            CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(false)
        }

        if wasSelected {
            // Select adjacent tab, excluding the one just closed
            selectedTab = allTabs.first { $0 != tab }
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
        if selectedTab == tab {
            selectedTab = .projectOverview(projectID: association.project.id, name: "Overview")
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

        selectedFolderID = nil
        selectedTab = .projectBoard(projectID: project.id, boardID: board.id, name: board.name)
    }

    func deleteTab(_ tab: CiderTab) {
        closeTab(tab)
    }

    func ensureDefaultTabs() {
        restorePersistentDynamicTabsIfNeeded()
        if selectedTab == nil {
            selectedTab = .domainDashboard(.mainDashboard)
        }
    }

    private func restorePersistentDynamicTabsIfNeeded() {
        for tab in CiderWorkspaceTabStateStore.shared.restoredDynamicTabs() where !dynamicTabs.contains(tab) {
            dynamicTabs.append(tab)
        }
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
