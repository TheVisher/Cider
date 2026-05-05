import CoreGraphics
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

struct KanbanColumnCardNode: Identifiable, Equatable {
    let card: KanbanCard
    let depth: Int
    let sameColumnParentID: String?

    var id: String { card.id }
}

enum KanbanBoardLayout {
    static let archiveDividerWidth: CGFloat = 28

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

    static func hasArchiveColumns(in board: KanbanBoard) -> Bool {
        board.columns.contains { isArchiveColumn($0) }
    }

    static func archiveColumns(for laneRole: KanbanLaneRole, in board: KanbanBoard) -> [KanbanColumn] {
        board.columns.filter { column in
            isArchiveColumn(column) && role(for: column) == laneRole
        }
    }

    static func cardNodes(
        for column: KanbanColumn,
        in board: KanbanBoard,
        visibleCards: [KanbanCard]? = nil
    ) -> [KanbanColumnCardNode] {
        let cards = visibleCards ?? column.cards
        let visibleIDs = Set(cards.map(\.id))
        let sameColumnIDs = Set(column.cards.map(\.id))
        let sameColumnChildren = Dictionary(grouping: cards.filter { card in
            guard let parentID = card.parentCardID else { return false }
            return visibleIDs.contains(parentID) && sameColumnIDs.contains(parentID)
        }, by: { $0.parentCardID ?? "" })

        var renderedIDs = Set<String>()
        var nodes: [KanbanColumnCardNode] = []

        for card in cards {
            guard !renderedIDs.contains(card.id) else { continue }

            if let parentID = card.parentCardID,
               visibleIDs.contains(parentID),
               sameColumnIDs.contains(parentID) {
                continue
            }

            nodes.append(KanbanColumnCardNode(card: card, depth: 0, sameColumnParentID: nil))
            renderedIDs.insert(card.id)

            for child in sameColumnChildren[card.id] ?? [] where !renderedIDs.contains(child.id) {
                nodes.append(KanbanColumnCardNode(card: child, depth: 1, sameColumnParentID: card.id))
                renderedIDs.insert(child.id)
            }
        }

        return nodes
    }

    static func shouldPushArchive(
        activeColumnCount: Int,
        archiveColumnCount: Int,
        availableWidth: CGFloat,
        columnWidth: CGFloat,
        spacing: CGFloat,
        archiveExpanded: Bool
    ) -> Bool {
        guard archiveExpanded, archiveColumnCount > 0 else { return false }
        let activeWidth = columnGroupWidth(
            columnCount: activeColumnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )
        let archiveWidth = archiveRevealWidth(
            columnCount: archiveColumnCount,
            columnWidth: columnWidth,
            spacing: spacing
        )
        return activeWidth + spacing + archiveWidth > availableWidth
    }

    static func columnGroupWidth(columnCount: Int, columnWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return CGFloat(columnCount) * columnWidth
            + CGFloat(columnCount - 1) * spacing
    }

    static func archiveRevealWidth(columnCount: Int, columnWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        return archiveDividerWidth
            + CGFloat(columnCount) * columnWidth
            + CGFloat(columnCount) * spacing
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
