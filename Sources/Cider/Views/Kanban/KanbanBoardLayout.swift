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
    let visualIndex: Int

    var id: String { card.id }
}

struct KanbanColumnCardGroup: Identifiable, Equatable {
    let parent: KanbanColumnCardNode
    let children: [KanbanColumnCardNode]
    let sameColumnChildCount: Int

    var id: String { parent.id }
    var renderID: String {
        ([parent.card.id] + children.map(\.card.id)).joined(separator: "|")
    }
}

struct KanbanColumnChildCount: Equatable {
    let columnID: String
    let columnName: String
    let count: Int
}

struct KanbanParentChildSummary: Equatable {
    let totalCount: Int
    let doneCount: Int
    let columnCounts: [KanbanColumnChildCount]

    var compactText: String {
        var pieces = [
            "\(totalCount) \(totalCount == 1 ? "child" : "children")"
        ]
        pieces.append(contentsOf: columnCounts.map { "\($0.count) \($0.columnName)" })
        if doneCount > 0 {
            pieces.append("\(doneCount)/\(totalCount) done")
        }
        return pieces.joined(separator: " · ")
    }
}

struct KanbanParentBadge: Equatable {
    let parentID: String
    let title: String
    let accentColor: KanbanCardColor?
}

struct KanbanPlanIndicator: Equatable {
    let parentID: String
    let title: String
    let stepNumber: Int
    let stepCount: Int
    let accentColor: KanbanCardColor?
    let isNextUp: Bool

    var compactText: String {
        let stepText = "Step \(stepNumber)/\(stepCount)"
        return isNextUp ? "Next Up · \(stepText)" : stepText
    }
}

struct KanbanTestingOwnerBadge: Equatable {
    enum Kind: Equatable {
        case needsErik
        case agentCanVerify
    }

    let text: String
    let kind: Kind
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

        func appendNode(_ card: KanbanCard, depth: Int, sameColumnParentID: String?) {
            guard !renderedIDs.contains(card.id) else { return }

            nodes.append(KanbanColumnCardNode(
                card: card,
                depth: depth,
                sameColumnParentID: sameColumnParentID,
                visualIndex: nodes.count
            ))
            renderedIDs.insert(card.id)

            for child in sameColumnChildren[card.id] ?? [] {
                appendNode(child, depth: depth + 1, sameColumnParentID: card.id)
            }
        }

        for card in cards {
            guard !renderedIDs.contains(card.id) else { continue }

            if let parentID = card.parentCardID,
               visibleIDs.contains(parentID),
               sameColumnIDs.contains(parentID) {
                continue
            }

            appendNode(card, depth: 0, sameColumnParentID: nil)
        }

