import Foundation

enum ProjectIntakeLifecycleState: String, Codable, CaseIterable {
    case captured
    case reviewed
    case integrated
    case deferred
    case rejected
}

enum ProjectIntakePlacementKind: String, Codable {
    case intake
    case primary
}

enum ProjectIntakeActorType: String, Codable {
    case human
    case agent
    case system
}

struct ProjectIntakeActor: Codable, Equatable {
    var type: ProjectIntakeActorType
    var id: String
}

struct ProjectIntakeApproval: Codable, Equatable {
    var actor: ProjectIntakeActor
    var explicitlyApproved: Bool
    var canApproveProject: Bool
}

enum ProjectIntakePlacement: Codable, Equatable {
    case before(String)
    case after(String)
    case between(after: String, before: String)
    case append
    case doNotIntegrate

    var mode: String {
        switch self {
        case .before: "before"
        case .after: "after"
        case .between: "between"
        case .append: "append"
        case .doNotIntegrate: "do_not_integrate"
        }
    }

    var beforeNodeID: String? {
        switch self {
        case .before(let nodeID), .between(_, let nodeID): nodeID
        default: nil
        }
    }

    var afterNodeID: String? {
        switch self {
        case .after(let nodeID), .between(let nodeID, _): nodeID
        default: nil
        }
    }

    static func stored(mode: String, beforeNodeID: String?, afterNodeID: String?) throws -> Self {
        switch mode {
        case "before":
            guard let beforeNodeID else { throw ProjectIntakeError.invalidInsertionAnchor }
            return .before(beforeNodeID)
        case "after":
            guard let afterNodeID else { throw ProjectIntakeError.invalidInsertionAnchor }
            return .after(afterNodeID)
        case "between":
            guard let afterNodeID, let beforeNodeID else { throw ProjectIntakeError.invalidInsertionAnchor }
            return .between(after: afterNodeID, before: beforeNodeID)
        case "append":
            return .append
        case "do_not_integrate":
            return .doNotIntegrate
        default:
            throw ProjectIntakeError.invalidInsertionAnchor
        }
    }
}

struct ProjectIntakeNode: Identifiable, Codable, Equatable {
    var id: String
    var projectID: String
    var kind: String
    var title: String
    var conciseSummary: String
    var lifecycle: ProjectIntakeLifecycleState
    var placement: ProjectIntakePlacementKind
    var intakeVisibility: String
    var captureKey: String
    var schemaVersion: Int
    var revision: Int
    var createdAt: Date
    var updatedAt: Date
    var integratedAt: Date?
}

struct ProjectIntakeAuthority: Codable, Equatable {
    var projectID: String
    var canonicalSummary: String
    var graphRevision: Int
    var primaryPathRevision: Int
    var canonicalSummaryRevision: Int
}

struct ProjectIntakeReviewedAgainst: Codable, Equatable {
    var canonicalSummaryRevision: Int
    var primaryPathRevision: Int
}

struct ProjectIntakeReviewProposal: Identifiable, Codable, Equatable {
    var id: String
    var nodeID: String
    var projectID: String
    var reviewedAgainst: ProjectIntakeReviewedAgainst
    var placement: ProjectIntakePlacement
    var rationale: String
    var authoritySummary: String
    var pathNodeIDs: [String]
    var createdAt: Date
}

struct ProjectIntakeCandidateReview: Codable, Equatable {
    var nodeID: String
    var placement: ProjectIntakePlacement
    var rationale: String?
}

struct ProjectIntakePrimaryPathMembership: Codable, Equatable {
    var projectID: String
    var nodeID: String
    var ordinal: Int
    var approvalEventID: String
    var integratedAt: Date
}

struct ProjectIntakeEvent: Identifiable, Codable, Equatable {
    var id: String
    var nodeID: String
    var operationID: String
    var kind: String
    var fromState: String?
    var toState: String?
    var actor: ProjectIntakeActor
    var authorityRevision: Int?
    var primaryPathRevision: Int?
    var payloadJSON: String
    var createdAt: Date
}

struct ProjectIntakeMutationReceipt: Codable, Equatable {
    var changed: Bool
    var node: ProjectIntakeNode
    var eventID: String
}

struct ProjectIntakeSnapshot: Equatable {
    var authority: ProjectIntakeAuthority
    var node: ProjectIntakeNode
    var path: [ProjectIntakePrimaryPathMembership]
    var events: [ProjectIntakeEvent]
}

