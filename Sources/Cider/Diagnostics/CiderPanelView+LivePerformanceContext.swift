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
        CiderUsageAuditService.shared.recordAppRouteOpen(
            domain: livePerformanceNavigationSnapshot.domain,
            route: livePerformanceNavigationSnapshot.route
        )
        updateLivePerformanceContext()
    }

    @MainActor
    var livePerformanceNavigationSnapshot: CiderLivePerformanceNavigationSnapshot {
        CiderLivePerformanceNavigationSnapshot(
            domain: selectedNavigationDomain?.title,
            route: selectedDomainRouteKind.rawValue,
            tab: workspaceRouter.presentation.title,
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

        let presentation = workspaceRouter.presentation
        switch presentation.contentKind {
        case .projectBoard(let boardID, _):
            let visibleCards = KanbanStorage.shared.boards
                .first(where: { $0.id == boardID })?
                .allCards
                .count
            return CiderLivePerformanceContext(view: presentation.title, visibleItemCount: visibleCards)
        case .search:
            let query: String
            if case .library(.search(let routeQuery)) = workspaceRouter.currentRoute {
                query = routeQuery
            } else {
                query = ""
            }
            return CiderLivePerformanceContext(
                view: query.isEmpty ? "Search" : "Search: \(query)",
                visibleItemCount: libraryViewModel.items.count
            )
        case .tag:
            return CiderLivePerformanceContext(
                view: presentation.title,
                visibleItemCount: libraryViewModel.items.count
            )
        case .libraryFeed, .folder:
            return CiderLivePerformanceContext(
                view: presentation.title,
                visibleItemCount: libraryViewModel.items.count
            )
        case .home, .reviewQueue, .libraryDashboard, .projectsHome, .projectOverview, .projectInbox, .projectSurface, .spacesOverview, .spacesManager, .aiAssistant, .journal:
            return CiderLivePerformanceContext(view: presentation.title, visibleItemCount: nil)
        }
    }
}