        return nodes
    }

    static func cardGroups(
        for column: KanbanColumn,
        in board: KanbanBoard,
        visibleCards: [KanbanCard]? = nil,
        collapsedParentIDs: Set<String> = []
    ) -> [KanbanColumnCardGroup] {
        let nodes = cardNodes(for: column, in: board, visibleCards: visibleCards)
        var groups: [KanbanColumnCardGroup] = []
        var index = 0

        while index < nodes.count {
            let parent = nodes[index]
            var children: [KanbanColumnCardNode] = []
            var nextIndex = index + 1

            while nextIndex < nodes.count,
                  nodes[nextIndex].depth > parent.depth {
                children.append(nodes[nextIndex])
                nextIndex += 1
            }

            groups.append(KanbanColumnCardGroup(
                parent: parent,
                children: collapsedParentIDs.contains(parent.card.id) ? [] : children,
                sameColumnChildCount: children.count
            ))
            index = nextIndex
        }

        return groups
    }

    static func childSummary(for parentID: String, in board: KanbanBoard) -> KanbanParentChildSummary? {
        var totalCount = 0
        var doneCount = 0
        var columnCounts: [KanbanColumnChildCount] = []

        for column in board.columns {
            let children = column.cards.filter { $0.parentCardID == parentID }
            guard !children.isEmpty else { continue }

            totalCount += children.count
            if column.isDoneColumn {
                doneCount += children.count
            } else {
                doneCount += children.filter { $0.completed != nil }.count
            }
            columnCounts.append(KanbanColumnChildCount(
                columnID: column.id,
                columnName: column.name,
                count: children.count
            ))
        }

        guard totalCount > 0 else { return nil }
        return KanbanParentChildSummary(
            totalCount: totalCount,
            doneCount: doneCount,
            columnCounts: columnCounts
        )
    }

    static func inheritedParentAccentColor(for card: KanbanCard, in board: KanbanBoard) -> KanbanCardColor? {
        guard let parent = board.parentCard(for: card.id) else { return nil }
        return cardAccentColor(for: parent, in: board)
    }

    static func cardAccentColor(for card: KanbanCard, in board: KanbanBoard) -> KanbanCardColor? {
        if card.parentCardID != nil || !board.childCards(of: card.id).isEmpty {
            return familyAccentColor(for: card, in: board)
        }

        return card.color
    }

    static func parentBadge(
        for card: KanbanCard,
        in column: KanbanColumn,
        board: KanbanBoard
    ) -> KanbanParentBadge? {
        guard let parent = board.parentCard(for: card.id) else { return nil }
        let parentIsInSameColumn = column.cards.contains { $0.id == parent.id }
        guard !parentIsInSameColumn else { return nil }

        return KanbanParentBadge(
            parentID: parent.id,
            title: parent.title,
            accentColor: cardAccentColor(for: parent, in: board)
        )
    }

    static func testingOwnerBadge(for card: KanbanCard) -> KanbanTestingOwnerBadge? {
        let normalizedTags = Set(card.tags.map(normalize))
        if normalizedTags.contains("needs_erik") || normalizedTags.contains("manual_qa") {
            return KanbanTestingOwnerBadge(text: "Needs Erik", kind: .needsErik)
        }
        if normalizedTags.contains("agent_can_verify") {
            return KanbanTestingOwnerBadge(text: "Agent can verify", kind: .agentCanVerify)
        }
        return nil
    }

    static func planIndicator(for card: KanbanCard, in board: KanbanBoard) -> KanbanPlanIndicator? {
        guard let parent = board.parentCard(for: card.id) else { return nil }

        let siblings = board.childCards(of: parent.id)
        guard let stepIndex = siblings.firstIndex(where: { $0.id == card.id }) else { return nil }
        let nextUpCardID = siblings.first { child in
            !isDone(child, in: board)
        }?.id

        return KanbanPlanIndicator(
            parentID: parent.id,
            title: parent.title,
            stepNumber: stepIndex + 1,
            stepCount: siblings.count,
            accentColor: cardAccentColor(for: parent, in: board),
            isNextUp: nextUpCardID == card.id
        )
    }

    static func previewText(for card: KanbanCard) -> String? {
        if let summary = trimmedNonEmpty(card.aiSummary) {
            return summary
        }

        return trimmedNonEmpty(card.notes)
    }

    private static func trimmedNonEmpty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isDone(_ card: KanbanCard, in board: KanbanBoard) -> Bool {
        if card.completed != nil {
            return true
        }

        guard let columnID = board.columnID(containing: card.id),
              let column = board.columns.first(where: { $0.id == columnID }) else {
            return false
        }

        return column.isDoneColumn
    }

    private static func familyAccentColor(for card: KanbanCard, in board: KanbanBoard) -> KanbanCardColor {
        if let ancestorColor = explicitAncestorColor(for: card, in: board) {
            return ancestorColor
        }

        if let color = card.color {
            return color
        }

        return parentAccentColor(for: familyRoot(for: card, in: board))
    }

    static func hierarchyConnectorAccentColor(for parent: KanbanCard, in board: KanbanBoard) -> KanbanCardColor? {
        cardAccentColor(for: parent, in: board)
    }

    private static func explicitAncestorColor(for card: KanbanCard, in board: KanbanBoard) -> KanbanCardColor? {
        var inheritedColor: KanbanCardColor?
        var visited = Set([card.id])
        var nextParentID = card.parentCardID

        while let parentID = nextParentID,
              let parent = board.card(id: parentID),
              visited.insert(parent.id).inserted {
            if let color = parent.color {
                inheritedColor = color
            }
            nextParentID = parent.parentCardID
        }

        return inheritedColor
    }

    private static func familyRoot(for card: KanbanCard, in board: KanbanBoard) -> KanbanCard {
        var root = card
        var visited = Set([card.id])
        var nextParentID = card.parentCardID

        while let parentID = nextParentID,
              let parent = board.card(id: parentID),
              visited.insert(parent.id).inserted {
            root = parent
            nextParentID = parent.parentCardID
        }

        return root
    }

    private static func parentAccentColor(for parent: KanbanCard) -> KanbanCardColor {
        if let color = parent.color {
            return color
        }

        let colors = KanbanCardColor.allCases
        let stableIndex = parent.id.utf8.reduce(0) { partial, byte in
            (partial + Int(byte)) % colors.count
        }
        return colors[stableIndex]
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
