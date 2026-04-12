import Foundation

enum LibraryEntityType: String, Codable, CaseIterable, Hashable {
    case bookmark
    case note
    case dateCard
    case contact
    case todo
    case externalFile // Legacy — kept for backward-compat decoding only
    case vaultFile
    case session      // Legacy — kept for backward-compat decoding only

    /// Active entity types — excludes legacy cases (externalFile, session).
    /// Use this instead of `allCases` for UI filters, defaults, and new view creation.
    static let activeCases: Set<LibraryEntityType> = [.bookmark, .note, .dateCard, .contact, .todo, .vaultFile]
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
