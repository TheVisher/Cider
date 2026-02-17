import Foundation

struct Folder: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var parentID: UUID?
    var createdAt: Date
    var updatedAt: Date
    var coverImagePath: String?
    var coverImageOffsetY: Double?

    init(
        id: UUID = UUID(),
        name: String,
        parentID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        coverImagePath: String? = nil,
        coverImageOffsetY: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.coverImagePath = coverImagePath
        self.coverImageOffsetY = coverImageOffsetY
    }
}
