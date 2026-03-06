import Foundation

struct Folder: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var coverImagePath: String?
    var coverImageOffsetY: Double?
    var icon: String?  // SF Symbol name (e.g. "star") or emoji (e.g. "🎨")

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        coverImagePath: String? = nil,
        coverImageOffsetY: Double? = nil,
        icon: String? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coverImagePath = coverImagePath
        self.coverImageOffsetY = coverImageOffsetY
        self.icon = icon
    }

    /// Whether the icon is an emoji (vs SF Symbol name).
    var iconIsEmoji: Bool {
        guard let icon, let scalar = icon.unicodeScalars.first else { return false }
        return scalar.value > 127
    }
}
