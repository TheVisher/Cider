import CryptoKit
import Foundation

enum ProjectIntakeSourceKind: String, Codable, Equatable {
    case ciderRoom = "cider_room"
    case ciderChapter = "cider_chapter"
    case transportMessageSpan = "transport_message_span"
    case importedChatArtifact = "imported_chat_artifact"
}

struct ProjectIntakeSourceDescriptor: Codable, Equatable {
    var sourceOwner: SecondBrainOwnerRef
    var sourceKind: ProjectIntakeSourceKind
    var roomID: String?
    var chapterID: String?
    var firstMessageID: String?
    var lastMessageID: String?
    var contentDigest: String
    var capturedAt: Date
    var capturedBy: String
    var sourceEvidenceRefs: [String] = []

    var spanIdentity: String {
        [
            sourceKind.rawValue,
            roomID ?? "",
            chapterID ?? "",
            firstMessageID ?? "",
            lastMessageID ?? "",
        ].joined(separator: "|")
    }
}

struct ProjectIntakeCaptureRequest: Equatable {
    var projectRef: String
    var source: ProjectIntakeSourceDescriptor
    var title: String
    var conciseSummary: String
    var reasoning: String
    var decisions: [String]
    var alternatives: [String]
    var openQuestions: [String]
    var requestID: String
    var actor: String
}

enum ProjectIntakeLifecycleState: String, Codable, Equatable {
    case captured
    case reviewed
    case integrated
    case deferred
    case rejected
}

enum ProjectIntakePlacementKind: String, Codable, Equatable {
    case intake
    case primary
}

struct ProjectIntakeNode: Identifiable, Codable, Equatable {
    var id: String
    var projectID: String
    var nodeKind: String
    var title: String
    var conciseSummary: String
    var lifecycleState: ProjectIntakeLifecycleState
    var placementKind: ProjectIntakePlacementKind
    var intakeVisibility: String
    var requestID: String
    var captureKey: String
    var schemaVersion: Int
    var nodeRevision: Int
    var createdAt: Date
    var updatedAt: Date
    var integratedAt: Date?

    var owner: SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: "project_node", ownerID: id)
    }
}

struct ProjectIntakeGraphState: Codable, Equatable {
    var projectID: String
    var graphRevision: Int
    var primaryPathRevision: Int
    var canonicalSummaryRevision: Int
    var intakeSummary: String
    var activeIntakeCount: Int
    var updatedAt: Date
}

struct ProjectIntakeEvent: Identifiable, Codable, Equatable {
    var id: String
    var nodeID: String
    var operationID: String
    var eventKind: String
    var fromState: String?
    var toState: String?
    var actorType: String
    var actorID: String?
    var authorityRevision: Int?
    var primaryPathRevision: Int?
    var payloadJSON: String
    var createdAt: Date
}

struct ProjectIntakeSourceEvidence: Codable, Equatable {
    var id: String
    var sourceOwner: SecondBrainOwnerRef
    var nodeID: String
    var contentDigest: String
    var metadata: [String: String]
}

enum ProjectIntakeReceiptStatus: String, Codable, Equatable {
    case succeeded
    case noChange = "no_change"
}

struct ProjectIntakeCaptureReceipt: Codable, Equatable {
    var operation: String = "capture"
    var status: ProjectIntakeReceiptStatus
    var project: SecondBrainProject
    var node: ProjectIntakeNode
    var source: ProjectIntakeSourceDescriptor
    var lifecycleBefore: ProjectIntakeLifecycleState?
    var lifecycleAfter: ProjectIntakeLifecycleState
    var scheduled: Bool
    var orderedPathChanged: Bool
    var rootSummaryChanged: Bool
    var rootSummaryDelta: String
    var provenanceRef: String
    var idempotencyKey: String
    var changed: Bool
    var graphRevision: Int
    var primaryPathRevision: Int
}

enum ProjectIntakeError: Error, LocalizedError, Equatable {
    case projectNotFound(String)
    case projectAmbiguous(String, [String])
    case sourceRequired
    case sourceNotPreserved(String)
    case sourceSpanInvalid
    case sourceDigestMismatch
    case idempotencyKeyConflict
    case invalidInput(String)

