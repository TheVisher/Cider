import Foundation

enum WorkspaceContextualTabPolicy {
    static func tabs(
        for domain: WorkspaceNavigationDomain?,
        allTabs: [CiderTab],
        savedViews: [SavedView]
    ) -> [CiderTab] {
        guard let domain else { return allTabs }

        let savedViewByID = Dictionary(uniqueKeysWithValues: savedViews.map { ($0.id, $0) })
        let compatibleTabs = allTabs.filter { tab in
            isCompatibilityTab(tab) || matches(tab, domain: domain, savedViewByID: savedViewByID)
        }

        return compatibleTabs.isEmpty ? allTabs : compatibleTabs
    }

    private static func isCompatibilityTab(_ tab: CiderTab) -> Bool {
        if tab == .aiAssistant { return true }
        if case .search = tab { return true }
        if case .tag = tab { return true }
        return false
    }

    private static func matches(
        _ tab: CiderTab,
        domain: WorkspaceNavigationDomain,
        savedViewByID: [UUID: SavedView]
    ) -> Bool {
        guard case .savedView(let id, _) = tab,
              let savedView = savedViewByID[id] else {
            return false
        }

        switch domain {
        case .mainDashboard:
            return savedView.kind == .dashboard
        case .projects:
            if case .kanban = savedView.kind { return true }
            return false
        case .bookmarks:
            return isLibraryView(savedView, scopedTo: [.bookmark])
        case .notes:
            return isLibraryView(savedView, scopedTo: [.note])
        case .tasksEvents:
            return isLibraryView(savedView, scopedTo: [.todo, .dateCard])
        case .files:
            return isLibraryView(savedView, scopedTo: [.vaultFile])
        case .people:
            return isLibraryView(savedView, scopedTo: [.contact])
        case .browse:
            return savedView.kind == .library
        case .media:
            return false
        }
    }

    private static func isLibraryView(_ savedView: SavedView, scopedTo entityTypes: Set<LibraryEntityType>) -> Bool {
        guard savedView.kind == .library else { return false }
        let activeTypes = savedView.filterSpec.entityTypes.isEmpty
            ? LibraryEntityType.activeCases
            : savedView.filterSpec.entityTypes
        return !activeTypes.isDisjoint(with: entityTypes) && activeTypes.isSubset(of: entityTypes)
    }
}
