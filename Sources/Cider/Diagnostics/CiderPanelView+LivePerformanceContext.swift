import Foundation

extension CiderPanelView {
    @MainActor
    func updateLivePerformanceContext() {
        CiderLivePerformanceRecorder.shared.updateContext(livePerformanceContext)
    }

    @MainActor
    func recordLivePerformanceNavigation(
        action: String,
        from previous: CiderLivePerformanceNavigationSnapshot
    ) {
        CiderLivePerformanceRecorder.shared.recordNavigation(
            action: action,
            from: previous,
            to: livePerformanceNavigationSnapshot
        )
        updateLivePerformanceContext()
    }

    @MainActor
    var livePerformanceNavigationSnapshot: CiderLivePerformanceNavigationSnapshot {
        CiderLivePerformanceNavigationSnapshot(
            domain: selectedNavigationDomain?.title,
            route: selectedDomainRouteKind.rawValue,
            tab: selectedTab?.displayName,
            hasFolder: selectedFolderID != nil,
            tagCount: selectedTagIDs.count
        )
    }

    @MainActor
    var livePerformanceContext: CiderLivePerformanceContext {
        if !selectedTagIDs.isEmpty {
            return CiderLivePerformanceContext(
                view: "Tags",
                visibleItemCount: libraryViewModel.items.count
            )
        }

        if selectedFolderID != nil {
            return CiderLivePerformanceContext(
                view: "Folder",
                visibleItemCount: libraryViewModel.items.count
            )
        }

        guard let selectedTab else {
            return CiderLivePerformanceContext(view: "No tab", visibleItemCount: nil)
        }

        switch selectedTab {
        case .aiAssistant, .domainDashboard, .projectOverview, .projectInbox, .projectSurface, .projectReferences, .spaceOverview, .spacesManager:
            return CiderLivePerformanceContext(view: selectedTab.displayName, visibleItemCount: nil)
        case .projectBoard(_, let boardID, let name):
            let visibleCards = KanbanStorage.shared.boards
                .first(where: { $0.id == boardID })?
                .allCards
                .count
            return CiderLivePerformanceContext(view: name, visibleItemCount: visibleCards)
        case .search(_, let query):
            return CiderLivePerformanceContext(
                view: query.isEmpty ? "Search" : "Search: \(query)",
                visibleItemCount: libraryViewModel.items.count
            )
        case .tag:
            return CiderLivePerformanceContext(
                view: selectedTab.displayName,
                visibleItemCount: libraryViewModel.items.count
            )
        }
    }
}
