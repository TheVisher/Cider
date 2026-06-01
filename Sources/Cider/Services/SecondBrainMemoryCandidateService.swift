import Foundation

struct SecondBrainMemoryCandidateResult: Equatable {
    var owner: SecondBrainOwnerRef
    var candidate: SecondBrainEnrichmentOutput
    var agentAction: SecondBrainAgentAction
}

@MainActor
final class SecondBrainMemoryCandidateService {
    enum MemoryCandidateError: LocalizedError, Equatable {
        case unsupportedKind(String)
        case missingValue
        case missingEvidence
        case invalidConfidence(Double)
        case unresolvedOwner(String, String)

        var errorDescription: String? {
            switch self {
            case .unsupportedKind(let kind):
                return "Unsupported memory candidate kind '\(kind)'."
            case .missingValue:
                return "Memory candidate value is required."
            case .missingEvidence:
                return "Memory candidate evidence is required."
            case .invalidConfidence(let confidence):
                return "Memory candidate confidence must be between 0 and 1; got \(confidence)."
            case .unresolvedOwner(let type, let ref):
                return "Could not resolve existing owner \(type):\(ref)."
            }
        }
    }

    static let allowedKinds: Set<String> = [
        "preference",
        "pattern",
        "project_context",
        "relationship_context",
        "agent_lesson",
    ]

    private let database: CiderDatabase
    private let outputService: SecondBrainEnrichmentOutputService
    private let store: SecondBrainStore

    init(
        database: CiderDatabase = .shared,
        outputService: SecondBrainEnrichmentOutputService? = nil,
        store: SecondBrainStore? = nil
    ) {
        self.database = database
        self.outputService = outputService ?? SecondBrainEnrichmentOutputService(database: database)
        self.store = store ?? SecondBrainStore(database: database)
    }

    @discardableResult
    func suggest(
        ownerType: String,
        ownerRef: String,
        kind rawKind: String,
        value rawValue: String,
        evidence rawEvidence: String,
        source rawSource: String?,
        confidence: Double?
    ) throws -> SecondBrainMemoryCandidateResult {
        let owner = try resolveOwner(type: ownerType, ref: ownerRef)
        return try suggest(
            owner: owner,
            requestedOwnerType: ownerType,
            requestedOwnerRef: ownerRef,
            kind: rawKind,
            value: rawValue,
            evidence: rawEvidence,
            source: rawSource,
            confidence: confidence
        )
    }

    @discardableResult
    func suggest(
        owner: SecondBrainOwnerRef,
        requestedOwnerType: String,
        requestedOwnerRef: String,
        kind rawKind: String,
        value rawValue: String,
        evidence rawEvidence: String,
        source rawSource: String?,
        confidence: Double?
    ) throws -> SecondBrainMemoryCandidateResult {
        guard try ownerExists(owner) else {
            throw MemoryCandidateError.unresolvedOwner(requestedOwnerType, requestedOwnerRef)
        }

        let kind = normalizedKind(rawKind)
        guard Self.allowedKinds.contains(kind) else {
            throw MemoryCandidateError.unsupportedKind(rawKind)
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw MemoryCandidateError.missingValue }

        let evidence = rawEvidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty else { throw MemoryCandidateError.missingEvidence }

        if let confidence, confidence < 0 || confidence > 1 {
            throw MemoryCandidateError.invalidConfidence(confidence)
        }

        let source = normalizedSource(rawSource)
        let candidate = SecondBrainEnrichmentOutput(
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: normalizedValue(value),
            label: "Memory candidate: \(kind.replacingOccurrences(of: "_", with: " "))",
            evidence: evidence,
            source: source,
            confidence: confidence,
            reviewState: "suggested",
            metadata: [
                "memory_kind": kind,
                "candidate_kind": kind,
                "requires_review": "true",
                "requested_owner_type": requestedOwnerType,
                "requested_owner_ref": requestedOwnerRef,
            ]
        )

        let arguments: [String: String] = [
            "ownerType": requestedOwnerType,
            "ownerRef": requestedOwnerRef,
            "kind": kind,
            "value": value,
            "evidence": evidence,
            "source": source,
            "confidence": confidence.map { String($0) } ?? "",
        ]
        let resultJSON = DatabaseHelpers.encodeJSON([
            "candidateID": candidate.id,
            "reviewState": candidate.reviewState,
            "owner": owner.canonicalRef,
        ])
        let action = SecondBrainAgentAction(
            owner: owner,
            itemID: itemID(for: owner),
            toolName: "cider-cli item memory-suggest",
            actionType: "memory_candidate_suggested",
            source: source,
            status: "suggested",
            summary: "Suggested \(kind) memory candidate for \(owner.canonicalRef).",
            argumentsJSON: DatabaseHelpers.encodeJSON(arguments),
            resultJSON: resultJSON,
            createdAt: Date()
        )

        try database.withTransaction {
            try outputService.record(candidate)
            try store.recordAgentAction(action)
        }

        return SecondBrainMemoryCandidateResult(owner: owner, candidate: candidate, agentAction: action)
    }