enum ProjectIntakeHistoryKind: String, Codable {
    case implementation
    case reviewHistory = "review_history"
    case testing
    case acceptance

    var sectionKey: String {
        switch self {
        case .implementation: "implementation_history"
        case .reviewHistory: "review_history"
        case .testing: "testing"
        case .acceptance: "acceptance"
        }
    }

    var sectionTitle: String {
        switch self {
        case .implementation: "Implementation history"
        case .reviewHistory: "Review history"
        case .testing: "Testing"
        case .acceptance: "Acceptance"
        }
    }
}

enum ProjectIntakeError: Error, LocalizedError, Equatable {
    case nodeNotFound(String)
    case projectNotFound(String)
    case proposalRequired
    case proposalMismatch
    case invalidTransition(from: ProjectIntakeLifecycleState, to: ProjectIntakeLifecycleState)
    case humanApprovalRequired
    case approvalMismatch
    case staleAuthorityRevision(expectedSummary: Int, actualSummary: Int, expectedPath: Int, actualPath: Int)
    case invalidInsertionAnchor
    case nodeAlreadyIntegrated
    case rootSummaryInvalid
    case historyKindRequiresIntegratedNode

    var errorDescription: String? {
        switch self {
        case .nodeNotFound(let id): "Project intake node '\(id)' was not found."
        case .projectNotFound(let id): "Project '\(id)' was not found."
        case .proposalRequired: "A recorded review proposal is required."
        case .proposalMismatch: "The proposal does not belong to the current node and project."
        case .invalidTransition(let from, let to): "The project intake transition from \(from.rawValue) to \(to.rawValue) is invalid."
        case .humanApprovalRequired: "An explicit authenticated human approval is required."
        case .approvalMismatch: "The approval is not authorized for this project operation."
        case .staleAuthorityRevision: "The review proposal is stale; re-review against the current authority and path."
        case .invalidInsertionAnchor: "The proposed insertion anchor is not valid on the current project path."
        case .nodeAlreadyIntegrated: "The node is already integrated."
        case .rootSummaryInvalid: "The bounded root-summary contribution is invalid."
        case .historyKindRequiresIntegratedNode: "Implementation, testing, review, and acceptance history require an integrated node."
        }
    }
}

@MainActor
final class ProjectIntakeService {
    static let contractVersion = "project-intake/v1"

    private let database: CiderDatabase
    private let store: SecondBrainStore

