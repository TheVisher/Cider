import Foundation

enum StackSortMode: String, Codable, CaseIterable, Hashable {
    case attention
    case time
}

enum StackSummaryModule: String, Codable, CaseIterable, Hashable {
    case none
    case bills
}

enum StackMatchCondition: String, Codable, CaseIterable, Hashable {
    case hasDate
    case isIncomplete
    case hasLabel
    case entityType
}

struct StackMatchRule: Codable, Hashable {
    var condition: StackMatchCondition
    /// Condition argument:
    /// - `hasLabel`: label UUID string
    /// - `entityType`: `LibraryEntityType.rawValue`
    var value: String?

    init(condition: StackMatchCondition, value: String? = nil) {
        self.condition = condition
        self.value = value
    }
}

struct CardStack: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var isPinned: Bool
    var sortMode: StackSortMode
    var manualItemRefs: [LibraryEntityRef]
    var matchRules: [StackMatchRule]
    var surfaceRules: [SurfacingRule]
    var summaryModule: StackSummaryModule
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        isPinned: Bool = false,
        sortMode: StackSortMode = .attention,
        manualItemRefs: [LibraryEntityRef] = [],
        matchRules: [StackMatchRule] = [],
        surfaceRules: [SurfacingRule] = [],
        summaryModule: StackSummaryModule = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.isPinned = isPinned
        self.sortMode = sortMode
        self.manualItemRefs = manualItemRefs
        self.matchRules = matchRules
        self.surfaceRules = surfaceRules
        self.summaryModule = summaryModule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