    private func resolveOwner(type rawType: String, ref rawRef: String) throws -> SecondBrainOwnerRef {
        let type = normalizedOwnerType(rawType)
        let ref = rawRef.trimmingCharacters(in: .whitespacesAndNewlines)
        if type == "project" {
            if let project = try SecondBrainProjectGraphService(database: database).project(id: ref) {
                return project.owner
            }
            throw MemoryCandidateError.unresolvedOwner(rawType, rawRef)
        }
        let owner = SecondBrainOwnerRef(ownerType: type, ownerID: ref)
        guard try ownerExists(owner) else {
            throw MemoryCandidateError.unresolvedOwner(rawType, rawRef)
        }
        return owner
    }

    private func ownerExists(_ owner: SecondBrainOwnerRef) throws -> Bool {
        switch owner.ownerType {
        case "project":
            return try SecondBrainProjectGraphService(database: database).project(id: owner.ownerID) != nil
        case "bookmark", "note", "dateCard", "contact", "todo", "vaultFile":
            return try itemExists(owner)
        case "capture_event":
            return try rowExists(table: "capture_events", id: owner.ownerID)
        case "kanban_card", "kanban_board", "doc", "artifact":
            return try projectionExists(owner)
        default:
            return try projectionExists(owner)
        }
    }

    private func itemExists(_ owner: SecondBrainOwnerRef) throws -> Bool {
        guard UUID(uuidString: owner.ownerID) != nil else { return false }
        let stmt = try database.prepare("SELECT 1 FROM items WHERE id = ? AND type = ? LIMIT 1;")
        stmt.bind(owner.ownerID, at: 1)
            .bind(owner.ownerType, at: 2)
        return try stmt.step()
    }

    private func rowExists(table: String, id: String) throws -> Bool {
        let stmt = try database.prepare("SELECT 1 FROM \(table) WHERE id = ? LIMIT 1;")
        stmt.bind(id, at: 1)
        return try stmt.step()
    }

    private func projectionExists(_ owner: SecondBrainOwnerRef) throws -> Bool {
        for table in ["item_sections", "content_chunks", "enrichment_outputs", "agent_actions"] {
            if try projectedRowExists(table: table, owner: owner) {
                return true
            }
        }
        if try relationExists(owner) { return true }
        return false
    }

    private func projectedRowExists(table: String, owner: SecondBrainOwnerRef) throws -> Bool {
        let stmt = try database.prepare("SELECT 1 FROM \(table) WHERE owner_type = ? AND owner_id = ? LIMIT 1;")
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
        return try stmt.step()
    }

    private func relationExists(_ owner: SecondBrainOwnerRef) throws -> Bool {
        let stmt = try database.prepare("""
            SELECT 1 FROM owner_relations
            WHERE (source_owner_type = ? AND source_owner_id = ?)
               OR (target_owner_type = ? AND target_owner_id = ?)
            LIMIT 1;
            """)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
            .bind(owner.ownerType, at: 3)
            .bind(owner.ownerID, at: 4)
        return try stmt.step()
    }

    private func itemID(for owner: SecondBrainOwnerRef) -> String? {
        switch owner.ownerType {
        case "bookmark", "note", "dateCard", "contact", "todo", "vaultFile":
            return UUID(uuidString: owner.ownerID) == nil ? nil : owner.ownerID
        default:
            return nil
        }
    }

    private func normalizedOwnerType(_ value: String) -> String {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
        switch normalized.lowercased() {
        case "card", "kanban":
            return "kanban_card"
        case "board":
            return "kanban_board"
        case "event":
            return "dateCard"
        case "file":
            return "vaultFile"
        default:
            if let active = LibraryEntityType.activeCases.first(where: { $0.rawValue.lowercased() == normalized.lowercased() }) {
                return active.rawValue
            }
            return normalized.lowercased()
        }
    }

    private func normalizedKind(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
    }

    private func normalizedValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedSource(_ value: String?) -> String {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "agent.memory_suggest" : trimmed
    }
}
