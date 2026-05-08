import Foundation

enum CiderTab: Identifiable, Hashable {
    case savedView(id: UUID, name: String)
    case search(id: UUID, query: String)
    case tag(id: UUID)
    case domainDashboard(WorkspaceNavigationDomain)
    case projectOverview(projectID: String, name: String)
    case projectReferences(projectID: String, name: String)
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
        case .projectReferences(let projectID, _): "project-references-\(projectID)"
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
        case .projectReferences(_, let name): name
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
        case .projectReferences: "photo.on.rectangle"
        case .aiAssistant: "sparkles"
        }
    }

    var savedViewID: UUID? {
        if case .savedView(let id, _) = self { return id }
        return nil
    }
}
