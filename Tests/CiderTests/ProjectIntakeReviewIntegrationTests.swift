import Foundation
import Testing
@testable import Cider

@Suite("Project Intake Review and Integration Tests")
@MainActor
struct ProjectIntakeReviewIntegrationTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-project-intake-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeFixture() throws -> (CiderDatabase, URL, ProjectIntakeService) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        let graph = SecondBrainProjectGraphService(database: db)
        _ = try graph.upsertProject(id: "cider", title: "Cider")
        try db.runSQL("""
            UPDATE projects
            SET canonical_summary = 'Build the graph foundation, then ship chat.',
                graph_revision = 2,
                primary_path_revision = 2,
                canonical_summary_revision = 4
            WHERE id = 'cider';
            """)
        try seedNode(db, id: "foundation", state: .integrated, placement: .primary, title: "Graph Foundation")
        try seedNode(db, id: "chat", state: .integrated, placement: .primary, title: "Cider Chat")
        try seedNode(db, id: "idea", state: .captured, placement: .intake, title: "Chat Project Intake")
        try db.runSQL("""
            INSERT INTO project_primary_path_memberships
                (project_id, node_id, ordinal, approval_event_id, integrated_at)
            VALUES
                ('cider', 'foundation', 0, 'approval-foundation', 1),
                ('cider', 'chat', 1, 'approval-chat', 2);
            """)
        let store = SecondBrainStore(database: db)
        let ideaOwner = ProjectIntakeService.owner(nodeID: "idea")
        try store.upsertSection(SecondBrainSection(
            owner: ideaOwner,
            sectionKey: "reasoning",
            title: "Reasoning",
            body: "Keep chat-derived ideas attached to project authority.",
            source: "test",
            sortOrder: 0
        ))
        try store.upsertSection(SecondBrainSection(
            owner: ideaOwner,
            sectionKey: "implementation_history",
            title: "Implementation history",
            body: "Initial prototype preserved.",
            source: "test",
            sortOrder: 6
        ))
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainProjectGraphService.owner(projectID: "cider"),
            targetOwner: ideaOwner,
            relationType: "contains_project_node",
            evidence: "Captured for Cider.",
            source: "project_intake/v1",
            actor: "system",
            confidence: 1
        ))
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: ideaOwner,
            targetOwner: SecondBrainOwnerRef(ownerType: "conversation_chapter", ownerID: "chapter-1"),
            relationType: "derived_from",
            evidence: "Captured from chapter 1.",
            source: "project_intake/v1",
            actor: "system",
            confidence: 1
        ))
        try seedEvent(db, id: "captured-event", nodeID: "idea", kind: "captured")
        return (db, url, ProjectIntakeService(database: db))
    }

    private func seedNode(
        _ db: CiderDatabase,
        id: String,
        state: ProjectIntakeLifecycleState,
        placement: ProjectIntakePlacementKind,
        title: String
    ) throws {
        let statement = try db.prepare("""
            INSERT INTO project_nodes (
                id, project_id, node_kind, title, concise_summary, lifecycle_state,
                placement_kind, intake_visibility, capture_key, schema_version,
                node_revision, created_at, updated_at, integrated_at
            ) VALUES (?, 'cider', 'idea', ?, ?, ?, ?, ?, ?, 1, 1, 1, 1, ?);
            """)
        statement.bind(id, at: 1)
            .bind(title, at: 2)
            .bind("Summary for \(title).", at: 3)
            .bind(state.rawValue, at: 4)
            .bind(placement.rawValue, at: 5)
            .bind(state == .integrated ? "archived" : "active", at: 6)
            .bind("capture-\(id)", at: 7)
            .bind(state == .integrated ? 1.0 : nil, at: 8)
        try statement.step()
    }

    private func seedEvent(_ db: CiderDatabase, id: String, nodeID: String, kind: String) throws {
        let statement = try db.prepare("""
            INSERT INTO project_node_events (
                id, node_id, operation_id, event_kind, from_state, to_state,
                actor_type, actor_id, payload_json, created_at
            ) VALUES (?, ?, ?, ?, NULL, ?, 'system', 'fixture', '{}', 1);
            """)
        statement.bind(id, at: 1)
            .bind(nodeID, at: 2)
            .bind("operation-\(id)", at: 3)
            .bind(kind, at: 4)
            .bind(kind, at: 5)
        try statement.step()
    }

    private let human = ProjectIntakeActor(type: .human, id: "erik")
    private let agent = ProjectIntakeActor(type: .agent, id: "moxie")

    @Test("Audit compares against authority and path without modifying graph")
    func auditIsReadOnly() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }

        let before = try service.snapshot(projectID: "cider", nodeID: "idea")
        let proposal = try service.review(
            nodeID: "idea",
            expectedCanonicalSummaryRevision: 4,
            expectedPrimaryPathRevision: 2,
            placement: .between(after: "foundation", before: "chat"),
            rationale: "Intake depends on graph authority and should precede chat automation."
        )
        let after = try service.snapshot(projectID: "cider", nodeID: "idea")

        #expect(proposal.reviewedAgainst.canonicalSummaryRevision == 4)
        #expect(proposal.reviewedAgainst.primaryPathRevision == 2)
        #expect(proposal.pathNodeIDs == ["foundation", "chat"])
        #expect(proposal.authoritySummary.contains("graph foundation"))
        #expect(before == after)
        #expect(try service.proposal(id: proposal.id) == nil)
    }

    @Test("Review recording enforces transitions and rejected reopen authorization")
    func transitionRulesAndReopenGate() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }

        let proposal = try service.review(
            nodeID: "idea",
            expectedCanonicalSummaryRevision: 4,
            expectedPrimaryPathRevision: 2,
            placement: .append,
            rationale: "Append after the current accepted path."
        )
        _ = try service.recordReview(proposal, operationID: "review-1", actor: human)
        _ = try service.transition(nodeID: "idea", to: .rejected, operationID: "reject-1", actor: human, reason: "Not now")

        #expect(throws: ProjectIntakeError.self) {
            _ = try service.recordReview(proposal, operationID: "reopen-agent", actor: agent, reopen: true)
        }
        #expect(throws: ProjectIntakeError.self) {
            _ = try service.recordReview(proposal, operationID: "reopen-no-flag", actor: human)
        }
        _ = try service.recordReview(proposal, operationID: "reopen-human", actor: human, reopen: true)

        let events = try service.events(nodeID: "idea")
        #expect(events.map(\.kind).suffix(2) == ["reopened", "reviewed"])
        #expect(try service.node(id: "idea")?.lifecycle == .reviewed)
        #expect(throws: ProjectIntakeError.self) {
            _ = try service.transition(nodeID: "idea", to: .captured, operationID: "backward", actor: human, reason: "No")
        }
    }

    @Test("Integration requires explicit authorized human approval")
    func integrationApprovalGate() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }
        let proposal = try reviewedProposal(service)

        #expect(throws: ProjectIntakeError.self) {
            _ = try service.approveIntegration(
                proposalID: proposal.id,
                approval: nil,
                operationID: "approve-none",
                summaryContribution: "Accept chat-derived project intake."
            )
        }
        #expect(throws: ProjectIntakeError.self) {
            _ = try service.approveIntegration(
                proposalID: proposal.id,
                approval: ProjectIntakeApproval(actor: agent, explicitlyApproved: true, canApproveProject: true),
                operationID: "approve-agent",
                summaryContribution: "Accept chat-derived project intake."
            )
        }
        #expect(throws: ProjectIntakeError.self) {
            _ = try service.approveIntegration(
                proposalID: proposal.id,
                approval: ProjectIntakeApproval(actor: human, explicitlyApproved: false, canApproveProject: true),
                operationID: "looks-good",
                summaryContribution: "Accept chat-derived project intake."
            )
        }
        #expect(try service.node(id: "idea")?.lifecycle == .reviewed)
        #expect(try service.primaryPath(projectID: "cider").map(\.nodeID) == ["foundation", "chat"])
    }

    @Test("Stale plan conflicts roll back every integration effect")
    func stalePlanConflictIsAtomic() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }
        let proposal = try reviewedProposal(service)
        try db.runSQL("UPDATE projects SET primary_path_revision = 3 WHERE id = 'cider';")
        let before = try service.snapshot(projectID: "cider", nodeID: "idea")

        #expect(throws: ProjectIntakeError.self) {
            _ = try service.approveIntegration(
                proposalID: proposal.id,
                approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
                operationID: "approve-stale",
                summaryContribution: "Accept chat-derived project intake."
            )
        }
        let after = try service.snapshot(projectID: "cider", nodeID: "idea")
        #expect(before == after)
        #expect(try service.events(nodeID: "idea").map(\.kind) == ["captured", "reviewed"])
    }

    @Test("Approved integration preserves identity, provenance, history, placement, and bounded summary")
    func integrationPreservesDurableNode() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }
        let proposal = try reviewedProposal(service)
        let owner = ProjectIntakeService.owner(nodeID: "idea")
        let store = SecondBrainStore(database: db)
        let sectionsBefore = try store.sections(for: owner)
        let relationsBefore = try store.relatedRelations(for: owner)

        let receipt = try service.approveIntegration(
            proposalID: proposal.id,
            approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
            operationID: "approve-1",
            summaryContribution: "Accept chat-derived ideas after graph authority and before chat automation."
        )

        #expect(receipt.changed)
        #expect(receipt.node.id == "idea")
        #expect(receipt.node.lifecycle == .integrated)
        #expect(receipt.node.placement == .primary)
        #expect(try service.primaryPath(projectID: "cider").map(\.nodeID) == ["foundation", "idea", "chat"])
        #expect(try store.sections(for: owner) == sectionsBefore)
        #expect(try store.relatedRelations(for: owner) == relationsBefore)
        #expect(try service.events(nodeID: "idea").map(\.kind) == ["captured", "reviewed", "integrated"])
        let authority = try service.authority(projectID: "cider")
        #expect(authority.canonicalSummary.contains("Chat Project Intake"))
        #expect(authority.canonicalSummary.contains("[node:idea]"))
        #expect(authority.primaryPathRevision == 3)
        #expect(authority.canonicalSummaryRevision == 5)
        #expect(authority.graphRevision == 3)

        let retry = try service.approveIntegration(
            proposalID: proposal.id,
            approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
            operationID: "approve-1",
            summaryContribution: "Accept chat-derived ideas after graph authority and before chat automation."
        )
        #expect(!retry.changed)
        #expect(try service.events(nodeID: "idea").filter { $0.kind == "integrated" }.count == 1)
    }

    @Test("Placement modes maintain contiguous order")
    func placementModes() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }
        let proposal = try service.review(
            nodeID: "idea",
            expectedCanonicalSummaryRevision: 4,
            expectedPrimaryPathRevision: 2,
            placement: .before("foundation"),
            rationale: "This work must establish intake before the foundation sequence."
        )
        _ = try service.recordReview(proposal, operationID: "review-before", actor: human)
        _ = try service.approveIntegration(
            proposalID: proposal.id,
            approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
            operationID: "approve-before",
            summaryContribution: "Establish intake before the existing path."
        )

        let path = try service.primaryPath(projectID: "cider")
        #expect(path.map(\.nodeID) == ["idea", "foundation", "chat"])
        #expect(path.map(\.ordinal) == [0, 1, 2])
    }

    @Test("After and append placements remain deterministic")
    func afterAndAppendPlacements() throws {
        for (placement, expectedPath, suffix) in [
            (ProjectIntakePlacement.after("foundation"), ["foundation", "idea", "chat"], "after"),
            (ProjectIntakePlacement.append, ["foundation", "chat", "idea"], "append"),
        ] {
            let (db, url, service) = try makeFixture()
            defer { db.close(); cleanup(url) }
            let proposal = try service.review(
                nodeID: "idea",
                expectedCanonicalSummaryRevision: 4,
                expectedPrimaryPathRevision: 2,
                placement: placement,
                rationale: "Exercise deterministic \(suffix) placement."
            )
            _ = try service.recordReview(proposal, operationID: "review-\(suffix)", actor: human)
            _ = try service.approveIntegration(
                proposalID: proposal.id,
                approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
                operationID: "approve-\(suffix)",
                summaryContribution: "Accept the \(suffix) placement."
            )
            #expect(try service.primaryPath(projectID: "cider").map(\.nodeID) == expectedPath)
        }
    }

    @Test("Bulk audit remains read-only and summary validation fails atomically")
    func bulkAuditAndSummaryBounds() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }
        let before = try service.snapshot(projectID: "cider", nodeID: "idea")
        let proposals = try service.reviewCandidates(
            projectID: "cider",
            expectedCanonicalSummaryRevision: 4,
            expectedPrimaryPathRevision: 2,
            candidates: [ProjectIntakeCandidateReview(
                nodeID: "idea",
                placement: .append,
                rationale: "Audit the candidate against the accepted sequence."
            )]
        )
        #expect(proposals.count == 1)
        #expect(try service.snapshot(projectID: "cider", nodeID: "idea") == before)
        _ = try service.recordReview(proposals[0], operationID: "review-bounds", actor: human)
        let reviewed = try service.snapshot(projectID: "cider", nodeID: "idea")
        #expect(throws: ProjectIntakeError.self) {
            _ = try service.approveIntegration(
                proposalID: proposals[0].id,
                approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
                operationID: "approve-unbounded",
                summaryContribution: String(repeating: "x", count: 601)
            )
        }
        #expect(try service.snapshot(projectID: "cider", nodeID: "idea") == reviewed)
    }

    @Test("Implementation and acceptance history continues on the integrated node")
    func historyContinuesAfterIntegration() throws {
        let (db, url, service) = try makeFixture()
        defer { db.close(); cleanup(url) }
        let proposal = try reviewedProposal(service)
        _ = try service.approveIntegration(
            proposalID: proposal.id,
            approval: ProjectIntakeApproval(actor: human, explicitlyApproved: true, canApproveProject: true),
            operationID: "approve-history",
            summaryContribution: "Accept chat-derived project intake."
        )
        _ = try service.appendHistory(
            nodeID: "idea",
            kind: .implementation,
            operationID: "implementation-1",
            actor: agent,
            detail: "Implemented the first service slice."
        )
        _ = try service.appendHistory(
            nodeID: "idea",
            kind: .testing,
            operationID: "testing-1",
            actor: agent,
            detail: "Automated tests passed."
        )
        _ = try service.appendHistory(
            nodeID: "idea",
            kind: .acceptance,
            operationID: "acceptance-1",
            actor: human,
            detail: "Accepted for the project path."
        )

        #expect(try service.node(id: "idea")?.id == "idea")
        #expect(try service.events(nodeID: "idea").map(\.kind) == [
            "captured", "reviewed", "integrated", "implementation", "testing", "acceptance"
        ])
        let sections = try SecondBrainStore(database: db).sections(for: ProjectIntakeService.owner(nodeID: "idea"))
        #expect(sections.first { $0.sectionKey == "implementation_history" }?.body.contains("first service slice") == true)
        #expect(sections.first { $0.sectionKey == "testing" }?.body.contains("Automated tests passed") == true)
        #expect(sections.first { $0.sectionKey == "acceptance" }?.body.contains("Accepted for the project path") == true)
    }

    private func reviewedProposal(_ service: ProjectIntakeService) throws -> ProjectIntakeReviewProposal {
        let proposal = try service.review(
            nodeID: "idea",
            expectedCanonicalSummaryRevision: 4,
            expectedPrimaryPathRevision: 2,
            placement: .between(after: "foundation", before: "chat"),
            rationale: "Intake belongs between graph authority and chat automation."
        )
        _ = try service.recordReview(proposal, operationID: "review-1", actor: human)
        return proposal
    }
}