    var code: String {
        switch self {
        case .projectNotFound: "project_not_found"
        case .projectAmbiguous: "project_ambiguous"
        case .sourceRequired: "source_required"
        case .sourceNotPreserved: "source_not_preserved"
        case .sourceSpanInvalid: "source_span_invalid"
        case .sourceDigestMismatch: "source_digest_mismatch"
        case .idempotencyKeyConflict: "idempotency_key_conflict"
        case .invalidInput: "invalid_input"
        }
    }

    var errorDescription: String? {
        switch self {
        case .projectNotFound(let ref):
            "No project matched '\(ref)'; no intake node was created."
        case .projectAmbiguous(let ref, let candidates):
            "Project '\(ref)' matched multiple destinations: \(candidates.joined(separator: ", "))."
        case .sourceRequired:
            "A preserved source room and message span are required."
        case .sourceNotPreserved(let ref):
            "The preserved source '\(ref)' could not be reopened."
        case .sourceSpanInvalid:
            "The selected source span is empty, reversed, or outside its room."
        case .sourceDigestMismatch:
            "The selected source changed before capture; no intake node was created."
        case .idempotencyKeyConflict:
            "This request ID was already used with a different project or source."
        case .invalidInput(let field):
            "Project intake requires a non-empty \(field)."
        }
    }
}

@MainActor
final class SecondBrainProjectIntakeService {
    static let contractVersion = "project-intake/v1"
    private static let sectionSource = "project_intake/v1"
    private static let rootSummaryLineLimit = 8
    private static let rootSummaryCharacterLimit = 2_000
    private static let rootSummaryContributionLimit = 600

    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func capture(_ request: ProjectIntakeCaptureRequest) throws -> ProjectIntakeCaptureReceipt {
        try database.withImmediateTransaction {
            let project = try resolveProject(request.projectRef)
            try validateRequiredInput(request)
            let captureKey = Self.sha256([
                Self.contractVersion,
                project.id,
                request.source.sourceOwner.canonicalRef,
                request.source.spanIdentity,
                request.requestID,
            ].joined(separator: "|"))

            if let existing = try node(requestID: request.requestID) {
                let existingEvidence = try sourceEvidence(nodeID: existing.id)
                guard existing.captureKey == captureKey,
                      existingEvidence?.contentDigest == request.source.contentDigest.lowercased() else {
                    throw ProjectIntakeError.idempotencyKeyConflict
                }
                return try receipt(
                    project: project,
                    node: existing,
                    source: request.source,
                    status: .noChange,
                    changed: false,
                    rootSummaryChanged: false
                )
            }

            let messages = try validateSource(request.source)
            let observedDigest = Self.contentDigest(messages: messages)
            guard observedDigest == request.source.contentDigest.lowercased() else {
                throw ProjectIntakeError.sourceDigestMismatch
            }
            if let existing = try node(captureKey: captureKey) {
                return try receipt(
                    project: project,
                    node: existing,
                    source: request.source,
                    status: .noChange,
                    changed: false,
                    rootSummaryChanged: false
                )
            }

            let now = Date()
            let node = ProjectIntakeNode(
                id: Self.makeULID(date: now),
                projectID: project.id,
                nodeKind: "idea",
                title: request.title.trimmingCharacters(in: .whitespacesAndNewlines),
                conciseSummary: request.conciseSummary.trimmingCharacters(in: .whitespacesAndNewlines),
                lifecycleState: .captured,
                placementKind: .intake,
                intakeVisibility: "active",
                requestID: request.requestID,
                captureKey: captureKey,
                schemaVersion: 1,
                nodeRevision: 1,
                createdAt: now,
                updatedAt: now,
                integratedAt: nil
            )
            try insert(node)
            try insertSections(for: node, request: request)
            try insertRelations(for: node, project: project, source: request.source, at: now)
            try insertSourceEvidence(for: node, source: request.source, at: now)
            try insertCapturedEvent(for: node, request: request, at: now)
            _ = try updateRootIntakeState(projectID: project.id, node: node, at: now)

            return try receipt(
                project: project,
                node: node,
                source: request.source,
                status: .succeeded,
                changed: true,
                rootSummaryChanged: true
            )
        }
    }

    func node(id: String) throws -> ProjectIntakeNode? {
        let stmt = try database.prepare("""
            SELECT id, project_id, node_kind, title, concise_summary, lifecycle_state,
                   placement_kind, intake_visibility, request_id, capture_key, schema_version,
                   node_revision, created_at, updated_at, integrated_at
            FROM project_nodes WHERE id = ? LIMIT 1;
            """)
        stmt.bind(id, at: 1)
        return try stmt.step() ? node(from: stmt) : nil
    }

