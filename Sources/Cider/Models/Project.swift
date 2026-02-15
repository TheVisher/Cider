import Foundation

struct Project: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var isArchived: Bool
    var searchQuery: String?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isArchived: Bool = false,
        searchQuery: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isArchived = isArchived
        self.searchQuery = searchQuery
    }
}

struct ProjectItem: Identifiable, Hashable, Codable {
    let id: UUID
    var projectID: UUID
    var bookmarkID: UUID?
    var noteID: UUID?
    var addedAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        projectID: UUID,
        bookmarkID: UUID? = nil,
        noteID: UUID? = nil,
        addedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.projectID = projectID
        self.bookmarkID = bookmarkID
        self.noteID = noteID
        self.addedAt = addedAt
        self.sortOrder = sortOrder
    }
}
