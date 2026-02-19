import Foundation

enum SurfacingRuleType: String, Codable, CaseIterable, Hashable {
    case pinUntilDone
    case surfaceDaysBeforeDate
    case remindBeforeMinutes
}

struct SurfacingRule: Identifiable, Codable, Hashable {
    let id: UUID
    var type: SurfacingRuleType
    /// Optional numeric argument used by some rule types.
    /// - `surfaceDaysBeforeDate`: days
    /// - `remindBeforeMinutes`: minutes
    var integerValue: Int?
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        type: SurfacingRuleType,
        integerValue: Int? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.integerValue = integerValue
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
