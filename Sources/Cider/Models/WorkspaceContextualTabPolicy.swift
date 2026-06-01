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
        if domain == .spaces {
            return [CiderTab.domainDashboard(.spaces)] + allTabs.filter { tab in
                if case .spaceOverview = tab { return true }
                return tab == .spacesManager
            }
        }
        if domain == .projects, let selectedProject {
            switch selectedProject.kind {
            case .project:
                return projectTabs(for: selectedProject, allTabs: domainTabs)
            case .browseAllBoards:
                return browseAllBoardTabs(for: selectedProject, selectedTab: selectedTab)
            case .home:
                break
            }
        }

        let matchingTabs = domainTabs.filter { tab in
            isCompatibilityTab(tab) || matches(tab, domain: domain)
        }
        if domain == .mainDashboard { return matchingTabs }
        return [CiderTab.domainDashboard(domain)] + matchingTabs
    }

    private static func projectTabs(
        for project: ProjectWorkspace,
        allTabs: [CiderTab]
    ) -> [CiderTab] {
        let boardTabs = project.boardIDs.map { boardID in
            CiderTab.projectBoard(projectID: project.id, boardID: boardID, name: boardID)
        }

        let surfaceTabs = project.surfaces
            .filter { $0 != .boards && $0 != .milestones }
            .map { surface in
                CiderTab.projectSurface(projectID: project.id, surface: surface, name: surface.tabName)
            }

        var result: [CiderTab] = [
            .projectOverview(projectID: project.id, name: "Overview"),
            .projectInbox(projectID: project.id, name: "Inbox")
        ] + boardTabs + surfaceTabs

        for tab in allTabs where isCompatibilityTab(tab) && !result.contains(tab) {
            result.append(tab)
        }
        return result
    }

    private static func browseAllBoardTabs(
        for workspace: ProjectWorkspace,
        selectedTab: CiderTab?
    ) -> [CiderTab] {
        var result: [CiderTab] = [
            .projectOverview(projectID: workspace.id, name: "All Boards")
        ]

        guard case .projectBoard(let projectID, let boardID, let selectedName) = selectedTab,
              projectID == workspace.id,
              workspace.boardIDs.contains(boardID) else {
            return result
        }

        result.append(.projectBoard(projectID: workspace.id, boardID: boardID, name: selectedName))
        return result
    }

    private static func isCompatibilityTab(_ tab: CiderTab) -> Bool {
        if tab == .aiAssistant { return true }
        if case .search = tab { return true }
        if case .tag = tab { return true }
        if case .spaceOverview = tab { return true }
        if case .projectBoard = tab { return true }
        return false
    }

    private static func matches(
        _ tab: CiderTab,
        domain: WorkspaceNavigationDomain
    ) -> Bool {
        switch domain {
        case .mainDashboard:
            return false
        case .spaces:
            return false
        case .projects:
            if case .projectBoard = tab { return true }
            return false
        case .bookmarks, .notes, .tasksEvents, .files, .people, .browse:
            return false
        case .media, .aiAssistant:
            return false
        }
    }
}
