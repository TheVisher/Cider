import Foundation

struct CiderSpaceMembership: Identifiable, Codable, Equatable {
    var id: String { "\(spaceID):\(item.type.rawValue):\(item.entityID.uuidString)" }
    var spaceID: String
    var spaceName: String
    var item: LibraryEntityRef
    var reason: String
    var confidence: Double?
    var source: String
    var actor: String
    var createdAt: Date
    var updatedAt: Date
}

@MainActor
final class CiderSpaceMembershipStore {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    @discardableResult
    func assign(
        item: LibraryEntityRef,
        toSpaceID spaceID: String,
        spaceName: String,
        reason: String,
        confidence: Double?,
        source: String,
        actor: String
    ) throws -> CiderSpaceMembership {
        let now = Date()
        let existing = try membership(for: item, inSpaceID: spaceID)
        let createdAt = existing?.createdAt ?? now
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSpaceName = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalSpaceName = trimmedSpaceName.isEmpty ? spaceID : trimmedSpaceName

        let stmt = try database.prepare("""
            INSERT INTO space_memberships (
                space_id, item_id, item_type, space_name, reason, confidence,
                source, actor, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(space_id, item_id, item_type) DO UPDATE SET
                space_name = excluded.space_name,
                reason = excluded.reason,
                confidence = excluded.confidence,
                source = excluded.source,
                actor = excluded.actor,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(spaceID, at: 1)
            .bind(item.entityID.uuidString, at: 2)
            .bind(item.type.rawValue, at: 3)
            .bind(finalSpaceName, at: 4)
            .bind(trimmedReason, at: 5)
            .bind(confidence, at: 6)
            .bind(source, at: 7)
            .bind(actor, at: 8)
            .bind(DatabaseHelpers.encode(createdAt), at: 9)
            .bind(DatabaseHelpers.encode(now), at: 10)
        try stmt.step()

        try mirrorMembershipToOwnerRelation(
            item: item,
            spaceID: spaceID,
            spaceName: finalSpaceName,
            reason: trimmedReason,
            confidence: confidence,
            membershipSource: source,
            actor: actor
        )

        return try membership(for: item, inSpaceID: spaceID) ?? CiderSpaceMembership(
            spaceID: spaceID,
            spaceName: finalSpaceName,
            item: item,
            reason: trimmedReason,
            confidence: confidence,
            source: source,
            actor: actor,
            createdAt: createdAt,
            updatedAt: now
        )
    }

    private func mirrorMembershipToOwnerRelation(
        item: LibraryEntityRef,
        spaceID: String,
        spaceName: String,
        reason: String,
        confidence: Double?,
        membershipSource: String,
        actor: String
    ) throws {
        let evidence = reason.isEmpty ? "Item belongs to Space \(spaceName)." : reason
        try SecondBrainStore(database: database).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(
                ownerType: item.type.rawValue,
                ownerID: item.entityID.uuidString
            ),
            targetOwner: SecondBrainOwnerRef(ownerType: "space", ownerID: spaceID),
            relationType: "belongs_to_space",
            evidence: evidence,
            source: "space_memberships",
            actor: actor,
            confidence: confidence,
            metadata: [
                "spaceName": spaceName,
                "membershipSource": membershipSource,
            ]
        ))
    }

    func memberships(for item: LibraryEntityRef) throws -> [CiderSpaceMembership] {
        let stmt = try database.prepare("""
            SELECT space_id, space_name, item_id, item_type, reason, confidence,
                   source, actor, created_at, updated_at
            FROM space_memberships
            WHERE item_id = ? AND item_type = ?
            ORDER BY space_name COLLATE NOCASE ASC, updated_at DESC;
            """)
        stmt.bind(item.entityID.uuidString, at: 1)
            .bind(item.type.rawValue, at: 2)
        return try readMemberships(from: stmt)
    }

    func itemRefs(inSpaceID spaceID: String) throws -> [LibraryEntityRef] {
        let stmt = try database.prepare("""
            SELECT item_id, item_type
            FROM space_memberships
            WHERE space_id = ?
            ORDER BY updated_at DESC, item_id ASC;
            """)
        stmt.bind(spaceID, at: 1)

        var refs: [LibraryEntityRef] = []
        while try stmt.step() {
            guard
                let type = LibraryEntityType(rawValue: stmt.string(at: 1)),
                let id = UUID(uuidString: stmt.string(at: 0))
            else { continue }
            refs.append(LibraryEntityRef(type: type, entityID: id))
        }
        return refs
    }

    private func membership(for item: LibraryEntityRef, inSpaceID spaceID: String) throws -> CiderSpaceMembership? {
        let stmt = try database.prepare("""
            SELECT space_id, space_name, item_id, item_type, reason, confidence,
                   source, actor, created_at, updated_at
            FROM space_memberships
            WHERE space_id = ? AND item_id = ? AND item_type = ?
            LIMIT 1;
            """)
        stmt.bind(spaceID, at: 1)
            .bind(item.entityID.uuidString, at: 2)
            .bind(item.type.rawValue, at: 3)
        return try readMemberships(from: stmt).first
    }

    private func readMemberships(from stmt: SQLStatement) throws -> [CiderSpaceMembership] {
        var memberships: [CiderSpaceMembership] = []
        while try stmt.step() {
            guard
                let type = LibraryEntityType(rawValue: stmt.string(at: 3)),
                let itemID = UUID(uuidString: stmt.string(at: 2))
            else { continue }
            memberships.append(CiderSpaceMembership(
                spaceID: stmt.string(at: 0),
                spaceName: stmt.string(at: 1),
                item: LibraryEntityRef(type: type, entityID: itemID),
                reason: stmt.string(at: 4),
                confidence: stmt.optionalDouble(at: 5),
                source: stmt.string(at: 6),
                actor: stmt.string(at: 7),
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 8)),
                updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 9))
            ))
        }
        return memberships
    }
}
