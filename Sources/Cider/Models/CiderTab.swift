import Foundation

enum CiderTab: Identifiable, Hashable {
    case home
    case bookmarks
    case notes
    case savedView(id: UUID, name: String)
    case search(id: UUID, query: String)
    case project(id: UUID, name: String)

    static func == (lhs: CiderTab, rhs: CiderTab) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var id: String {
        switch self {
        case .home: "home"
        case .bookmarks: "bookmarks"
        case .notes: "notes"
        case .savedView(let id, _): "saved-\(id.uuidString)"
        case .search(let id, _): "search-\(id.uuidString)"
        case .project(let id, _): "project-\(id.uuidString)"
        }
    }

    var displayName: String {
        switch self {
        case .home: "Home"
        case .bookmarks: "Bookmarks"
        case .notes: "Notes"
        case .savedView(_, let name): name
        case .search(_, let query): query.isEmpty ? "Search" : query
        case .project(_, let name): name
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .bookmarks: "bookmark"
        case .notes: "note.text"
        case .savedView: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .project: "tray.full"
        }
    }

    var isFixed: Bool {
        switch self {
        case .home, .bookmarks, .notes: true
        case .savedView, .search, .project: false
        }
    }

    var isCloseable: Bool {
        !isFixed
    }

    var projectID: UUID? {
        if case .project(let id, _) = self { return id }
        return nil
    }

    var savedViewID: UUID? {
        if case .savedView(let id, _) = self { return id }
        return nil
    }

    static let fixedTabs: [CiderTab] = [.home, .bookmarks, .notes]
}
