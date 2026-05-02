import Foundation

struct DashboardTopic: Identifiable, Hashable, Codable, Sendable {
    let id: UUID
    var ciderSyncId: String
    var title: String
    var icon: String?
    var colorToken: String?
    var position: Int
    var isPinned: Bool?
    var isArchived: Bool?
    var createdAt: Int64
    var updatedAt: Int64
    var deleted: Bool?
    var deletedAt: Int64?

    init(
        id: UUID = UUID(),
        ciderSyncId: String? = nil,
        title: String,
        icon: String? = nil,
        colorToken: String? = nil,
        position: Int,
        isPinned: Bool? = nil,
        isArchived: Bool? = nil,
        createdAt: Int64,
        updatedAt: Int64,
        deleted: Bool? = nil,
        deletedAt: Int64? = nil
    ) {
        self.id = id
        self.ciderSyncId = DashboardModelIdentity.ciderSyncId(ciderSyncId, defaultingTo: id)
        self.title = title
        self.icon = icon
        self.colorToken = colorToken
        self.position = position
        self.isPinned = isPinned
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deleted = deleted
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case ciderSyncId
        case title
        case icon
        case colorToken
        case position
        case isPinned
        case isArchived
        case createdAt
        case updatedAt
        case deleted
        case deletedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSyncId = try container.decode(String.self, forKey: .ciderSyncId).lowercased()
        id = DashboardModelIdentity.localID(from: decodedSyncId)
        ciderSyncId = decodedSyncId
        title = try container.decode(String.self, forKey: .title)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        colorToken = try container.decodeIfPresent(String.self, forKey: .colorToken)
        position = try container.decode(Int.self, forKey: .position)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived)
        createdAt = try container.decode(Int64.self, forKey: .createdAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
        deletedAt = try container.decodeIfPresent(Int64.self, forKey: .deletedAt)
    }
}
