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

        if case .savedView(let id, _) = tab {
            savedViewStorage.addToTabOrder(id)
        }

        selectedTab = tab
    }

    func reorderVisibleTabs(from sourceIndex: Int, to destinationIndex: Int) {
        let visibleTabs = contextualTabs
        guard visibleTabs.indices.contains(sourceIndex),
              visibleTabs.indices.contains(destinationIndex),
              let sourceID = visibleTabs[sourceIndex].savedViewID,
              let destinationID = visibleTabs[destinationIndex].savedViewID,
              let globalSourceIndex = savedViewStorage.tabOrder.firstIndex(of: sourceID),
              let globalDestinationIndex = savedViewStorage.tabOrder.firstIndex(of: destinationID) else {
            return
        }

        savedViewStorage.moveTab(from: globalSourceIndex, to: globalDestinationIndex)
    }

    func closeTab(_ tab: CiderTab) {
        let wasSelected = selectedTab == tab

        if case .savedView(let id, _) = tab {
            savedViewStorage.removeFromTabOrder(id)
        } else {
            dynamicTabs.removeAll { $0 == tab }
            if tab == .aiAssistant {
                CiderWorkspaceTabStateStore.shared.setAIAssistantTabOpen(false)
            }
        }

        if wasSelected {
            // Select adjacent tab, excluding the one just closed
            selectedTab = allTabs.first { $0 != tab }
        }
    }

    func deleteTab(_ tab: CiderTab) {
        guard case .savedView(let id, _) = tab else {
            closeTab(tab)
            return
        }
        guard let savedView = savedViewStorage.savedView(for: id) else { return }

        // For kanban tabs, trash the board YAML file
        if case .kanban(let boardID) = savedView.kind {
            if let trashItem = KanbanStorage.shared.deleteBoard(id: boardID) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .kanbanBoard, trashItem: trashItem))
            }
        }

        let wasSelected = selectedTab == tab
        savedViewStorage.deleteSavedView(id)
        if wasSelected {
            selectedTab = allTabs.first
        }
    }

    func deleteClosedTab(_ savedView: SavedView) {
        if case .kanban(let boardID) = savedView.kind {
            if let trashItem = KanbanStorage.shared.deleteBoard(id: boardID) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .kanbanBoard, trashItem: trashItem))
            }
        }
        savedViewStorage.deleteSavedView(savedView.id)
    }

    func reopenTab(_ id: UUID) {
        guard let savedView = savedViewStorage.savedView(for: id) else { return }
        savedViewStorage.addToTabOrder(id)
        withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
            selectedFolderID = nil
            selectedTab = .savedView(id: savedView.id, name: savedView.name)
        }
    }

    func createSavedViewFromCurrentState() {
        let name = nextSavedViewName()
        let filter = SavedViewFilterSpec(entityTypes: [])
        let layout = SavedViewLayoutSpec(
            displayMode: homeDisplayMode,
            cardSizeScale: homeCardSizeScale,
            showsGhostCells: true,
            showsCalendarProjection: false
        )
        let savedView = savedViewStorage.createSavedView(
            name: name,
            filterSpec: filter,
            layoutSpec: layout,
            isBlank: true
        )
        savedViewStorage.addToTabOrder(savedView.id)
        selectedTab = .savedView(id: savedView.id, name: savedView.name)
    }

    func deleteSavedView(_ id: UUID) {
        let wasSelected = selectedTab?.savedViewID == id
        _ = savedViewStorage.deleteSavedView(id)
        if wasSelected {
            selectedTab = allTabs.first
        }
    }

    private func nextSavedViewName() -> String {
        let usedNames = Set(savedViewStorage.tabOrderedViews().map(\.name))
        var index = 1
        while usedNames.contains("View \(index)") {
            index += 1
        }
        return "View \(index)"
    }

    func ensureDefaultTabs() {
        restorePersistentDynamicTabsIfNeeded()

        if savedViewStorage.savedViews.contains(where: { $0.kind == .dashboard }) == false {
            let dashboard = savedViewStorage.createDashboardView()
            savedViewStorage.removeFromTabOrder(dashboard.id)
            savedViewStorage.insertInTabOrder(dashboard.id, at: 0)
            if selectedTab == nil {
                selectedTab = .savedView(id: dashboard.id, name: dashboard.name)
            }
        }

        guard savedViewStorage.tabOrder.isEmpty else {
            // Tabs exist — just select the first one if nothing is selected
            if selectedTab == nil {
                selectedTab = allTabs.first
            }
            return
        }

        // First launch — create Inbox (unassigned items) + Library (all items)
        let inbox = savedViewStorage.createSavedView(
            name: "Inbox",
            filterSpec: SavedViewFilterSpec(onlyUnassigned: true)
        )
        savedViewStorage.addToTabOrder(inbox.id)

        let library = savedViewStorage.createSavedView(
            name: "Library",
            filterSpec: SavedViewFilterSpec()
        )
        savedViewStorage.addToTabOrder(library.id)

        // Create onboarding tab if not already completed
        let config = CiderConfig.load()
        if !config.hasCompletedOnboarding {
            let welcome = savedViewStorage.createSavedView(
                name: "Welcome",
                filterSpec: SavedViewFilterSpec(),
                isBlank: true,
                isOnboarding: true
            )
            savedViewStorage.insertInTabOrder(welcome.id, at: 0)
            selectedTab = .savedView(id: welcome.id, name: welcome.name)
        } else {
            selectedTab = .savedView(id: inbox.id, name: inbox.name)
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
