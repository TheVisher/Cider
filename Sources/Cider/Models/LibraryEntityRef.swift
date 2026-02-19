import Foundation

enum LibraryEntityType: String, Codable, CaseIterable, Hashable {
    case bookmark
    case note
    case dateCard
    case contact
}

struct LibraryEntityRef: Identifiable, Codable, Hashable {
    let type: LibraryEntityType
    let entityID: UUID

    var id: String {
        "\(type.rawValue)-\(entityID.uuidString)"
    }

    init(type: LibraryEntityType, entityID: UUID) {
        self.type = type
        self.entityID = entityID
    }
}
