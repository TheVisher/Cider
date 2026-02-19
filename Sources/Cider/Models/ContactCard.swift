import Foundation

struct ContactCard: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var relationshipLabel: String
    var birthday: Date?
    var notes: String
    var labelIDs: [UUID]
    var linkedEntities: [LibraryEntityRef]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        relationshipLabel: String = "",
        birthday: Date? = nil,
        notes: String = "",
        labelIDs: [UUID] = [],
        linkedEntities: [LibraryEntityRef] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.relationshipLabel = relationshipLabel
        self.birthday = birthday
        self.notes = notes
        self.labelIDs = labelIDs
        self.linkedEntities = linkedEntities
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
