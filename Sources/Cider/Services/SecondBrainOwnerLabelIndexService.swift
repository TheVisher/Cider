import Foundation

struct SecondBrainOwnerLabelIndexRecord: Equatable {
    var owner: SecondBrainOwnerRef
    var ownerKind: String
    var canonicalLabel: String
    var normalizedLabel: String
    var aliases: [String]
    var normalizedAliases: [String]
    var externalIDs: [String: String]
    var provenanceRefs: [String]
    var sourceRefs: [String]
    var labelSource: String
    var confidence: Double?
    var updatedAt: Date
}

struct SecondBrainOwnerLabelIndexRebuildResult: Equatable {
    var indexedCount: Int
    var deletedCount: Int
}

@MainActor
final class SecondBrainOwnerLabelIndexService {
    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    @discardableResult
    func upsertLabel(
        owner: SecondBrainOwnerRef,
        ownerKind: String,
        canonicalLabel: String,
        aliases: [String] = [],
        externalIDs: [String: String] = [:],
        provenanceRefs: [String] = [],
        sourceRefs: [String] = [],
        labelSource: String,
        confidence: Double? = nil,
        isDeleted: Bool = false
    ) throws -> SecondBrainOwnerLabelIndexRecord {
        let now = Date()
        let normalizedAliases = uniqueStrings(([canonicalLabel] + aliases).map(Self.normalizedLabel).filter { !$0.isEmpty })
        let cleanAliases = uniqueStrings(aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let cleanProvenance = uniqueStrings(provenanceRefs)
        let cleanSources = uniqueStrings(sourceRefs + [owner.canonicalRef])
        let normalized = Self.normalizedLabel(canonicalLabel)
        let stmt = try database.prepare("""
            INSERT INTO owner_label_index (
                owner_type, owner_id, owner_kind, canonical_label, normalized_label,
                aliases_json, normalized_aliases_json, external_ids_json,
                provenance_refs_json, source_refs_json, label_source, confidence,
                is_deleted, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_type, owner_id) DO UPDATE SET
                owner_kind = excluded.owner_kind,
                canonical_label = excluded.canonical_label,
                normalized_label = excluded.normalized_label,
                aliases_json = excluded.aliases_json,
                normalized_aliases_json = excluded.normalized_aliases_json,
                external_ids_json = excluded.external_ids_json,
                provenance_refs_json = excluded.provenance_refs_json,
                source_refs_json = excluded.source_refs_json,
                label_source = excluded.label_source,
                confidence = excluded.confidence,
                is_deleted = excluded.is_deleted,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
            .bind(ownerKind, at: 3)
            .bind(canonicalLabel, at: 4)
            .bind(normalized, at: 5)
            .bind(DatabaseHelpers.encode(cleanAliases), at: 6)
            .bind(DatabaseHelpers.encode(normalizedAliases), at: 7)
            .bind(DatabaseHelpers.encodeJSON(externalIDs) ?? "{}", at: 8)
            .bind(DatabaseHelpers.encode(cleanProvenance), at: 9)
            .bind(DatabaseHelpers.encode(cleanSources), at: 10)
            .bind(labelSource, at: 11)
            .bind(confidence, at: 12)
            .bind(isDeleted ? 1 : 0, at: 13)
            .bind(now.timeIntervalSince1970, at: 14)
            .bind(now.timeIntervalSince1970, at: 15)
        try stmt.step()
        return SecondBrainOwnerLabelIndexRecord(
            owner: owner,
            ownerKind: ownerKind,
            canonicalLabel: canonicalLabel,
            normalizedLabel: normalized,
            aliases: cleanAliases,
            normalizedAliases: normalizedAliases,
            externalIDs: externalIDs,
            provenanceRefs: cleanProvenance,
            sourceRefs: cleanSources,
            labelSource: labelSource,
            confidence: confidence,
            updatedAt: now
        )
    }

    func search(
        query: String,
        ownerKinds: Set<String>,
        ownerTypes: Set<String>,
        limit: Int = 8
    ) throws -> [SecondBrainOwnerLabelIndexRecord] {
        let normalizedQuery = Self.normalizedLabel(query)
        let queryTokens = Self.lookupTokens(query)
        guard !normalizedQuery.isEmpty, !queryTokens.isEmpty else { return [] }
        let records = try activeRecords(ownerKinds: ownerKinds, ownerTypes: ownerTypes)
        return records
            .map { (record: $0, score: Self.score(record: $0, normalizedQuery: normalizedQuery, queryTokens: queryTokens)) }
            .filter { $0.score >= 0.52 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let leftConfidence = lhs.record.confidence ?? 0
                let rightConfidence = rhs.record.confidence ?? 0
                if leftConfidence != rightConfidence { return leftConfidence > rightConfidence }
                return lhs.record.canonicalLabel.localizedCaseInsensitiveCompare(rhs.record.canonicalLabel) == .orderedAscending
            }
            .prefix(limit)
            .map(\.record)
    }

    @discardableResult
    func rebuild() throws -> SecondBrainOwnerLabelIndexRebuildResult {
        let delete = try database.prepare("DELETE FROM owner_label_index;")
        try delete.step()
        var indexed = 0
        indexed += try rebuildAcceptedRelationTargets()
        indexed += try rebuildContacts()
        indexed += try rebuildProjects()
        indexed += try rebuildProjectedOwners()
        return SecondBrainOwnerLabelIndexRebuildResult(indexedCount: indexed, deletedCount: 0)
    }

    private func activeRecords(ownerKinds: Set<String>, ownerTypes: Set<String>) throws -> [SecondBrainOwnerLabelIndexRecord] {
        let stmt = try database.prepare("""
            SELECT owner_type, owner_id, owner_kind, canonical_label, normalized_label,
                   aliases_json, normalized_aliases_json, external_ids_json,
                   provenance_refs_json, source_refs_json, label_source, confidence, updated_at
            FROM owner_label_index
            WHERE is_deleted = 0
            ORDER BY updated_at DESC
            LIMIT 800;
            """)
        var records: [SecondBrainOwnerLabelIndexRecord] = []
        while try stmt.step() {
            let ownerType = stmt.string(at: 0)
            let ownerKind = stmt.string(at: 2)
            if !ownerTypes.isEmpty, !ownerTypes.contains(ownerType) { continue }
            if !ownerKinds.isEmpty, !ownerKinds.contains(ownerKind) { continue }
            records.append(record(from: stmt))
        }
        return records
    }

    private func record(from stmt: SQLStatement) -> SecondBrainOwnerLabelIndexRecord {
        SecondBrainOwnerLabelIndexRecord(
            owner: SecondBrainOwnerRef(ownerType: stmt.string(at: 0), ownerID: stmt.string(at: 1)),
            ownerKind: stmt.string(at: 2),
            canonicalLabel: stmt.string(at: 3),
            normalizedLabel: stmt.string(at: 4),
            aliases: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 5)),
            normalizedAliases: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 6)),
            externalIDs: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 7)) ?? [:],
            provenanceRefs: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 8)),
            sourceRefs: DatabaseHelpers.decodeStringArray(stmt.optionalString(at: 9)),
            labelSource: stmt.string(at: 10),
            confidence: stmt.optionalDouble(at: 11),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 12))
        )
    }

    private func rebuildContacts() throws -> Int {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, c.relationship_label, c.notes, c.email, i.relative_path
            FROM contacts c
            JOIN items i ON i.id = c.item_id
            ORDER BY i.updated_at DESC;
            """)
        var count = 0
        while try stmt.step() {
            let id = stmt.string(at: 0)
            let owner = SecondBrainOwnerRef(ownerType: "contact", ownerID: id)
            let aliases = [stmt.string(at: 2), stmt.string(at: 4)].filter { !$0.isEmpty }
            try upsertLabel(
                owner: owner,
                ownerKind: "person",
                canonicalLabel: stmt.string(at: 1),
                aliases: aliases,
                sourceRefs: [owner.canonicalRef, stmt.optionalString(at: 5)].compactMap { $0 },
                labelSource: "owner_label_index.rebuild.contacts",
                confidence: 0.86
            )
            count += 1
        }
        return count
    }

    private func rebuildProjects() throws -> Int {
        let stmt = try database.prepare("SELECT id, title, subtitle FROM projects ORDER BY updated_at DESC;")
        var count = 0
        while try stmt.step() {
            let owner = SecondBrainOwnerRef(ownerType: "project", ownerID: stmt.string(at: 0))
            try upsertLabel(
                owner: owner,
                ownerKind: "project",
                canonicalLabel: stmt.string(at: 1),
                aliases: [stmt.string(at: 2)].filter { !$0.isEmpty },
                sourceRefs: [owner.canonicalRef],
                labelSource: "owner_label_index.rebuild.projects",
                confidence: 0.88
            )
            count += 1
        }
        return count
    }

    private func rebuildProjectedOwners() throws -> Int {
        let stmt = try database.prepare("""
            SELECT owner_type, owner_id, title, body, source, confidence
            FROM item_sections
            WHERE owner_type IN ('media_item', 'place', 'graph_object')
            ORDER BY updated_at DESC;
            """)
        var seen = Set<String>()
        var count = 0
        while try stmt.step() {
            let owner = SecondBrainOwnerRef(ownerType: stmt.string(at: 0), ownerID: stmt.string(at: 1))
            guard seen.insert(owner.canonicalRef).inserted else { continue }
            let body = stmt.string(at: 3)
            let title = stmt.string(at: 2).isEmpty ? owner.ownerID : stmt.string(at: 2)
            try upsertLabel(
                owner: owner,
                ownerKind: ownerKind(ownerType: owner.ownerType, body: body),
                canonicalLabel: title,
                aliases: aliases(from: body),
                externalIDs: externalIDs(from: body),
                sourceRefs: [owner.canonicalRef, stmt.string(at: 4)].filter { !$0.isEmpty },
                labelSource: "owner_label_index.rebuild.item_sections",
                confidence: stmt.optionalDouble(at: 5)
            )
            count += 1
        }
        return count
    }

    private func rebuildAcceptedRelationTargets() throws -> Int {
        let stmt = try database.prepare("""
            SELECT target_owner_type, target_owner_id, evidence, metadata, confidence
            FROM owner_relations
            ORDER BY updated_at DESC;
            """)
        var seen = Set<String>()
        var count = 0
        while try stmt.step() {
            let owner = SecondBrainOwnerRef(ownerType: stmt.string(at: 0), ownerID: stmt.string(at: 1))
            guard seen.insert(owner.canonicalRef).inserted else { continue }
            let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 3)) ?? [:]
            let label = metadata["target_label"]
                ?? metadata["mediaItemTitle"]
                ?? metadata["candidate_mention_text"]
                ?? owner.ownerID
            try upsertLabel(
                owner: owner,
                ownerKind: ownerKind(ownerType: owner.ownerType, body: metadata.values.joined(separator: " ")),
                canonicalLabel: label,
                aliases: [stmt.string(at: 2), metadata["candidate_mention_text"]].compactMap { $0 }.filter { !$0.isEmpty },
                sourceRefs: [owner.canonicalRef],
                labelSource: "owner_label_index.rebuild.owner_relations",
                confidence: stmt.optionalDouble(at: 4)
            )
            count += 1
        }
        return count
    }

    private func ownerKind(ownerType: String, body: String) -> String {
        switch ownerType {
        case "contact", "person":
            return "person"
        case "project":
            return "project"
        case "media_item":
            return "media"
        case "place":
            return "place"
        default:
            let normalizedBody = Self.normalizedLabel(body)
            if normalizedBody.contains("movie") || normalizedBody.contains("book") || normalizedBody.contains("show") {
                return "media"
            }
            return ownerType
        }
    }

    private func aliases(from body: String) -> [String] {
        body.split(whereSeparator: \.isNewline).compactMap { line in
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.lowercased().hasPrefix("alias:") else { return nil }
            return text.dropFirst("alias:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func externalIDs(from body: String) -> [String: String] {
        var ids: [String: String] = [:]
        for line in body.split(whereSeparator: \.isNewline) {
            let text = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.lowercased().hasPrefix("external id:") else { continue }
            let value = text.dropFirst("external id:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                ids[parts[0].trimmingCharacters(in: .whitespacesAndNewlines)] = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ids
    }

    static func normalizedLabel(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func lookupTokens(_ value: String) -> Set<String> {
        let stopwords: Set<String> = ["the", "a", "an", "and", "or", "to", "of", "for", "with", "in", "on", "at"]
        return Set(normalizedLabel(value)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !stopwords.contains($0) })
    }

    private static func score(
        record: SecondBrainOwnerLabelIndexRecord,
        normalizedQuery: String,
        queryTokens: Set<String>
    ) -> Double {
        let labels = uniqueStrings([record.normalizedLabel] + record.normalizedAliases)
        if labels.contains(normalizedQuery) { return min(0.99, 0.94 + ((record.confidence ?? 0) * 0.04)) }
        if labels.contains(where: { !$0.isEmpty && ($0.contains(normalizedQuery) || normalizedQuery.contains($0)) }) {
            return min(0.94, 0.86 + ((record.confidence ?? 0) * 0.05))
        }
        let externalTokens = lookupTokens(record.externalIDs.values.joined(separator: " "))
        let labelTokens = Set(labels.flatMap { $0.split(separator: " ").map(String.init) }).union(externalTokens)
        guard !labelTokens.isEmpty else { return 0 }
        let overlap = queryTokens.intersection(labelTokens)
        let tokenScore = Double(overlap.count) / Double(max(queryTokens.count, 1))
        return min(0.86, tokenScore * 0.72 + min(0.1, (record.confidence ?? 0) * 0.1))
    }
}

private func uniqueStrings(_ values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { raw in
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, seen.insert(value).inserted else { return nil }
        return value
    }
}