    func allNodes() throws -> [ProjectIntakeNode] {
        let stmt = try database.prepare("""
            SELECT id, project_id, node_kind, title, concise_summary, lifecycle_state,
                   placement_kind, intake_visibility, request_id, capture_key, schema_version,
                   node_revision, created_at, updated_at, integrated_at
            FROM project_nodes ORDER BY created_at ASC, id ASC;
            """)
        var result: [ProjectIntakeNode] = []
        while try stmt.step() { result.append(node(from: stmt)) }
        return result
    }

    func sections(nodeID: String) throws -> [SecondBrainSection] {
        try SecondBrainStore(database: database).sections(
            for: SecondBrainOwnerRef(ownerType: "project_node", ownerID: nodeID)
        )
    }

    func relations(nodeID: String) throws -> [SecondBrainRelation] {
        let owner = SecondBrainOwnerRef(ownerType: "project_node", ownerID: nodeID)
        let store = SecondBrainStore(database: database)
        return try store.backlinks(for: owner) + store.outgoingRelations(for: owner)
    }

    func events(nodeID: String) throws -> [ProjectIntakeEvent] {
        let stmt = try database.prepare("""
            SELECT id, node_id, operation_id, event_kind, from_state, to_state,
                   actor_type, actor_id, authority_revision, primary_path_revision,
                   payload_json, created_at
            FROM project_node_events
            WHERE node_id = ?
            ORDER BY created_at ASC, id ASC;
            """)
        stmt.bind(nodeID, at: 1)
        var result: [ProjectIntakeEvent] = []
        while try stmt.step() {
            result.append(ProjectIntakeEvent(
                id: stmt.string(at: 0),
                nodeID: stmt.string(at: 1),
                operationID: stmt.string(at: 2),
                eventKind: stmt.string(at: 3),
                fromState: stmt.optionalString(at: 4),
                toState: stmt.optionalString(at: 5),
                actorType: stmt.string(at: 6),
                actorID: stmt.optionalString(at: 7),
                authorityRevision: stmt.optionalDouble(at: 8).map(Int.init),
                primaryPathRevision: stmt.optionalDouble(at: 9).map(Int.init),
                payloadJSON: stmt.string(at: 10),
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 11))
            ))
        }
        return result
    }

    func graphState(projectID: String) throws -> ProjectIntakeGraphState {
        let normalized = SecondBrainProjectGraphService.normalizedProjectID(projectID)
        let stmt = try database.prepare("""
            SELECT project_id, graph_revision, primary_path_revision,
                   canonical_summary_revision, intake_summary, active_intake_count, updated_at
            FROM project_graph_states WHERE project_id = ? LIMIT 1;
            """)
        stmt.bind(normalized, at: 1)
        guard try stmt.step() else {
            return ProjectIntakeGraphState(
                projectID: normalized,
                graphRevision: 0,
                primaryPathRevision: 0,
                canonicalSummaryRevision: 0,
                intakeSummary: "",
                activeIntakeCount: 0,
                updatedAt: .distantPast
            )
        }
        return ProjectIntakeGraphState(
            projectID: stmt.string(at: 0),
            graphRevision: stmt.int(at: 1),
            primaryPathRevision: stmt.int(at: 2),
            canonicalSummaryRevision: stmt.int(at: 3),
            intakeSummary: stmt.string(at: 4),
            activeIntakeCount: stmt.int(at: 5),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 6))
        )
    }

    func primaryPathNodeIDs(projectID: String) throws -> [String] {
        let stmt = try database.prepare("""
            SELECT node_id FROM project_primary_path_memberships
            WHERE project_id = ? ORDER BY ordinal ASC;
            """)
        stmt.bind(SecondBrainProjectGraphService.normalizedProjectID(projectID), at: 1)
        var result: [String] = []
        while try stmt.step() { result.append(stmt.string(at: 0)) }
        return result
    }

    func sourceEvidence(nodeID: String) throws -> ProjectIntakeSourceEvidence? {
        let stmt = try database.prepare("""
            SELECT id, source_owner_type, source_owner_id, derived_owner_id, metadata
            FROM source_evidence
            WHERE derived_owner_type = 'project_node'
              AND derived_owner_id = ?
              AND evidence_kind = 'project_intake_source'
            LIMIT 1;
            """)
        stmt.bind(nodeID, at: 1)
        guard try stmt.step() else { return nil }
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 4)) ?? [:]
        return ProjectIntakeSourceEvidence(
            id: stmt.string(at: 0),
            sourceOwner: SecondBrainOwnerRef(ownerType: stmt.string(at: 1), ownerID: stmt.string(at: 2)),
            nodeID: stmt.string(at: 3),
            contentDigest: metadata["content_digest"] ?? "",
            metadata: metadata
        )
    }

    func seedPrimaryPathForTesting(projectID: String, nodeIDs: [String], revision: Int) throws {
        let projectID = SecondBrainProjectGraphService.normalizedProjectID(projectID)
        try database.withTransaction {
            let delete = try database.prepare("DELETE FROM project_primary_path_memberships WHERE project_id = ?;")
            delete.bind(projectID, at: 1)
            try delete.step()
            for (ordinal, nodeID) in nodeIDs.enumerated() {
                let seedNode = try database.prepare("""
                    INSERT OR IGNORE INTO project_nodes (
                        id, project_id, node_kind, title, concise_summary, lifecycle_state,
                        placement_kind, intake_visibility, request_id, capture_key,
                        schema_version, node_revision, created_at, updated_at, integrated_at
                    ) VALUES (?, ?, 'milestone', ?, 'Test seed', 'integrated', 'primary',
                              'archived', ?, ?, 1, 1, ?, ?, ?);
                    """)
                let seededAt = DatabaseHelpers.encode(Date(timeIntervalSince1970: 1))
                seedNode.bind(nodeID, at: 1)
                    .bind(projectID, at: 2)
                    .bind(nodeID, at: 3)
                    .bind("test-request-\(projectID)-\(nodeID)", at: 4)
                    .bind("test-capture-\(projectID)-\(nodeID)", at: 5)
                    .bind(seededAt, at: 6)
                    .bind(seededAt, at: 7)
                    .bind(seededAt, at: 8)
                try seedNode.step()
                let insert = try database.prepare("""
                    INSERT INTO project_primary_path_memberships
                        (project_id, node_id, ordinal, approval_event_id, integrated_at)
                    VALUES (?, ?, ?, 'test-seed', ?);
                    """)
                insert.bind(projectID, at: 1)
                    .bind(nodeID, at: 2)
                    .bind(ordinal, at: 3)
                    .bind(seededAt, at: 4)
                try insert.step()
            }
            let state = try database.prepare("""
                INSERT INTO project_graph_states
                    (project_id, graph_revision, primary_path_revision, canonical_summary_revision,
                     intake_summary, active_intake_count, updated_at)
                VALUES (?, 0, ?, 0, '', 0, ?)
                ON CONFLICT(project_id) DO UPDATE SET
                    primary_path_revision = excluded.primary_path_revision,
                    updated_at = excluded.updated_at;
                """)
            state.bind(projectID, at: 1)
                .bind(revision, at: 2)
                .bind(DatabaseHelpers.encode(Date()), at: 3)
            try state.step()
        }
    }

    nonisolated static func contentDigest(messages: [ConversationMessage]) -> String {
        let material = messages
            .sorted { $0.sequence < $1.sequence }
            .map { "\($0.id.uuidString)|\($0.sequence)|\($0.role)|\($0.contentText)" }
            .joined(separator: "\n")
        return sha256(material)
    }

    private func validateRequiredInput(_ request: ProjectIntakeCaptureRequest) throws {
        let required = [
            ("project", request.projectRef),
            ("title", request.title),
            ("concise summary", request.conciseSummary),
            ("reasoning", request.reasoning),
            ("request ID", request.requestID),
            ("actor", request.actor),
        ]
        if let missing = required.first(where: { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw ProjectIntakeError.invalidInput(missing.0)
        }
        guard request.title.count <= 160,
              request.conciseSummary.count <= 600,
              request.reasoning.count <= 4_000,
              request.requestID.count <= 256,
              request.actor.count <= 160,
              request.decisions.count <= 50,
              request.alternatives.count <= 50,
              request.openQuestions.count <= 50,
              (request.decisions + request.alternatives + request.openQuestions)
                .allSatisfy({ $0.count <= 1_000 }) else {
            throw ProjectIntakeError.invalidInput("bounded intake fields")
        }
    }

    private func resolveProject(_ ref: String) throws -> SecondBrainProject {
        let trimmed = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProjectIntakeError.projectNotFound(ref) }
        let normalized = SecondBrainProjectGraphService.normalizedProjectID(trimmed)
        let exact = try projects(where: "id = ?", binding: normalized)
        if let project = exact.first { return project }

        let candidates = try allProjects().filter { project in
            if project.title.caseInsensitiveCompare(trimmed) == .orderedSame { return true }
            let aliases = project.metadata["aliases"]?
                .split(whereSeparator: { $0 == "," || $0 == "|" })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? []
            return aliases.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        }
        guard !candidates.isEmpty else { throw ProjectIntakeError.projectNotFound(ref) }
        guard candidates.count == 1 else {
            throw ProjectIntakeError.projectAmbiguous(ref, candidates.map { "\($0.title) (\($0.id))" })
        }
        return candidates[0]
    }

    private func projects(where predicate: String, binding: String) throws -> [SecondBrainProject] {
        let stmt = try database.prepare("""
            SELECT id, title, subtitle, status, metadata, created_at, updated_at
            FROM projects WHERE \(predicate) ORDER BY id ASC;
            """)
        stmt.bind(binding, at: 1)
        var result: [SecondBrainProject] = []
        while try stmt.step() { result.append(project(from: stmt)) }
        return result
    }

    private func allProjects() throws -> [SecondBrainProject] {
        let stmt = try database.prepare("""
            SELECT id, title, subtitle, status, metadata, created_at, updated_at
            FROM projects ORDER BY id ASC;
            """)
        var result: [SecondBrainProject] = []
        while try stmt.step() { result.append(project(from: stmt)) }
        return result
    }

    private func project(from stmt: SQLStatement) -> SecondBrainProject {
        SecondBrainProject(
            id: stmt.string(at: 0),
            title: stmt.string(at: 1),
            subtitle: stmt.string(at: 2),
            status: stmt.string(at: 3),
            metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 4)) ?? [:],
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 5)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 6))
        )
    }

    private func validateSource(_ source: ProjectIntakeSourceDescriptor) throws -> [ConversationMessage] {
        guard !source.sourceOwner.ownerType.isEmpty,
              !source.sourceOwner.ownerID.isEmpty,
              !source.contentDigest.isEmpty else {
            throw ProjectIntakeError.sourceRequired
        }
        switch source.sourceKind {
        case .ciderRoom, .ciderChapter:
            if source.sourceKind == .ciderChapter,
               source.chapterID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                throw ProjectIntakeError.sourceRequired
            }
            guard let roomIDString = source.roomID,
                  let roomID = UUID(uuidString: roomIDString),
                  let firstIDString = source.firstMessageID,
                  let firstID = UUID(uuidString: firstIDString),
                  let lastIDString = source.lastMessageID,
                  let lastID = UUID(uuidString: lastIDString) else {
                throw ProjectIntakeError.sourceRequired
            }
            let canonicalOwner = SecondBrainOwnerRef(ownerType: "conversation_room", ownerID: roomID.uuidString)
            guard source.sourceOwner == canonicalOwner else { throw ProjectIntakeError.sourceSpanInvalid }
            let repository = ConversationRepository(database: database)
            guard try repository.room(id: roomID) != nil else {
                throw ProjectIntakeError.sourceNotPreserved(source.sourceOwner.canonicalRef)
            }
            let allMessages = try repository.messages(roomID: roomID)
            guard let first = allMessages.first(where: { $0.id == firstID }),
                  let last = allMessages.first(where: { $0.id == lastID }),
                  first.sequence <= last.sequence else {
                throw ProjectIntakeError.sourceSpanInvalid
            }
            let selected = allMessages.filter { $0.sequence >= first.sequence && $0.sequence <= last.sequence }
            guard !selected.isEmpty else { throw ProjectIntakeError.sourceSpanInvalid }
            return selected
        case .transportMessageSpan, .importedChatArtifact:
            throw ProjectIntakeError.sourceNotPreserved(source.sourceOwner.canonicalRef)
        }
    }

    private func insert(_ node: ProjectIntakeNode) throws {
        let stmt = try database.prepare("""
            INSERT INTO project_nodes (
                id, project_id, node_kind, title, concise_summary, lifecycle_state,
                placement_kind, intake_visibility, request_id, capture_key, schema_version,
                node_revision, created_at, updated_at, integrated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(node.id, at: 1)
            .bind(node.projectID, at: 2)
            .bind(node.nodeKind, at: 3)
            .bind(node.title, at: 4)
            .bind(node.conciseSummary, at: 5)
            .bind(node.lifecycleState.rawValue, at: 6)
            .bind(node.placementKind.rawValue, at: 7)
            .bind(node.intakeVisibility, at: 8)
            .bind(node.requestID, at: 9)
            .bind(node.captureKey, at: 10)
            .bind(node.schemaVersion, at: 11)
            .bind(node.nodeRevision, at: 12)
            .bind(DatabaseHelpers.encode(node.createdAt), at: 13)
            .bind(DatabaseHelpers.encode(node.updatedAt), at: 14)
            .bind(node.integratedAt.map(DatabaseHelpers.encode), at: 15)
        try stmt.step()
    }

    private func insertSections(for node: ProjectIntakeNode, request: ProjectIntakeCaptureRequest) throws {
        let provenance = DatabaseHelpers.encodeJSON(request.source) ?? "{}"
        let values: [(String, String, String)] = [
            ("reasoning", "Reasoning", request.reasoning),
            ("decisions", "Decisions", bulletList(request.decisions)),
            ("alternatives", "Alternatives", bulletList(request.alternatives)),
            ("open_questions", "Open Questions", bulletList(request.openQuestions)),
            ("source_provenance", "Source Provenance", provenance),
        ]
        for (index, value) in values.enumerated() {
            let stmt = try database.prepare("""
                INSERT INTO item_sections (
                    id, item_id, owner_type, owner_id, section_key, title, body,
                    source, confidence, metadata, sort_order, created_at, updated_at
                ) VALUES (?, NULL, 'project_node', ?, ?, ?, ?, ?, 1, ?, ?, ?, ?);
                """)
            let metadata = DatabaseHelpers.encodeJSON([
                "contract_version": Self.contractVersion,
                "content_digest": request.source.contentDigest,
            ]) ?? "{}"
            stmt.bind(UUID().uuidString, at: 1)
                .bind(node.id, at: 2)
                .bind(value.0, at: 3)
                .bind(value.1, at: 4)
                .bind(value.2, at: 5)
                .bind(Self.sectionSource, at: 6)
                .bind(metadata, at: 7)
                .bind(index, at: 8)
                .bind(DatabaseHelpers.encode(node.createdAt), at: 9)
                .bind(DatabaseHelpers.encode(node.updatedAt), at: 10)
            try stmt.step()
        }
    }

    private func insertRelations(
        for node: ProjectIntakeNode,
        project: SecondBrainProject,
        source: ProjectIntakeSourceDescriptor,
        at date: Date
    ) throws {
        let projectOwner = project.owner
        let nodeOwner = node.owner
        try insertRelation(
            source: projectOwner,
            target: nodeOwner,
            type: "contains_project_node",
            evidence: "Project authority contains captured intake node \(node.title).",
            metadata: ["lifecycle": "captured", "placement": "intake"],
            at: date
        )
        try insertRelation(
            source: nodeOwner,
            target: source.sourceOwner,
            type: "derived_from",
            evidence: "Captured from preserved \(source.sourceKind.rawValue) source.",
            metadata: [
                "source_kind": source.sourceKind.rawValue,
                "source_span_identity": source.spanIdentity,
                "content_digest": source.contentDigest,
            ],
            at: date
        )
    }

    private func insertRelation(
        source: SecondBrainOwnerRef,
        target: SecondBrainOwnerRef,
        type: String,
        evidence: String,
        metadata: [String: String],
        at date: Date
    ) throws {
        let stmt = try database.prepare("""
            INSERT INTO owner_relations (
                id, source_owner_type, source_owner_id, target_owner_type, target_owner_id,
                relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'system', 1, ?, ?, ?);
            """)
        stmt.bind(UUID().uuidString, at: 1)
            .bind(source.ownerType, at: 2)
            .bind(source.ownerID, at: 3)
            .bind(target.ownerType, at: 4)
            .bind(target.ownerID, at: 5)
            .bind(type, at: 6)
            .bind(evidence, at: 7)
            .bind(Self.sectionSource, at: 8)
            .bind(DatabaseHelpers.encodeJSON(metadata) ?? "{}", at: 9)
            .bind(DatabaseHelpers.encode(date), at: 10)
            .bind(DatabaseHelpers.encode(date), at: 11)
        try stmt.step()
    }

    private func insertSourceEvidence(
        for node: ProjectIntakeNode,
        source: ProjectIntakeSourceDescriptor,
        at date: Date
    ) throws {
        let metadata = DatabaseHelpers.encodeJSON([
            "content_digest": source.contentDigest,
            "source_span_identity": source.spanIdentity,
            "room_id": source.roomID ?? "",
            "chapter_id": source.chapterID ?? "",
            "first_message_id": source.firstMessageID ?? "",
            "last_message_id": source.lastMessageID ?? "",
            "captured_by": source.capturedBy,
            "source_evidence_refs": source.sourceEvidenceRefs.joined(separator: ","),
        ]) ?? "{}"
        let stmt = try database.prepare("""
            INSERT INTO source_evidence (
                id, evidence_kind, source_owner_type, source_owner_id, source_kind,
                source_quote, observed_at, captured_at, extracted_at, extraction_source,
                derived_owner_type, derived_owner_id, derived_kind, metadata, created_at, updated_at
            ) VALUES (?, 'project_intake_source', ?, ?, ?, '', ?, ?, ?, ?,
                      'project_node', ?, 'project_intake_capture', ?, ?, ?);
            """)
        stmt.bind(UUID().uuidString, at: 1)
            .bind(source.sourceOwner.ownerType, at: 2)
            .bind(source.sourceOwner.ownerID, at: 3)
            .bind(source.sourceKind.rawValue, at: 4)
            .bind(DatabaseHelpers.encode(source.capturedAt), at: 5)
            .bind(DatabaseHelpers.encode(source.capturedAt), at: 6)
            .bind(DatabaseHelpers.encode(date), at: 7)
            .bind(Self.sectionSource, at: 8)
            .bind(node.id, at: 9)
            .bind(metadata, at: 10)
            .bind(DatabaseHelpers.encode(date), at: 11)
            .bind(DatabaseHelpers.encode(date), at: 12)
        try stmt.step()
    }

    private func insertCapturedEvent(
        for node: ProjectIntakeNode,
        request: ProjectIntakeCaptureRequest,
        at date: Date
    ) throws {
        let state = try graphState(projectID: node.projectID)
        let payload = DatabaseHelpers.encodeJSON([
            "contract_version": Self.contractVersion,
            "capture_key": node.captureKey,
            "source_owner_ref": request.source.sourceOwner.canonicalRef,
            "source_span_identity": request.source.spanIdentity,
            "content_digest": request.source.contentDigest,
            "scheduled": "false",
            "ordered_path_changed": "false",
        ]) ?? "{}"
        let stmt = try database.prepare("""
            INSERT INTO project_node_events (
                id, node_id, operation_id, event_kind, from_state, to_state,
                actor_type, actor_id, authority_revision, primary_path_revision,
                payload_json, created_at
            ) VALUES (?, ?, ?, 'captured', NULL, 'captured', 'agent', ?, ?, ?, ?, ?);
            """)
        stmt.bind(UUID().uuidString, at: 1)
            .bind(node.id, at: 2)
            .bind(request.requestID, at: 3)
            .bind(request.actor, at: 4)
            .bind(state.canonicalSummaryRevision, at: 5)
            .bind(state.primaryPathRevision, at: 6)
            .bind(payload, at: 7)
            .bind(DatabaseHelpers.encode(date), at: 8)
        try stmt.step()
    }

    private func updateRootIntakeState(
        projectID: String,
        node: ProjectIntakeNode,
        at date: Date
    ) throws -> ProjectIntakeGraphState {
        let prior = try graphState(projectID: projectID)
        let line = boundedRootLine(node: node)
        var lines = prior.intakeSummary.split(separator: "\n").map(String.init)
        if lines.count < Self.rootSummaryLineLimit { lines.append(line) }
        var summary = lines.joined(separator: "\n")
        if summary.count > Self.rootSummaryCharacterLimit {
            summary = "\(prior.activeIntakeCount + 1) captured intake items — open the project intake view."
        }
        let stmt = try database.prepare("""
            INSERT INTO project_graph_states (
                project_id, graph_revision, primary_path_revision, canonical_summary_revision,
                intake_summary, active_intake_count, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(project_id) DO UPDATE SET
                graph_revision = excluded.graph_revision,
                intake_summary = excluded.intake_summary,
                active_intake_count = excluded.active_intake_count,
                updated_at = excluded.updated_at;
            """)
        stmt.bind(projectID, at: 1)
            .bind(prior.graphRevision + 1, at: 2)
            .bind(prior.primaryPathRevision, at: 3)
            .bind(prior.canonicalSummaryRevision, at: 4)
            .bind(summary, at: 5)
            .bind(prior.activeIntakeCount + 1, at: 6)
            .bind(DatabaseHelpers.encode(date), at: 7)
        try stmt.step()
        return try graphState(projectID: projectID)
    }

    private func boundedRootLine(node: ProjectIntakeNode) -> String {
        let prefix = "- \(node.title) (project_node:\(node.id)): "
        let available = max(0, Self.rootSummaryContributionLimit - prefix.count)
        let summary = String(node.conciseSummary.prefix(available))
        return prefix + summary
    }

    private func receipt(
        project: SecondBrainProject,
        node: ProjectIntakeNode,
        source: ProjectIntakeSourceDescriptor,
        status: ProjectIntakeReceiptStatus,
        changed: Bool,
        rootSummaryChanged: Bool
    ) throws -> ProjectIntakeCaptureReceipt {
        let state = try graphState(projectID: project.id)
        return ProjectIntakeCaptureReceipt(
            status: status,
            project: project,
            node: node,
            source: source,
            lifecycleBefore: changed ? nil : node.lifecycleState,
            lifecycleAfter: node.lifecycleState,
            scheduled: false,
            orderedPathChanged: false,
            rootSummaryChanged: rootSummaryChanged,
            rootSummaryDelta: rootSummaryChanged ? "Added one bounded Captured intake mention." : "No root change; returned the existing capture.",
            provenanceRef: "source_evidence:\(try sourceEvidence(nodeID: node.id)?.id ?? "")",
            idempotencyKey: node.captureKey,
            changed: changed,
            graphRevision: state.graphRevision,
            primaryPathRevision: state.primaryPathRevision
        )
    }

    private func node(requestID: String) throws -> ProjectIntakeNode? {
        let stmt = try database.prepare("""
            SELECT id, project_id, node_kind, title, concise_summary, lifecycle_state,
                   placement_kind, intake_visibility, request_id, capture_key, schema_version,
                   node_revision, created_at, updated_at, integrated_at
            FROM project_nodes WHERE request_id = ? LIMIT 1;
            """)
        stmt.bind(requestID, at: 1)
        return try stmt.step() ? node(from: stmt) : nil
    }

    private func node(captureKey: String) throws -> ProjectIntakeNode? {
        let stmt = try database.prepare("""
            SELECT id, project_id, node_kind, title, concise_summary, lifecycle_state,
                   placement_kind, intake_visibility, request_id, capture_key, schema_version,
                   node_revision, created_at, updated_at, integrated_at
            FROM project_nodes WHERE capture_key = ? LIMIT 1;
            """)
        stmt.bind(captureKey, at: 1)
        return try stmt.step() ? node(from: stmt) : nil
    }

    private func node(from stmt: SQLStatement) -> ProjectIntakeNode {
        ProjectIntakeNode(
            id: stmt.string(at: 0),
            projectID: stmt.string(at: 1),
            nodeKind: stmt.string(at: 2),
            title: stmt.string(at: 3),
            conciseSummary: stmt.string(at: 4),
            lifecycleState: ProjectIntakeLifecycleState(rawValue: stmt.string(at: 5)) ?? .captured,
            placementKind: ProjectIntakePlacementKind(rawValue: stmt.string(at: 6)) ?? .intake,
            intakeVisibility: stmt.string(at: 7),
            requestID: stmt.string(at: 8),
            captureKey: stmt.string(at: 9),
            schemaVersion: stmt.int(at: 10),
            nodeRevision: stmt.int(at: 11),
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 12)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 13)),
            integratedAt: stmt.optionalDouble(at: 14).map(DatabaseHelpers.decodeDate)
        )
    }

    private func bulletList(_ values: [String]) -> String {
        values.map { "- \($0)" }.joined(separator: "\n")
    }

    nonisolated private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    nonisolated private static func makeULID(date: Date) -> String {
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        var timestamp = UInt64(max(0, date.timeIntervalSince1970 * 1_000))
        var timeCharacters = Array(repeating: Character("0"), count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            timeCharacters[index] = alphabet[Int(timestamp & 31)]
            timestamp >>= 5
        }
        var generator = SystemRandomNumberGenerator()
        let randomCharacters = (0..<16).map { _ in alphabet[Int.random(in: 0..<alphabet.count, using: &generator)] }
        return String(timeCharacters + randomCharacters)
    }
}
