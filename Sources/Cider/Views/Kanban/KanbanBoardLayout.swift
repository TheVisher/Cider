import Foundation

enum KanbanLaneRole: String, CaseIterable {
    case discovery
    case build
    case quality
    case done
    case other

    var title: String {
        switch self {
        case .discovery: "Discovery"
        case .build: "Build"
        case .quality: "Quality"
        case .done: "Done"
        case .other: "Other"
        }
    }
}

struct KanbanBoardLane: Identifiable, Equatable {
    let role: KanbanLaneRole
    let columns: [KanbanColumn]

    var id: String { role.rawValue }
    var title: String { role.title }
    var cardCount: Int { columns.reduce(0) { $0 + $1.cards.count } }
}

enum KanbanBoardLayout {
    static func usesProjectLayout(for board: KanbanBoard) -> Bool {
        let normalizedBoardName = normalize(board.name)
        if ["cider", "cider_web", "cider_ios"].contains(normalizedBoardName) {
            return true
        }

        if board.columns.count >= 6 {
            return true
        }

        let roles = Set(board.columns.map(role(for:)))
        return roles.count >= 4
    }

    static func lanes(for board: KanbanBoard) -> [KanbanBoardLane] {
        let grouped = Dictionary(grouping: board.columns, by: role(for:))
        return KanbanLaneRole.allCases.compactMap { role in
            guard let columns = grouped[role], !columns.isEmpty else { return nil }
            return KanbanBoardLane(role: role, columns: columns)
        }
    }

    static func role(for column: KanbanColumn) -> KanbanLaneRole {
        if column.isDoneColumn {
            return .done
        }

        let normalized = normalize("\(column.id) \(column.name)")

        if containsAny(normalized, ["archive", "archived", "complete", "completed", "done"]) {
            return .done
        }

        if containsAny(normalized, ["test", "testing", "qa", "quality", "bug", "bugs", "fix", "fixed", "fixes", "ready_to_test", "investigating", "verified"]) {
            return .quality
        }

        if containsAny(normalized, ["progress", "implement", "implementation", "build", "coding", "review", "active"]) {
            return .build
        }

        if containsAny(normalized, ["idea", "ideas", "backlog", "discovery", "shaping", "ready", "next", "planned"]) {
            return .discovery
        }

        return .other
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
