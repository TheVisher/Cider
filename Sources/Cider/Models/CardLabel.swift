import Foundation

enum CardLabelKind: String, Codable, CaseIterable, Hashable {
    case person
    case category
    case priority
    case custom
}

struct CardLabel: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// Hex color string (e.g. "#D97706"). Rendering stays centralized in UI.
    var colorHex: String
    var kind: CardLabelKind
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "#6B7280",
        kind: CardLabelKind = .custom,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.kind = kind
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
