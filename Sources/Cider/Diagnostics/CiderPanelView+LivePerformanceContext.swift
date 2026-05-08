import Foundation

extension CiderPanelView {
    @MainActor
    func updateLivePerformanceContext() {
        CiderLivePerformanceRecorder.shared.updateContext(livePerformanceContext)
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
        case .aiAssistant, .domainDashboard:
            return CiderLivePerformanceContext(view: selectedTab.displayName, visibleItemCount: nil)
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
        case .savedView(let id, let name):
            if let savedView = savedViewStorage.savedView(for: id) {
                switch savedView.kind {
                case .kanban(let boardID):
                    let visibleCards = KanbanStorage.shared.boards
                        .first(where: { $0.id == boardID })?
                        .allCards
                        .count
                    return CiderLivePerformanceContext(view: name, visibleItemCount: visibleCards)
                default:
                    return CiderLivePerformanceContext(view: name, visibleItemCount: libraryViewModel.items.count)
                }
            }
            return CiderLivePerformanceContext(view: name, visibleItemCount: nil)
        }
    }
}
