import CoreGraphics
import Foundation

struct KanbanCardFaceChip: Equatable {
    enum Activation: Equatable {
        case none
        case tagEditor
        case featureDomainFilter(String)
    }

    enum Role: Equatable {
        case tagEdit
        case featureDomain
        case typeStatus
    }

    enum Accessory: Equatable {
        case none
        case featureIcon
        case colorDot
    }

    enum Surface: Equatable {
        case muted
    }

    let label: String
    let role: Role
    let accessory: Accessory
    let surface: Surface

    var showsDisclosureIndicator: Bool { false }

    var activation: Activation {
        switch role {
        case .tagEdit:
            return .tagEditor
        case .featureDomain:
            return .featureDomainFilter(KanbanCardTagTaxonomy.normalized(label))
        case .typeStatus:
            return .none
        }
    }

    var iconSystemName: String? {
        switch accessory {
        case .none, .colorDot:
            return nil
        case .featureIcon:
            return "cube.transparent"
        }
    }
}

struct KanbanFeatureDomainFilter: Identifiable, Equatable {
    let id: String
    let label: String
    let cardCount: Int
}

private struct KanbanFeatureDomainDefinition: Equatable {
    let id: String
    let label: String
    let aliases: Set<String>

    func matches(_ tag: String) -> Bool {
        id == tag || aliases.contains(tag)
    }
}

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

    static var featureDomainCatalog: [KanbanFeatureDomainFilter] {
        featureDomainDefinitions.map { definition in
            KanbanFeatureDomainFilter(id: definition.id, label: definition.label, cardCount: 0)
        }
    }

    static func usesProjectLayout(for board: KanbanBoard) -> Bool {
        let normalizedBoardName = normalize(board.name)
        if ["cider", "cider_web", "cider_ios"].contains(normalizedBoardName) {
            return true
        }

        if board.columns.count >= 6 {
            return true
        }

        return board.columns.contains { isHiddenColumn($0) }
    }

    static func lanes(for board: KanbanBoard) -> [KanbanBoardLane] {
        let activeColumns = board.columns.filter { !isHiddenColumn($0) }

        guard !activeColumns.isEmpty else {
            return []
        }

        return [KanbanBoardLane(role: .workflow, columns: activeColumns)]
    }

    static func visibleColumns(in board: KanbanBoard) -> [KanbanColumn] {
        board.columns.filter { !isHiddenColumn($0) }
    }

    static func hasArchiveColumns(in board: KanbanBoard) -> Bool {
        board.columns.contains { isArchiveColumn($0) }
    }

    static func archiveColumns(for laneRole: KanbanLaneRole, in board: KanbanBoard) -> [KanbanColumn] {
        guard laneRole == .workflow else { return [] }
        return board.columns.filter { column in
            isArchiveColumn(column)
        }
    }

    static func hasHiddenColumns(in board: KanbanBoard) -> Bool {
        board.columns.contains { isHiddenColumn($0) }
    }

    static func hiddenColumns(in board: KanbanBoard) -> [KanbanColumn] {
        board.columns.filter { isHiddenColumn($0) }
    }

    static func projectColumnHeight(
        availableBoardHeight: CGFloat,
        showsScrollControls: Bool
    ) -> CGFloat {
        let reservedHeight =
            (Spacing.lg * 2) +
            (Spacing.sm * 2) +
            22 +
            Spacing.sm +
            (showsScrollControls ? (Spacing.xs + KanbanDesign.projectHorizontalScrollControlHeight) : 0)
        return max(availableBoardHeight - reservedHeight, 0)
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

    static func cardFacePreviewText(for card: KanbanCard) -> String? {
        nil
    }

    static func cardFaceSemanticChips(for card: KanbanCard, limit: Int = 3) -> [String] {
        cardFaceSemanticChipModels(for: card, limit: limit).map(\.label)
    }

    static func cardFaceChips(for card: KanbanCard, limit: Int = Int.max) -> [KanbanCardFaceChip] {
        let semanticChips = cardFaceSemanticChipModels(for: card, limit: limit)
        return [KanbanCardFaceChip(label: "…", role: .tagEdit, accessory: .none, surface: .muted)] + semanticChips
    }

    static func cardFaceOverflowTags(for card: KanbanCard, limit: Int = 8) -> [KanbanCardFaceChip] {
        cardFaceSemanticChipModels(for: card, limit: limit)
    }

    static func featureDomainFilters(for board: KanbanBoard) -> [KanbanFeatureDomainFilter] {
        var cardIDsByFeature: [String: Set<String>] = [:]

        for column in board.columns {
            for card in column.cards {
                for feature in featureDomainTags(for: card) {
                    cardIDsByFeature[feature, default: []].insert(card.id)
                }
            }
        }

        return featureDomainDefinitions.compactMap { definition in
            guard let cardIDs = cardIDsByFeature[definition.id], !cardIDs.isEmpty else { return nil }
            return KanbanFeatureDomainFilter(
                id: definition.id,
                label: definition.label,
                cardCount: cardIDs.count
            )
        }
    }

    static func cards(_ cards: [KanbanCard], matchingFeatureDomainFilter filter: String?) -> [KanbanCard] {
        let normalizedFilter = KanbanCardTagTaxonomy.normalized(filter ?? "")
        guard !normalizedFilter.isEmpty else { return cards }
        let canonicalFilter = canonicalFeatureDomain(for: normalizedFilter)?.id ?? normalizedFilter
        return cards.filter { featureDomainTags(for: $0).contains(canonicalFilter) }
    }

    private static func cardFaceSemanticChipModels(for card: KanbanCard, limit: Int = 3) -> [KanbanCardFaceChip] {
        guard limit > 0 else { return [] }
        let priorityLabels = Set(KanbanPriority.allCases.map { $0.rawValue })
        var seen: Set<String> = []
        var featureDomainChips: [KanbanCardFaceChip] = []
        var typeStatusChips: [KanbanCardFaceChip] = []

        for tag in card.tags {
            let normalized = KanbanCardTagTaxonomy.normalized(tag)
            guard !normalized.isEmpty, !priorityLabels.contains(normalized) else {
                continue
            }
            let feature = canonicalFeatureDomain(for: normalized)
            guard feature != nil || typeStatusTags.contains(normalized) || KanbanCardTagTaxonomy.isCoreTag(normalized) else {
                continue
            }
            let dedupeKey = feature?.id ?? normalized
            guard seen.insert(dedupeKey).inserted else { continue }
            let role = cardFaceChipRole(for: normalized)
            let chip = KanbanCardFaceChip(
                label: feature?.label ?? displayChipLabel(for: normalized),
                role: role,
                accessory: cardFaceChipAccessory(for: role),
                surface: .muted
            )
            switch role {
            case .featureDomain:
                featureDomainChips.append(chip)
            case .typeStatus:
                typeStatusChips.append(chip)
            case .tagEdit:
                break
            }
        }

        return Array((featureDomainChips + typeStatusChips).prefix(limit))
    }

    private static func featureDomainTags(for card: KanbanCard) -> [String] {
        let priorityLabels = Set(KanbanPriority.allCases.map { $0.rawValue })
        var seen: Set<String> = []
        var features: [String] = []

        for tag in card.tags {
            let normalized = KanbanCardTagTaxonomy.normalized(tag)
            guard !normalized.isEmpty,
                  !priorityLabels.contains(normalized),
                  let feature = canonicalFeatureDomain(for: normalized),
                  seen.insert(feature.id).inserted else {
                continue
            }
            features.append(feature.id)
        }

        return features
    }

    private static func cardFaceChipRole(for tag: String) -> KanbanCardFaceChip.Role {
        if canonicalFeatureDomain(for: tag) != nil {
            return .featureDomain
        }
        return .typeStatus
    }

    private static func canonicalFeatureDomain(for tag: String) -> KanbanFeatureDomainDefinition? {
        guard !typeStatusTags.contains(tag), !KanbanCardTagTaxonomy.isCoreTag(tag) else { return nil }
        return featureDomainDefinitions.first { $0.matches(tag) }
    }

    private static func cardFaceChipAccessory(for role: KanbanCardFaceChip.Role) -> KanbanCardFaceChip.Accessory {
        switch role {
        case .tagEdit:
            return .none
        case .featureDomain:
            return .featureIcon
        case .typeStatus:
            return .colorDot
        }
    }

    // Linear-style board scoping: keep the visible filter surface to a few stable
    // product domains. Card-local labels can be narrower, but they roll up here
    // instead of becoming dozens of primary board filters.
    private static let featureDomainDefinitions: [KanbanFeatureDomainDefinition] = [
        KanbanFeatureDomainDefinition(id: "kanban", label: "Kanban", aliases: [
            "board", "boards", "card", "cards", "comments", "parent-child", "archive", "workflow"
        ]),
        KanbanFeatureDomainDefinition(id: "second-brain", label: "Second Brain", aliases: [
            "dashboard", "home", "projects", "project-inbox", "agenda", "todos", "reminders"
        ]),
        KanbanFeatureDomainDefinition(id: "capture", label: "Capture", aliases: [
            "bookmarks", "bookmark", "enrichment", "clipboard", "scanner", "routing"
        ]),
        KanbanFeatureDomainDefinition(id: "library", label: "Library", aliases: [
            "spaces", "space", "folders", "domains", "media", "references"
        ]),
        KanbanFeatureDomainDefinition(id: "ai-assistant", label: "AI Assistant", aliases: [
            "agents", "agent", "ai", "hermes", "handoffs", "automation", "life-assistant"
        ]),
        KanbanFeatureDomainDefinition(id: "apps", label: "Apps", aliases: [
            "cider-web", "web", "cider-ios", "ios", "app-parity"
        ]),
        KanbanFeatureDomainDefinition(id: "interface", label: "Interface", aliases: [
            "ux", "ui", "navigation", "sidebar", "tabs", "layout", "design-system"
        ]),
        KanbanFeatureDomainDefinition(id: "infrastructure", label: "Infrastructure", aliases: [
            "cli", "storage", "backend", "sqlite", "sync", "duplicates", "vault-doctor", "migration", "indexing", "search", "recall"
        ]),
    ]

    private static let typeStatusTags: Set<String> = [
        "idea",
        "performance",
        "test",
        "testing",
        "qa",
        "review",
        "needs-qa",
        "manual-qa",
        "agent-can-verify",
        "agent-report",
        "new",
        "inbox",
        "blocked",
        "done",
        "fixed",
    ]

    private static func displayChipLabel(for tag: String) -> String {
        tag.split(separator: "-")
            .map { part in
                let lowercased = part.lowercased()
                if lowercased == "ios" { return "iOS" }
                if lowercased == "qa" { return "QA" }
                guard let first = part.first else { return "" }
                return first.uppercased() + part.dropFirst()
            }
            .joined(separator: " ")
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

    private static func isHiddenColumn(_ column: KanbanColumn) -> Bool {
        column.hiddenColumnState ?? isArchiveColumn(column)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }
}
