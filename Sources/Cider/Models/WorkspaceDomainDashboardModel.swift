import Foundation

struct WorkspaceDomainDashboardModel: Equatable {
    let domain: WorkspaceNavigationDomain
    let title: String
    let subtitle: String
    let systemImage: String
    let primaryAction: WorkspaceDomainDashboardAction?
    let sections: [WorkspaceDomainDashboardSection]
    let emptyStateTitle: String
    let emptyStateSubtitle: String
}

struct WorkspaceDomainDashboardSection: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let items: [WorkspaceDomainDashboardItem]
}

struct WorkspaceDomainDashboardItem: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let target: CiderTab?
}

struct WorkspaceDomainDashboardAction: Equatable {
    let title: String
    let systemImage: String
    let target: CiderTab?
}

enum WorkspaceDomainDashboardProvider {
    static func model(
        for domain: WorkspaceNavigationDomain,
        savedViews: [SavedView],
        allTabs: [CiderTab]
    ) -> WorkspaceDomainDashboardModel {
        let compatibleTabs = WorkspaceContextualTabPolicy.tabs(
            for: domain,
            allTabs: allTabs,
            savedViews: savedViews
        )
        let items = compatibleTabs.compactMap { item(for: $0, savedViews: savedViews) }
        let section = section(for: domain, items: items)
        let primaryAction = primaryAction(for: domain, firstItem: items.first)

        return WorkspaceDomainDashboardModel(
            domain: domain,
            title: domain.title,
            subtitle: domain.subtitle,
            systemImage: domain.systemImage,
            primaryAction: primaryAction,
            sections: section.map { [$0] } ?? [],
            emptyStateTitle: "No \(domain.title) dashboard items yet",
            emptyStateSubtitle: "Use Browse to see every tab, folder, saved view, and board while this domain gets richer."
        )
    }

    private static func section(
        for domain: WorkspaceNavigationDomain,
        items: [WorkspaceDomainDashboardItem]
    ) -> WorkspaceDomainDashboardSection? {
        guard items.isEmpty == false else { return nil }
        return WorkspaceDomainDashboardSection(
            id: domain.id,
            title: sectionTitle(for: domain),
            subtitle: nil,
            items: items
        )
    }

    private static func sectionTitle(for domain: WorkspaceNavigationDomain) -> String {
        switch domain {
        case .mainDashboard: "Dashboard"
        case .media: "Media views"
        case .bookmarks: "Bookmark views"
        case .notes: "Note views"
        case .projects: "Project boards"
        case .tasksEvents: "Tasks and events"
        case .files: "File views"
        case .people: "People views"
        case .aiAssistant: "Assistant"
        case .browse: "All open views"
        }
    }

    private static func primaryAction(
        for domain: WorkspaceNavigationDomain,
        firstItem: WorkspaceDomainDashboardItem?
    ) -> WorkspaceDomainDashboardAction? {
        if let firstItem, let target = firstItem.target {
            return WorkspaceDomainDashboardAction(
                title: "Open \(firstItem.title)",
                systemImage: firstItem.systemImage,
                target: target
            )
        }
        guard domain != .browse else { return nil }
        return WorkspaceDomainDashboardAction(
            title: "Browse all Cider",
            systemImage: WorkspaceNavigationDomain.browse.systemImage,
            target: nil
        )
    }

    private static func item(
        for tab: CiderTab,
        savedViews: [SavedView]
    ) -> WorkspaceDomainDashboardItem? {
        switch tab {
        case .aiAssistant:
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: tab.displayName,
                subtitle: "Ask questions and run agent workflows",
                systemImage: "sparkles",
                target: tab
            )
        case .search:
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: tab.displayName,
                subtitle: "Search results",
                systemImage: "magnifyingglass",
                target: tab
            )
        case .tag:
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: tab.displayName,
                subtitle: "Tags and labels",
                systemImage: "tag",
                target: tab
            )
        case .savedView(let id, let title):
            let savedView = savedViews.first(where: { $0.id == id })
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: title,
                subtitle: savedView?.kind.systemImage == nil ? nil : savedView?.name,
                systemImage: savedView?.kind.systemImage ?? "square.grid.2x2",
                target: tab
            )
        }
    }
}
