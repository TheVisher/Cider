import Foundation

enum WorkspaceDomainRouteKind: String, CaseIterable, Hashable {
    case overview
    case inbox
    case all
    case bookmarks
    case notes
    case files
    case folders
    case tags
    case recent
    case savedViews
    case chats

    var libraryEntityTypes: Set<LibraryEntityType>? {
        switch self {
        case .bookmarks:
            return [.bookmark]
        case .notes:
            return [.note]
        case .files:
            return [.vaultFile]
        case .overview, .inbox, .all, .folders, .tags, .recent, .savedViews, .chats:
            return nil
        }
    }
}

struct WorkspaceDomainRoute: Identifiable, Equatable {
    let kind: WorkspaceDomainRouteKind
    let title: String
    let systemImage: String

    var id: String { kind.rawValue }
}

enum WorkspaceDomainRoutePolicy {
    static func routes(for domain: WorkspaceNavigationDomain) -> [WorkspaceDomainRoute] {
        routeKinds(for: domain).map(route)
    }

    private static func routeKinds(for domain: WorkspaceNavigationDomain) -> [WorkspaceDomainRouteKind] {
        switch domain {
        case .mainDashboard:
            return []
        case .spaces:
            return []
        case .browse:
            return [.inbox, .all, .bookmarks, .notes, .files, .folders, .tags]
        case .projects:
            return []
        case .aiAssistant:
            return [.chats]
        case .bookmarks:
            return [.inbox, .folders, .tags, .recent, .savedViews]
        case .tasksEvents:
            return [.inbox]
        case .media, .people:
            return []
        case .notes, .files:
            return [.folders, .tags, .recent, .savedViews]
        }
    }

    private static func route(_ kind: WorkspaceDomainRouteKind) -> WorkspaceDomainRoute {
        switch kind {
        case .overview:
            return WorkspaceDomainRoute(kind: kind, title: "Overview", systemImage: "rectangle.3.group")
        case .inbox:
            return WorkspaceDomainRoute(kind: kind, title: "Inbox", systemImage: "tray")
        case .all:
            return WorkspaceDomainRoute(kind: kind, title: "All", systemImage: "square.grid.2x2")
        case .bookmarks:
            return WorkspaceDomainRoute(kind: kind, title: "Bookmarks", systemImage: "bookmark")
        case .notes:
            return WorkspaceDomainRoute(kind: kind, title: "Notes", systemImage: "note.text")
        case .files:
            return WorkspaceDomainRoute(kind: kind, title: "Files", systemImage: "doc.text")
        case .folders:
            return WorkspaceDomainRoute(kind: kind, title: "Folders", systemImage: "folder")
        case .tags:
            return WorkspaceDomainRoute(kind: kind, title: "Tags", systemImage: "tag")
        case .recent:
            return WorkspaceDomainRoute(kind: kind, title: "Recent", systemImage: "clock")
        case .savedViews:
            return WorkspaceDomainRoute(kind: kind, title: "Saved Views", systemImage: "rectangle.stack")
        case .chats:
            return WorkspaceDomainRoute(kind: kind, title: "Chats", systemImage: "bubble.left.and.bubble.right")
        }
    }
}

enum WorkspaceDomainSidebarModel {
    static func primaryDomains(selectedDomain: WorkspaceNavigationDomain?) -> [WorkspaceNavigationDomain] {
        primaryDomains(selectedDomain: selectedDomain, pinnedSpaces: [])
    }

    static func primaryDomains(
        selectedDomain: WorkspaceNavigationDomain?,
        pinnedSpaces: [CiderSpace]
    ) -> [WorkspaceNavigationDomain] {
        let domains: [WorkspaceNavigationDomain] = [
            .mainDashboard,
            .browse,
            .spaces,
            .projects,
            .tasksEvents,
            .people,
            .aiAssistant
        ]

        return domains
    }

    static func isDomainSelected(
        _ domain: WorkspaceNavigationDomain,
        selectedDomain: WorkspaceNavigationDomain?,
        selectedSpaceID: String?,
        isSpacesManagerSelected: Bool
    ) -> Bool {
        if domain == .mainDashboard {
            return selectedDomain == nil
                && selectedSpaceID == nil
                && !isSpacesManagerSelected
        }
        if domain == .spaces {
            return selectedDomain == .spaces
                || selectedSpaceID != nil
                || isSpacesManagerSelected
        }
        return selectedDomain == domain
    }
}

struct WorkspaceDomainSidebarExpansionState: Equatable {
    private(set) var expandedDomains: Set<WorkspaceNavigationDomain>

    init(expandedDomains: Set<WorkspaceNavigationDomain> = []) {
        self.expandedDomains = expandedDomains.filter(Self.isExpandable)
    }

    mutating func toggle(_ domain: WorkspaceNavigationDomain) {
        guard Self.isExpandable(domain) else { return }
        if expandedDomains.contains(domain) {
            expandedDomains.remove(domain)
        } else {
            expandedDomains.insert(domain)
        }
    }

    mutating func expand(_ domain: WorkspaceNavigationDomain) {
        guard Self.isExpandable(domain) else { return }
        expandedDomains.insert(domain)
    }

    mutating func expandAll(in domains: [WorkspaceNavigationDomain]) {
        expandedDomains = Set(domains.filter(Self.isExpandable))
    }

    mutating func collapseAll() {
        expandedDomains.removeAll()
    }

    func isExpanded(_ domain: WorkspaceNavigationDomain) -> Bool {
        expandedDomains.contains(domain)
    }

    private static func isExpandable(_ domain: WorkspaceNavigationDomain) -> Bool {
        domain != .mainDashboard
    }
}
