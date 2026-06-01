import Foundation

enum CiderTab: Identifiable, Hashable {
    case savedView(id: UUID, name: String)
    case search(id: UUID, query: String)
    case tag(id: UUID)
    case domainDashboard(WorkspaceNavigationDomain)
    case projectOverview(projectID: String, name: String)
    case projectInbox(projectID: String, name: String)
    case projectBoard(projectID: String, boardID: String, name: String)
    case projectSurface(projectID: String, surface: ProjectWorkspaceSurface, name: String)
    case projectReferences(projectID: String, name: String)
    case spaceOverview(id: String, name: String)
    case spacesManager
    case aiAssistant

    static func == (lhs: CiderTab, rhs: CiderTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String {
        switch self {
        case .savedView(let id, _): "saved-\(id.uuidString)"
        case .search(let id, _): "search-\(id.uuidString)"
        case .tag(let id): "tag-\(id.uuidString)"
        case .domainDashboard(let domain): "domain-dashboard-\(domain.rawValue)"
        case .projectOverview(let projectID, _): "project-overview-\(projectID)"
        case .projectInbox(let projectID, _): "project-inbox-\(projectID)"
        case .projectBoard(let projectID, let boardID, _): "project-board-\(projectID)-\(boardID)"
        case .projectSurface(let projectID, let surface, _): "project-surface-\(projectID)-\(surface.id)"
        case .projectReferences(let projectID, _): "project-references-\(projectID)"
        case .spaceOverview(let id, _): "space-overview-\(id)"
        case .spacesManager: "spaces-manager"
        case .aiAssistant: "aiAssistant"
        }
    }

    var displayName: String {
        switch self {
        case .savedView(_, let name): name
        case .search(_, let query): query.isEmpty ? "Search" : query
        case .tag: "Tags"
        case .domainDashboard(let domain): "\(domain.title) Dashboard"
        case .projectOverview(_, let name): name
        case .projectInbox(_, let name): name
        case .projectBoard(_, _, let name): name
        case .projectSurface(_, _, let name): name
        case .projectReferences(_, let name): name
        case .spaceOverview(_, let name): name
        case .spacesManager: "All Spaces"
        case .aiAssistant: "AI Assistant"
        }
    }

    var systemImage: String {
        switch self {
        case .savedView: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .tag: "tag"
        case .domainDashboard(let domain): domain.systemImage
        case .projectOverview: "rectangle.3.group"
        case .projectInbox: "tray.full"
        case .projectBoard: "rectangle.split.3x1"
        case .projectSurface(_, let surface, _): surface.systemImage
        case .projectReferences: "photo.on.rectangle"
        case .spaceOverview: "square.grid.2x2"
        case .spacesManager: "square.grid.2x2"
        case .aiAssistant: "sparkles"
        }
    }

    var savedViewID: UUID? {
        if case .savedView(let id, _) = self { return id }
        return nil
    }
}
