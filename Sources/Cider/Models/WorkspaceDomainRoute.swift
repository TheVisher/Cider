import Foundation

enum WorkspaceDomainRouteKind: String, CaseIterable, Hashable {
    case overview
    case inbox
    case folders
    case tags
    case recent
    case savedViews
    case chats
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
        case .browse:
            return [.overview, .folders, .tags, .recent, .savedViews]
        case .projects:
            return [.overview]
        case .aiAssistant:
            return [.overview, .chats]
        case .bookmarks:
            return [.overview, .inbox, .folders, .tags, .recent, .savedViews]
        case .tasksEvents:
            return [.overview, .inbox, .folders, .tags, .recent]
        case .media, .notes, .files, .people:
            return [.overview, .folders, .tags, .recent, .savedViews]
        }
    }

    private static func route(_ kind: WorkspaceDomainRouteKind) -> WorkspaceDomainRoute {
        switch kind {
        case .overview:
            return WorkspaceDomainRoute(kind: kind, title: "Overview", systemImage: "rectangle.3.group")
        case .inbox:
            return WorkspaceDomainRoute(kind: kind, title: "Inbox", systemImage: "tray")
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
        [
            .mainDashboard,
            .browse,
            .media,
            .bookmarks,
            .notes,
            .projects,
            .tasksEvents,
            .files,
            .people,
            .aiAssistant
        ]
    }
}
