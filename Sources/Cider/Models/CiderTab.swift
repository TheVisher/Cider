import Foundation

enum CiderTab: Identifiable, Hashable {
    case savedView(id: UUID, name: String)
    case search(id: UUID, query: String)
    case tag(id: UUID)

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
        }
    }

    var displayName: String {
        switch self {
        case .savedView(_, let name): name
        case .search(_, let query): query.isEmpty ? "Search" : query
        case .tag: "Tags"
        }
    }

    var systemImage: String {
        switch self {
        case .savedView: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .tag: "tag"
        }
    }

    var savedViewID: UUID? {
        if case .savedView(let id, _) = self { return id }
        return nil
    }
}