    init(database: CiderDatabase = .shared, store: SecondBrainStore? = nil) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
    }

    nonisolated static func owner(nodeID: String) -> SecondBrainOwnerRef {
        SecondBrainOwnerRef(ownerType: "project_node", ownerID: nodeID)
    }

    func review(
        nodeID: String,
        expectedCanonicalSummaryRevision: Int,
        expectedPrimaryPathRevision: Int,
        placement: ProjectIntakePlacement = .append,
        rationale: String? = nil
    ) throws -> ProjectIntakeReviewProposal {
        guard let node = try node(id: nodeID) else { throw ProjectIntakeError.nodeNotFound(nodeID) }
        guard node.lifecycle != .integrated else { throw ProjectIntakeError.nodeAlreadyIntegrated }
        let authority = try authority(projectID: node.projectID)
        try requireCurrentAuthority(
            authority,
            expectedSummary: expectedCanonicalSummaryRevision,
            expectedPath: expectedPrimaryPathRevision
        )
        let path = try primaryPath(projectID: node.projectID)
        try validate(placement: placement, path: path)
        let normalizedRationale = rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultRationale = path.isEmpty
            ? "The project has no accepted path; this candidate is proposed as its first accepted node."
            : "The candidate was compared with the current authority summary and accepted path and is proposed at the specified sequence point."
        let resolvedRationale = normalizedRationale.flatMap { $0.isEmpty ? nil : $0 } ?? defaultRationale
        return ProjectIntakeReviewProposal(
            id: UUID().uuidString,
            nodeID: node.id,
            projectID: node.projectID,
            reviewedAgainst: ProjectIntakeReviewedAgainst(
                canonicalSummaryRevision: authority.canonicalSummaryRevision,
                primaryPathRevision: authority.primaryPathRevision
            ),
            placement: placement,
            rationale: resolvedRationale,
            authoritySummary: authority.canonicalSummary,
            pathNodeIDs: path.map(\.nodeID),
            createdAt: Date()
        )
    }

    func reviewCandidates(
        projectID: String,
        expectedCanonicalSummaryRevision: Int,
        expectedPrimaryPathRevision: Int,
        candidates: [ProjectIntakeCandidateReview]
    ) throws -> [ProjectIntakeReviewProposal] {
        let normalizedProjectID = SecondBrainProjectGraphService.normalizedProjectID(projectID)
        return try candidates.map { candidate in
            guard let candidateNode = try node(id: candidate.nodeID) else {
                throw ProjectIntakeError.nodeNotFound(candidate.nodeID)
            }
            guard candidateNode.projectID == normalizedProjectID else {
                throw ProjectIntakeError.proposalMismatch
            }
            return try review(
                nodeID: candidate.nodeID,
                expectedCanonicalSummaryRevision: expectedCanonicalSummaryRevision,
                expectedPrimaryPathRevision: expectedPrimaryPathRevision,
                placement: candidate.placement,
                rationale: candidate.rationale
            )
        }
    }

    func recordReview(
        _ proposal: ProjectIntakeReviewProposal,
        operationID: String,
        actor: ProjectIntakeActor,
        reopen: Bool = false
    ) throws -> ProjectIntakeMutationReceipt {
        guard actor.type == .human else { throw ProjectIntakeError.humanApprovalRequired }
        return try database.withImmediateTransaction {
            guard let currentNode = try node(id: proposal.nodeID) else {
                throw ProjectIntakeError.nodeNotFound(proposal.nodeID)
            }
            if let existing = try event(nodeID: currentNode.id, operationID: operationID) {
                return ProjectIntakeMutationReceipt(changed: false, node: currentNode, eventID: existing.id)
            }
            guard currentNode.projectID == proposal.projectID else { throw ProjectIntakeError.proposalMismatch }
            let authority = try authority(projectID: currentNode.projectID)
            try requireCurrentAuthority(
                authority,
                expectedSummary: proposal.reviewedAgainst.canonicalSummaryRevision,
                expectedPath: proposal.reviewedAgainst.primaryPathRevision
            )
            try validate(placement: proposal.placement, path: try primaryPath(projectID: currentNode.projectID))

            switch currentNode.lifecycle {
            case .captured, .reviewed, .deferred:
                break
            case .rejected:
                guard reopen else {
                    throw ProjectIntakeError.invalidTransition(from: .rejected, to: .reviewed)
                }
            case .integrated:
                throw ProjectIntakeError.invalidTransition(from: .integrated, to: .reviewed)
            }

            try persist(proposal)
            let now = Date()
            if currentNode.lifecycle == .rejected {
                try insertEvent(
                    id: UUID().uuidString,
                    nodeID: currentNode.id,
                    operationID: operationID + ":reopened",
                    kind: "reopened",
                    from: .rejected,
                    to: .rejected,
                    actor: actor,
                    authority: authority,
                    payload: ["proposal_id": proposal.id]
                )
            }
            let eventID = UUID().uuidString
            try insertEvent(
                id: eventID,
                nodeID: currentNode.id,
                operationID: operationID,
                kind: "reviewed",
                from: currentNode.lifecycle,
                to: .reviewed,
                actor: actor,
                authority: authority,
                payload: [
                    "proposal_id": proposal.id,
                    "placement_mode": proposal.placement.mode,
                    "rationale": proposal.rationale,
                ]
            )
            try updateNodeLifecycle(
                nodeID: currentNode.id,
                state: .reviewed,
                placement: .intake,
                visibility: "active",
                integratedAt: nil,
                updatedAt: now
            )
            guard let updated = try node(id: currentNode.id) else {
                throw ProjectIntakeError.nodeNotFound(currentNode.id)
            }
            return ProjectIntakeMutationReceipt(changed: true, node: updated, eventID: eventID)
        }
    }

    func transition(
        nodeID: String,
        to target: ProjectIntakeLifecycleState,
        operationID: String,
        actor: ProjectIntakeActor,
        reason: String
    ) throws -> ProjectIntakeMutationReceipt {
        guard actor.type == .human else { throw ProjectIntakeError.humanApprovalRequired }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else { throw ProjectIntakeError.approvalMismatch }
        return try database.withImmediateTransaction {
            guard let currentNode = try node(id: nodeID) else { throw ProjectIntakeError.nodeNotFound(nodeID) }
            if let existing = try event(nodeID: nodeID, operationID: operationID) {
                return ProjectIntakeMutationReceipt(changed: false, node: currentNode, eventID: existing.id)
            }
            let allowed = switch (currentNode.lifecycle, target) {
            case (.captured, .deferred), (.captured, .rejected),
                 (.reviewed, .deferred), (.reviewed, .rejected),
                 (.deferred, .rejected): true
            default: false
            }
            guard allowed else {
                throw ProjectIntakeError.invalidTransition(from: currentNode.lifecycle, to: target)
            }
            let authority = try authority(projectID: currentNode.projectID)
            let eventID = UUID().uuidString
            try insertEvent(
                id: eventID,
                nodeID: nodeID,
                operationID: operationID,
                kind: target.rawValue,
                from: currentNode.lifecycle,
                to: target,
                actor: actor,
                authority: authority,
                payload: ["reason": normalizedReason]
            )
            try updateNodeLifecycle(
                nodeID: nodeID,
                state: target,
                placement: .intake,
                visibility: target == .deferred ? "deferred" : "archived",
                integratedAt: nil,
                updatedAt: Date()
            )
            guard let updated = try node(id: nodeID) else { throw ProjectIntakeError.nodeNotFound(nodeID) }
            return ProjectIntakeMutationReceipt(changed: true, node: updated, eventID: eventID)
        }
    }

    func approveIntegration(
        proposalID: String,
        approval: ProjectIntakeApproval?,
        operationID: String,
        summaryContribution: String
    ) throws -> ProjectIntakeMutationReceipt {
        guard let approval,
              approval.actor.type == .human,
              approval.explicitlyApproved else {
            throw ProjectIntakeError.humanApprovalRequired
        }
        guard approval.canApproveProject else { throw ProjectIntakeError.approvalMismatch }
        let contribution = summaryContribution.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contribution.isEmpty, contribution.utf8.count <= 600 else {
            throw ProjectIntakeError.rootSummaryInvalid
        }

        return try database.withImmediateTransaction {
            guard let proposal = try proposal(id: proposalID) else { throw ProjectIntakeError.proposalRequired }
            guard let currentNode = try node(id: proposal.nodeID) else {
                throw ProjectIntakeError.nodeNotFound(proposal.nodeID)
            }
            if let existing = try event(nodeID: currentNode.id, operationID: operationID) {
                guard existing.kind == "integrated", currentNode.lifecycle == .integrated else {
                    throw ProjectIntakeError.approvalMismatch
                }
                return ProjectIntakeMutationReceipt(changed: false, node: currentNode, eventID: existing.id)
            }
            guard currentNode.lifecycle == .reviewed else {
                if currentNode.lifecycle == .integrated { throw ProjectIntakeError.nodeAlreadyIntegrated }
                throw ProjectIntakeError.invalidTransition(from: currentNode.lifecycle, to: .integrated)
            }
            guard currentNode.projectID == proposal.projectID else { throw ProjectIntakeError.proposalMismatch }
            let authority = try authority(projectID: currentNode.projectID)
            try requireCurrentAuthority(
                authority,
                expectedSummary: proposal.reviewedAgainst.canonicalSummaryRevision,
                expectedPath: proposal.reviewedAgainst.primaryPathRevision
            )
            let currentPath = try primaryPath(projectID: currentNode.projectID)
            try validate(placement: proposal.placement, path: currentPath)
            let insertionIndex = try insertionIndex(for: proposal.placement, path: currentPath)
            let eventID = UUID().uuidString
            let now = Date()
            let acceptedLine = "- \(currentNode.title): \(contribution) [node:\(currentNode.id)]"
            let existingSummary = authority.canonicalSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let updatedSummary = existingSummary.isEmpty ? acceptedLine : existingSummary + "\n" + acceptedLine
            guard updatedSummary.utf8.count <= 12_000 else { throw ProjectIntakeError.rootSummaryInvalid }

            let offset = currentPath.count + 1
            let park = try database.prepare("""
                UPDATE project_primary_path_memberships
                SET ordinal = ordinal + ?
                WHERE project_id = ?;
                """)
            park.bind(offset, at: 1).bind(currentNode.projectID, at: 2)
            try park.step()

            let insert = try database.prepare("""
                INSERT INTO project_primary_path_memberships
                    (project_id, node_id, ordinal, approval_event_id, integrated_at)
                VALUES (?, ?, ?, ?, ?);
                """)
            insert.bind(currentNode.projectID, at: 1)
                .bind(currentNode.id, at: 2)
                .bind(insertionIndex, at: 3)
                .bind(eventID, at: 4)
                .bind(DatabaseHelpers.encode(now), at: 5)
            try insert.step()

            var orderedNodeIDs = currentPath.map(\.nodeID)
            orderedNodeIDs.insert(currentNode.id, at: insertionIndex)
            for (ordinal, nodeID) in orderedNodeIDs.enumerated() where nodeID != currentNode.id {
                let reorder = try database.prepare("""
                    UPDATE project_primary_path_memberships
                    SET ordinal = ?
                    WHERE project_id = ? AND node_id = ?;
                    """)
                reorder.bind(ordinal, at: 1)
                    .bind(currentNode.projectID, at: 2)
                    .bind(nodeID, at: 3)
                try reorder.step()
            }

            try updateNodeLifecycle(
                nodeID: currentNode.id,
                state: .integrated,
                placement: .primary,
                visibility: "archived",
                integratedAt: now,
                updatedAt: now
            )
            let updateAuthority = try database.prepare("""
                UPDATE projects
                SET canonical_summary = ?,
                    graph_revision = graph_revision + 1,
                    primary_path_revision = primary_path_revision + 1,
                    canonical_summary_revision = canonical_summary_revision + 1,
                    updated_at = ?
                WHERE id = ?;
                """)
            updateAuthority.bind(updatedSummary, at: 1)
                .bind(DatabaseHelpers.encode(now), at: 2)
                .bind(currentNode.projectID, at: 3)
            try updateAuthority.step()

            try insertEvent(
                id: eventID,
                nodeID: currentNode.id,
                operationID: operationID,
                kind: "integrated",
                from: .reviewed,
                to: .integrated,
                actor: approval.actor,
                authority: ProjectIntakeAuthority(
                    projectID: authority.projectID,
                    canonicalSummary: updatedSummary,
                    graphRevision: authority.graphRevision + 1,
                    primaryPathRevision: authority.primaryPathRevision + 1,
                    canonicalSummaryRevision: authority.canonicalSummaryRevision + 1
                ),
                payload: [
                    "proposal_id": proposal.id,
                    "placement_mode": proposal.placement.mode,
                    "summary_contribution": contribution,
                ]
            )
            guard let updated = try node(id: currentNode.id) else {
                throw ProjectIntakeError.nodeNotFound(currentNode.id)
            }
            return ProjectIntakeMutationReceipt(changed: true, node: updated, eventID: eventID)
        }
    }

    func appendHistory(
        nodeID: String,
        kind: ProjectIntakeHistoryKind,
        operationID: String,
        actor: ProjectIntakeActor,
        detail: String
    ) throws -> ProjectIntakeMutationReceipt {
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedDetail.isEmpty else { throw ProjectIntakeError.approvalMismatch }
        return try database.withImmediateTransaction {
            guard let currentNode = try node(id: nodeID) else { throw ProjectIntakeError.nodeNotFound(nodeID) }
            if let existing = try event(nodeID: nodeID, operationID: operationID) {
                return ProjectIntakeMutationReceipt(changed: false, node: currentNode, eventID: existing.id)
            }
            guard currentNode.lifecycle == .integrated else {
                throw ProjectIntakeError.historyKindRequiresIntegratedNode
            }
            let authority = try authority(projectID: currentNode.projectID)
            let eventID = UUID().uuidString
            try insertEvent(
                id: eventID,
                nodeID: nodeID,
                operationID: operationID,
                kind: kind.rawValue,
                from: .integrated,
                to: .integrated,
                actor: actor,
                authority: authority,
                payload: ["detail": normalizedDetail]
            )
            let owner = Self.owner(nodeID: nodeID)
            let existing = try store.sections(for: owner).first { $0.sectionKey == kind.sectionKey }
            let updatedBody = [existing?.body, normalizedDetail]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            try store.upsertSection(SecondBrainSection(
                id: existing?.id ?? UUID().uuidString,
                owner: owner,
                itemID: existing?.itemID,
                sectionKey: kind.sectionKey,
                title: existing?.title ?? kind.sectionTitle,
                body: updatedBody,
                source: Self.contractVersion,
                confidence: existing?.confidence,
                metadata: existing?.metadata ?? [:],
                sortOrder: existing?.sortOrder ?? historySortOrder(kind),
                createdAt: existing?.createdAt ?? Date(),
                updatedAt: Date()
            ))
            let update = try database.prepare("""
                UPDATE project_nodes
                SET node_revision = node_revision + 1, updated_at = ?
                WHERE id = ?;
                """)
            update.bind(DatabaseHelpers.encode(Date()), at: 1).bind(nodeID, at: 2)
            try update.step()
            guard let updated = try node(id: nodeID) else { throw ProjectIntakeError.nodeNotFound(nodeID) }
            return ProjectIntakeMutationReceipt(changed: true, node: updated, eventID: eventID)
        }
    }

    func node(id: String) throws -> ProjectIntakeNode? {
        let statement = try database.prepare("""
            SELECT id, project_id, node_kind, title, concise_summary, lifecycle_state,
                   placement_kind, intake_visibility, capture_key, schema_version,
                   node_revision, created_at, updated_at, integrated_at
            FROM project_nodes
            WHERE id = ?
            LIMIT 1;
            """)
        statement.bind(id, at: 1)
        guard try statement.step() else { return nil }
        return decodeNode(statement)
    }

    func authority(projectID: String) throws -> ProjectIntakeAuthority {
        let statement = try database.prepare("""
            SELECT id, canonical_summary, graph_revision, primary_path_revision,
                   canonical_summary_revision
            FROM projects
            WHERE id = ?
            LIMIT 1;
            """)
        statement.bind(SecondBrainProjectGraphService.normalizedProjectID(projectID), at: 1)
        guard try statement.step() else { throw ProjectIntakeError.projectNotFound(projectID) }
        return ProjectIntakeAuthority(
            projectID: statement.string(at: 0),
            canonicalSummary: statement.string(at: 1),
            graphRevision: statement.int(at: 2),
            primaryPathRevision: statement.int(at: 3),
            canonicalSummaryRevision: statement.int(at: 4)
        )
    }

    func primaryPath(projectID: String) throws -> [ProjectIntakePrimaryPathMembership] {
        let statement = try database.prepare("""
            SELECT project_id, node_id, ordinal, approval_event_id, integrated_at
            FROM project_primary_path_memberships
            WHERE project_id = ?
            ORDER BY ordinal ASC;
            """)
        statement.bind(SecondBrainProjectGraphService.normalizedProjectID(projectID), at: 1)
        var memberships: [ProjectIntakePrimaryPathMembership] = []
        while try statement.step() {
            memberships.append(ProjectIntakePrimaryPathMembership(
                projectID: statement.string(at: 0),
                nodeID: statement.string(at: 1),
                ordinal: statement.int(at: 2),
                approvalEventID: statement.string(at: 3),
                integratedAt: DatabaseHelpers.decodeDate(statement.double(at: 4))
            ))
        }
        return memberships
    }

    func events(nodeID: String) throws -> [ProjectIntakeEvent] {
        let statement = try database.prepare("""
            SELECT id, node_id, operation_id, event_kind, from_state, to_state,
                   actor_type, actor_id, authority_revision, primary_path_revision,
                   payload_json, created_at
            FROM project_node_events
            WHERE node_id = ?
            ORDER BY created_at ASC, rowid ASC;
            """)
        statement.bind(nodeID, at: 1)
        var result: [ProjectIntakeEvent] = []
        while try statement.step() { result.append(decodeEvent(statement)) }
        return result
    }

    func proposal(id: String) throws -> ProjectIntakeReviewProposal? {
        let statement = try database.prepare("""
            SELECT id, node_id, project_id, canonical_summary_revision,
                   primary_path_revision, placement_mode, before_node_id,
                   after_node_id, rationale, authority_summary, path_node_ids_json,
                   created_at
            FROM project_intake_review_proposals
            WHERE id = ?
            LIMIT 1;
            """)
        statement.bind(id, at: 1)
        guard try statement.step() else { return nil }
        let placement = try ProjectIntakePlacement.stored(
            mode: statement.string(at: 5),
            beforeNodeID: statement.optionalString(at: 6),
            afterNodeID: statement.optionalString(at: 7)
        )
        return ProjectIntakeReviewProposal(
            id: statement.string(at: 0),
            nodeID: statement.string(at: 1),
            projectID: statement.string(at: 2),
            reviewedAgainst: ProjectIntakeReviewedAgainst(
                canonicalSummaryRevision: statement.int(at: 3),
                primaryPathRevision: statement.int(at: 4)
            ),
            placement: placement,
            rationale: statement.string(at: 8),
            authoritySummary: statement.string(at: 9),
            pathNodeIDs: DatabaseHelpers.decodeJSON([String].self, from: statement.optionalString(at: 10)) ?? [],
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 11))
        )
    }

    func snapshot(projectID: String, nodeID: String) throws -> ProjectIntakeSnapshot {
        guard let node = try node(id: nodeID) else { throw ProjectIntakeError.nodeNotFound(nodeID) }
        return ProjectIntakeSnapshot(
            authority: try authority(projectID: projectID),
            node: node,
            path: try primaryPath(projectID: projectID),
            events: try events(nodeID: nodeID)
        )
    }

    private func persist(_ proposal: ProjectIntakeReviewProposal) throws {
        let statement = try database.prepare("""
            INSERT OR IGNORE INTO project_intake_review_proposals (
                id, node_id, project_id, canonical_summary_revision,
                primary_path_revision, placement_mode, before_node_id,
                after_node_id, rationale, authority_summary, path_node_ids_json,
                created_at, recorded_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        statement.bind(proposal.id, at: 1)
            .bind(proposal.nodeID, at: 2)
            .bind(proposal.projectID, at: 3)
            .bind(proposal.reviewedAgainst.canonicalSummaryRevision, at: 4)
            .bind(proposal.reviewedAgainst.primaryPathRevision, at: 5)
            .bind(proposal.placement.mode, at: 6)
            .bind(proposal.placement.beforeNodeID, at: 7)
            .bind(proposal.placement.afterNodeID, at: 8)
            .bind(proposal.rationale, at: 9)
            .bind(proposal.authoritySummary, at: 10)
            .bind(DatabaseHelpers.encodeJSON(proposal.pathNodeIDs) ?? "[]", at: 11)
            .bind(DatabaseHelpers.encode(proposal.createdAt), at: 12)
            .bind(DatabaseHelpers.encode(Date()), at: 13)
        try statement.step()
    }

    private func requireCurrentAuthority(
        _ authority: ProjectIntakeAuthority,
        expectedSummary: Int,
        expectedPath: Int
    ) throws {
        guard authority.canonicalSummaryRevision == expectedSummary,
              authority.primaryPathRevision == expectedPath else {
            throw ProjectIntakeError.staleAuthorityRevision(
                expectedSummary: expectedSummary,
                actualSummary: authority.canonicalSummaryRevision,
                expectedPath: expectedPath,
                actualPath: authority.primaryPathRevision
            )
        }
    }

    private func validate(
        placement: ProjectIntakePlacement,
        path: [ProjectIntakePrimaryPathMembership]
    ) throws {
        let ids = path.map(\.nodeID)
        switch placement {
        case .before(let nodeID), .after(let nodeID):
            guard ids.contains(nodeID) else { throw ProjectIntakeError.invalidInsertionAnchor }
        case .between(let afterNodeID, let beforeNodeID):
            guard let afterIndex = ids.firstIndex(of: afterNodeID),
                  let beforeIndex = ids.firstIndex(of: beforeNodeID),
                  beforeIndex == afterIndex + 1 else {
                throw ProjectIntakeError.invalidInsertionAnchor
            }
        case .append, .doNotIntegrate:
            break
        }
    }

    private func insertionIndex(
        for placement: ProjectIntakePlacement,
        path: [ProjectIntakePrimaryPathMembership]
    ) throws -> Int {
        let ids = path.map(\.nodeID)
        switch placement {
        case .before(let nodeID):
            guard let index = ids.firstIndex(of: nodeID) else { throw ProjectIntakeError.invalidInsertionAnchor }
            return index
        case .after(let nodeID):
            guard let index = ids.firstIndex(of: nodeID) else { throw ProjectIntakeError.invalidInsertionAnchor }
            return index + 1
        case .between(let afterNodeID, let beforeNodeID):
            guard let afterIndex = ids.firstIndex(of: afterNodeID),
                  let beforeIndex = ids.firstIndex(of: beforeNodeID),
                  beforeIndex == afterIndex + 1 else {
                throw ProjectIntakeError.invalidInsertionAnchor
            }
            return beforeIndex
        case .append:
            return path.count
        case .doNotIntegrate:
            throw ProjectIntakeError.invalidInsertionAnchor
        }
    }

    private func updateNodeLifecycle(
        nodeID: String,
        state: ProjectIntakeLifecycleState,
        placement: ProjectIntakePlacementKind,
        visibility: String,
        integratedAt: Date?,
        updatedAt: Date
    ) throws {
        let statement = try database.prepare("""
            UPDATE project_nodes
            SET lifecycle_state = ?, placement_kind = ?, intake_visibility = ?,
                integrated_at = ?, node_revision = node_revision + 1, updated_at = ?
            WHERE id = ?;
            """)
        statement.bind(state.rawValue, at: 1)
            .bind(placement.rawValue, at: 2)
            .bind(visibility, at: 3)
            .bind(integratedAt.map(DatabaseHelpers.encode), at: 4)
            .bind(DatabaseHelpers.encode(updatedAt), at: 5)
            .bind(nodeID, at: 6)
        try statement.step()
    }

    private func insertEvent(
        id: String,
        nodeID: String,
        operationID: String,
        kind: String,
        from: ProjectIntakeLifecycleState,
        to: ProjectIntakeLifecycleState,
        actor: ProjectIntakeActor,
        authority: ProjectIntakeAuthority,
        payload: [String: String]
    ) throws {
        let statement = try database.prepare("""
            INSERT INTO project_node_events (
                id, node_id, operation_id, event_kind, from_state, to_state,
                actor_type, actor_id, authority_revision, primary_path_revision,
                payload_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        statement.bind(id, at: 1)
            .bind(nodeID, at: 2)
            .bind(operationID, at: 3)
            .bind(kind, at: 4)
            .bind(from.rawValue, at: 5)
            .bind(to.rawValue, at: 6)
            .bind(actor.type.rawValue, at: 7)
            .bind(actor.id, at: 8)
            .bind(authority.canonicalSummaryRevision, at: 9)
            .bind(authority.primaryPathRevision, at: 10)
            .bind(DatabaseHelpers.encodeJSON(payload) ?? "{}", at: 11)
            .bind(DatabaseHelpers.encode(Date()), at: 12)
        try statement.step()
    }

    private func event(nodeID: String, operationID: String) throws -> ProjectIntakeEvent? {
        let statement = try database.prepare("""
            SELECT id, node_id, operation_id, event_kind, from_state, to_state,
                   actor_type, actor_id, authority_revision, primary_path_revision,
                   payload_json, created_at
            FROM project_node_events
            WHERE node_id = ? AND operation_id = ?
            LIMIT 1;
            """)
        statement.bind(nodeID, at: 1).bind(operationID, at: 2)
        guard try statement.step() else { return nil }
        return decodeEvent(statement)
    }

    private func decodeNode(_ statement: SQLStatement) -> ProjectIntakeNode {
        ProjectIntakeNode(
            id: statement.string(at: 0),
            projectID: statement.string(at: 1),
            kind: statement.string(at: 2),
            title: statement.string(at: 3),
            conciseSummary: statement.string(at: 4),
            lifecycle: ProjectIntakeLifecycleState(rawValue: statement.string(at: 5)) ?? .captured,
            placement: ProjectIntakePlacementKind(rawValue: statement.string(at: 6)) ?? .intake,
            intakeVisibility: statement.string(at: 7),
            captureKey: statement.string(at: 8),
            schemaVersion: statement.int(at: 9),
            revision: statement.int(at: 10),
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 11)),
            updatedAt: DatabaseHelpers.decodeDate(statement.double(at: 12)),
            integratedAt: statement.optionalDouble(at: 13).map(DatabaseHelpers.decodeDate)
        )
    }

    private func decodeEvent(_ statement: SQLStatement) -> ProjectIntakeEvent {
        ProjectIntakeEvent(
            id: statement.string(at: 0),
            nodeID: statement.string(at: 1),
            operationID: statement.string(at: 2),
            kind: statement.string(at: 3),
            fromState: statement.optionalString(at: 4),
            toState: statement.optionalString(at: 5),
            actor: ProjectIntakeActor(
                type: ProjectIntakeActorType(rawValue: statement.string(at: 6)) ?? .system,
                id: statement.optionalString(at: 7) ?? ""
            ),
            authorityRevision: statement.optionalInt(at: 8),
            primaryPathRevision: statement.optionalInt(at: 9),
            payloadJSON: statement.string(at: 10),
            createdAt: DatabaseHelpers.decodeDate(statement.double(at: 11))
        )
    }

    private func historySortOrder(_ kind: ProjectIntakeHistoryKind) -> Int {
        switch kind {
        case .implementation: 6
        case .reviewHistory: 7
        case .testing: 8
        case .acceptance: 9
        }
    }
}
