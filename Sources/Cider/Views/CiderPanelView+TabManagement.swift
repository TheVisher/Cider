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
            selectedSourceID = nil
            selectedTagIDs.removeAll()
            selectedTab = existing
        } else {
            let tab = CiderTab.tag(id: UUID())
            dynamicTabs.append(tab)
            selectedFolderID = nil
            selectedSourceID = nil
            selectedTagIDs.removeAll()
            selectedTab = tab
        }
    }

    func closeTab(_ tab: CiderTab) {
        let wasSelected = selectedTab == tab

        if case .savedView(let id, _) = tab {
            savedViewStorage.removeFromTabOrder(id)
        } else if case .externalSource(let id, _) = tab, var source = externalSourceStorage.source(for: id) {
            source.isTabPinned = false
            externalSourceStorage.updateSource(source)
        } else {
            dynamicTabs.removeAll { $0 == tab }
        }

        if wasSelected {
            // Select adjacent tab or nil
            selectedTab = allTabs.first
        }
    }

    func deleteTab(_ tab: CiderTab) {
        guard case .savedView(let id, _) = tab else {
            closeTab(tab)
            return
        }
        guard let savedView = savedViewStorage.savedView(for: id) else { return }

        // For whiteboard tabs, flush any pending drawing and send canvas to trash
        if case .whiteboard(let canvasID) = savedView.kind {
            whiteboardViewModel.flushSave()
            if let trashItem = WhiteboardStorage.shared.deleteCanvas(canvasID) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .whiteboard, trashItem: trashItem))
            }
        }

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
        if case .whiteboard(let canvasID) = savedView.kind {
            whiteboardViewModel.flushSave()
            if let trashItem = WhiteboardStorage.shared.deleteCanvas(canvasID) {
                CiderUndoManager.shared.record(.deletedToTrash(itemType: .whiteboard, trashItem: trashItem))
            }
        }
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
            selectedSourceID = nil
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
        if selectedFolderID == folderID {
            selectedFolderID = nil
        }
        bookmarksViewModel.deleteFolder(folderID)
    }
}
