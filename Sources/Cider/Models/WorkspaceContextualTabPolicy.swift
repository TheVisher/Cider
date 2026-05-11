import Foundation

enum WorkspaceContextualTabPolicy {
    static func tabs(
        for domain: WorkspaceNavigationDomain?,
        selectedProject: ProjectWorkspace? = nil,
        selectedTab: CiderTab? = nil,
        allTabs: [CiderTab],
        savedViews: [SavedView]
    ) -> [CiderTab] {
        if selectedTab == .aiAssistant && domain == nil { return [.aiAssistant] }
        if let selectedTab, case .spaceOverview = selectedTab, domain == nil {
            return [selectedTab]
        }
        if selectedTab == .spacesManager && domain == nil { return [.spacesManager] }

        let domainTabs = allTabs.filter { tab in
            tab != .aiAssistant && tab != .spacesManager
        }

        guard let domain else { return domainTabs }
        if domain == .aiAssistant {
            var result: [CiderTab] = [.domainDashboard(.aiAssistant)]
            if allTabs.contains(.aiAssistant) {
                result.append(.aiAssistant)
            }
            return result
        }
        if domain == .browse { return [CiderTab.domainDashboard(.browse)] + domainTabs }
        if domain == .projects, let selectedProject {
            switch selectedProject.kind {
            case .project:
                return projectTabs(for: selectedProject, savedViews: savedViews, allTabs: domainTabs)
            case .browseAllBoards:
                return browseAllBoardTabs(for: selectedProject, selectedTab: selectedTab, savedViews: savedViews)
            case .home:
                break
            }
        }

        let savedViewByID = Dictionary(uniqueKeysWithValues: savedViews.map { ($0.id, $0) })
        let matchingTabs = domainTabs.filter { tab in
            isCompatibilityTab(tab) || matches(tab, domain: domain, savedViewByID: savedViewByID)
        }
        if domain == .mainDashboard { return matchingTabs }
        return [CiderTab.domainDashboard(domain)] + matchingTabs
    }

    private static func projectTabs(
        for project: ProjectWorkspace,
        savedViews: [SavedView],
        allTabs: [CiderTab]
    ) -> [CiderTab] {
        let boardTabs = project.boardIDs.compactMap { boardID -> CiderTab? in
            guard let savedView = savedViews.first(where: { savedView in
                if case .kanban(let savedBoardID) = savedView.kind {
                    return savedBoardID == boardID
                }
                return false
            }) else { return nil }
            return .savedView(id: savedView.id, name: savedView.name)
        }

        var result: [CiderTab] = [
            .projectOverview(projectID: project.id, name: "Overview")
        ] + boardTabs + [
            .projectReferences(projectID: project.id, name: "References")
        ]

        for tab in allTabs where isCompatibilityTab(tab) && !result.contains(tab) {
            result.append(tab)
        }
        return result
    }

    private static func browseAllBoardTabs(
        for workspace: ProjectWorkspace,
        selectedTab: CiderTab?,
        savedViews: [SavedView]
    ) -> [CiderTab] {
        var result: [CiderTab] = [
            .projectOverview(projectID: workspace.id, name: "All Boards")
        ]

        guard case .savedView(let selectedID, let selectedName) = selectedTab,
              let savedView = savedViews.first(where: { $0.id == selectedID }),
              case .kanban(let boardID) = savedView.kind,
              workspace.boardIDs.contains(boardID) else {
            return result
        }

        result.append(.savedView(id: selectedID, name: selectedName))
        return result
    }

    private static func isCompatibilityTab(_ tab: CiderTab) -> Bool {
        if tab == .aiAssistant { return true }
        if case .search = tab { return true }
        if case .tag = tab { return true }
        if case .spaceOverview = tab { return true }
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
        case .media, .aiAssistant:
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
