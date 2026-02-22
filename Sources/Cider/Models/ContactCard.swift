import Foundation

struct ContactCard: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
    var relationshipLabel: String
    var birthday: Date?
    var notes: String
    var email: String
    var phone: String
    var address: String
    var hasAvatar: Bool
    var labelIDs: [UUID]
    var linkedEntities: [LibraryEntityRef]
    var folderID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String,
        relationshipLabel: String = "",
        birthday: Date? = nil,
        notes: String = "",
        email: String = "",
        phone: String = "",
        address: String = "",
        hasAvatar: Bool = false,
        labelIDs: [UUID] = [],
        linkedEntities: [LibraryEntityRef] = [],
        folderID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.relationshipLabel = relationshipLabel
        self.birthday = birthday
        self.notes = notes
        self.email = email
        self.phone = phone
        self.address = address
        self.hasAvatar = hasAvatar
        self.labelIDs = labelIDs
        self.linkedEntities = linkedEntities
        self.folderID = folderID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        relationshipLabel = (try c.decodeIfPresent(String.self, forKey: .relationshipLabel)) ?? ""
        birthday = try c.decodeIfPresent(Date.self, forKey: .birthday)
        notes = (try c.decodeIfPresent(String.self, forKey: .notes)) ?? ""
        email = (try c.decodeIfPresent(String.self, forKey: .email)) ?? ""
        phone = (try c.decodeIfPresent(String.self, forKey: .phone)) ?? ""
        address = (try c.decodeIfPresent(String.self, forKey: .address)) ?? ""
        hasAvatar = (try c.decodeIfPresent(Bool.self, forKey: .hasAvatar)) ?? false
        labelIDs = (try c.decodeIfPresent([UUID].self, forKey: .labelIDs)) ?? []
        linkedEntities = (try c.decodeIfPresent([LibraryEntityRef].self, forKey: .linkedEntities)) ?? []
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}
