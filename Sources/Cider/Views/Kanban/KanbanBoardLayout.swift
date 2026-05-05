import Foundation

enum KanbanLaneRole: String, CaseIterable {
    case workflow
    case qa
    case other

    var title: String {
        switch self {
        case .workflow: "Workflow"
        case .qa: "QA"
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

        return board.columns.contains { isArchiveColumn($0) }
    }

    static func lanes(for board: KanbanBoard) -> [KanbanBoardLane] {
        let activeColumns = board.columns.filter { !isArchiveColumn($0) }
        let workflowColumns = activeColumns.filter { role(for: $0) == .workflow }
        let qaColumns = activeColumns.filter { role(for: $0) == .qa }

        guard !workflowColumns.isEmpty || !qaColumns.isEmpty else {
            return []
        }

        return [
            KanbanBoardLane(role: .workflow, columns: workflowColumns),
            KanbanBoardLane(role: .qa, columns: qaColumns)
        ].filter { !$0.columns.isEmpty }
    }

    static func role(for column: KanbanColumn) -> KanbanLaneRole {
        let normalized = normalize("\(column.id) \(column.name)")

        if containsAny(normalized, ["testing"]) {
            return .workflow
        }

        if containsAny(normalized, ["qa", "quality", "bug", "bugs", "fix", "fixed", "fixes", "investigating", "ready_to_test", "verified"]) {
            return .qa
        }

        return .workflow
    }

    private static func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private static func isArchiveColumn(_ column: KanbanColumn) -> Bool {
        let normalized = normalize("\(column.id) \(column.name)")
        return containsAny(normalized, ["archive", "archived"])
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
