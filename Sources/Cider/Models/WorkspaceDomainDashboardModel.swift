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
        allTabs: [CiderTab],
        bookmarks: [Bookmark] = [],
        bookmarkFolders: [Folder] = []
    ) -> WorkspaceDomainDashboardModel {
        let compatibleTabs = WorkspaceContextualTabPolicy.tabs(
            for: domain,
            allTabs: allTabs
        )
        let items = compatibleTabs.compactMap { item(for: $0) }
        var sections = section(for: domain, items: items).map { [$0] } ?? []
        sections.append(contentsOf: domainInsightSections(
            for: domain,
            bookmarks: bookmarks,
            bookmarkFolders: bookmarkFolders
        ))
        let primaryAction = primaryAction(for: domain, firstItem: items.first)

        return WorkspaceDomainDashboardModel(
            domain: domain,
            title: domain.title,
            subtitle: domain.subtitle,
            systemImage: domain.systemImage,
            primaryAction: primaryAction,
            sections: sections,
            emptyStateTitle: "No \(domain.title) dashboard items yet",
            emptyStateSubtitle: "Use Library to see every tab, folder, and board while this domain gets richer."
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

    private static func domainInsightSections(
        for domain: WorkspaceNavigationDomain,
        bookmarks: [Bookmark],
        bookmarkFolders: [Folder]
    ) -> [WorkspaceDomainDashboardSection] {
        guard domain == .bookmarks, bookmarks.isEmpty == false else { return [] }

        let recentItems = bookmarks
            .sorted { lhs, rhs in lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.updatedAt > rhs.updatedAt }
            .prefix(6)
            .map { bookmarkItem($0, reason: "Recent capture") }

        let triageItems = bookmarks
            .filter { needsBookmarkTriage($0, folders: bookmarkFolders) }
            .sorted { lhs, rhs in lhs.createdAt != rhs.createdAt ? lhs.createdAt > rhs.createdAt : lhs.updatedAt > rhs.updatedAt }
            .prefix(6)
            .map { bookmarkItem($0, reason: "Needs routing or review") }

        let metadataItems = bookmarks
            .filter(needsBookmarkMetadata)
            .sorted { lhs, rhs in lhs.updatedAt > rhs.updatedAt }
            .prefix(6)
            .map { bookmarkItem($0, reason: "Needs enrichment metadata") }

        return [
            WorkspaceDomainDashboardSection(
                id: "bookmarks-recent",
                title: "Recent bookmarks",
                subtitle: "Fresh captures to revisit or route.",
                items: Array(recentItems)
            ),
            WorkspaceDomainDashboardSection(
                id: "bookmarks-triage",
                title: "Needs triage",
                subtitle: "Bookmarks still sitting in Inbox/Bookmarks or without a destination.",
                items: Array(triageItems)
            ),
            WorkspaceDomainDashboardSection(
                id: "bookmarks-metadata",
                title: "Needs metadata",
                subtitle: "Bookmarks missing summaries, enrichment, or preview metadata.",
                items: Array(metadataItems)
            )
        ].filter { $0.items.isEmpty == false }
    }

    private static func bookmarkItem(_ bookmark: Bookmark, reason: String) -> WorkspaceDomainDashboardItem {
        WorkspaceDomainDashboardItem(
            id: "bookmark-\(bookmark.id.uuidString)-\(reason.replacingOccurrences(of: " ", with: "-"))",
            title: bookmark.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? bookmark.hostDisplay : bookmark.title,
            subtitle: "\(reason) · \(bookmark.hostDisplay)",
            systemImage: bookmarkSystemImage(bookmark),
            target: nil
        )
    }

    private static func bookmarkSystemImage(_ bookmark: Bookmark) -> String {
        if bookmark.mediaType == .video { return "play.rectangle" }
        if bookmark.mediaType == .gif || bookmark.thumbnailRelativePath != nil || bookmark.thumbnailRemoteURLString != nil { return "photo" }
        return "link"
    }

    private static func needsBookmarkTriage(_ bookmark: Bookmark, folders: [Folder]) -> Bool {
        if bookmark.folderID == nil { return true }
        if let relativePath = bookmark.relativePath?.lowercased(), relativePath.hasPrefix("inbox/bookmarks") {
            return true
        }
        guard let folderID = bookmark.folderID else { return false }
        let folderPath = folderPath(for: folderID, folders: folders).lowercased()
        return folderPath == "bookmarks" || folderPath == "inbox/bookmarks" || folderPath.hasPrefix("inbox/bookmarks/")
    }

    private static func needsBookmarkMetadata(_ bookmark: Bookmark) -> Bool {
        let status = bookmark.enrichmentStatus?.lowercased()
        if status == nil || status == "none" || status == "partial" { return true }
        if bookmark.lastEnrichedAt == nil { return true }
        if bookmark.metadataUpdatedAt == nil { return true }
        if bookmark.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true { return true }
        return false
    }

    private static func folderPath(for folderID: UUID, folders: [Folder]) -> String {
        let foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        var names: [String] = []
        var currentID: UUID? = folderID
        var visited = Set<UUID>()

        while let id = currentID, let folder = foldersByID[id], visited.insert(id).inserted {
            names.insert(folder.name, at: 0)
            currentID = folder.parentID
        }

        return names.joined(separator: "/")
    }

    private static func sectionTitle(for domain: WorkspaceNavigationDomain) -> String {
        switch domain {
        case .mainDashboard: "Dashboard"
        case .spaces: "Spaces"
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
            title: "Open Library",
            systemImage: WorkspaceNavigationDomain.browse.systemImage,
            target: nil
        )
    }

    private static func item(for tab: CiderTab) -> WorkspaceDomainDashboardItem? {
        switch tab {
        case .domainDashboard, .spacesManager:
            return nil
        case .spaceOverview(_, let name):
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: name,
                subtitle: "Space overview",
                systemImage: tab.systemImage,
                target: tab
            )
        case .projectOverview(let projectID, let name):
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: name,
                subtitle: "\(projectID) project overview",
                systemImage: tab.systemImage,
                target: tab
            )
        case .projectInbox(let projectID, let name):
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: name,
                subtitle: "\(projectID) unread agent work and review queue",
                systemImage: tab.systemImage,
                target: tab
            )
        case .projectBoard(let projectID, _, let name):
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: name,
                subtitle: "\(projectID) Kanban board",
                systemImage: tab.systemImage,
                target: tab
            )
        case .projectSurface(let projectID, let surface, let name):
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: name,
                subtitle: "\(projectID) \(surface.title.localizedLowercase) workspace surface",
                systemImage: tab.systemImage,
                target: tab
            )
        case .projectReferences(let projectID, let name):
            return WorkspaceDomainDashboardItem(
                id: tab.id,
                title: name,
                subtitle: "\(projectID) references and inspiration",
                systemImage: tab.systemImage,
                target: tab
            )
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
        }
    }
}
