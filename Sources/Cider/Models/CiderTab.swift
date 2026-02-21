import Foundation

enum CiderTab: Identifiable, Hashable {
    case home
    case savedView(id: UUID, name: String)
    case search(id: UUID, query: String)
    // NOTE: .project case removed — Projects UI stripped. ProjectStorage kept dormant.
    case externalSource(id: UUID, name: String)

    static func == (lhs: CiderTab, rhs: CiderTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String {
        switch self {
        case .home: "home"
        case .savedView(let id, _): "saved-\(id.uuidString)"
        case .search(let id, _): "search-\(id.uuidString)"
        case .externalSource(let id, _): "source-\(id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .home: "Home"
        case .savedView(_, let name): name
        case .search(_, let query): query.isEmpty ? "Search" : query
        case .externalSource(_, let name): name
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .savedView: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .externalSource: "folder.badge.gear"
        }
    }

    var isFixed: Bool {
        switch self {
        case .home: true
        case .savedView, .search, .externalSource: false
        }
    }

    var isCloseable: Bool {
        !isFixed
    }

    var savedViewID: UUID? {
        if case .savedView(let id, _) = self { return id }
        return nil
    }

    var sourceID: UUID? {
        if case .externalSource(let id, _) = self { return id }
        return nil
    }

    static let fixedTabs: [CiderTab] = [.home]
}
