import Foundation
import Testing
@testable import Cider

@Suite("Project Intake Capture Tests")
@MainActor
struct ProjectIntakeCaptureTests {
    private struct Fixture {
        let database: CiderDatabase
        let databaseURL: URL
        let service: SecondBrainProjectIntakeService
        let projectService: SecondBrainProjectGraphService
        let source: ProjectIntakeSourceDescriptor
    }

    private func makeFixture(projectID: String = "universal-cider", projectTitle: String = "Universal Cider") throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-project-intake-\(UUID().uuidString).db")
        let database = CiderDatabase()
        try database.open(at: url)
        let projectService = SecondBrainProjectGraphService(database: database)
        _ = try projectService.upsertProject(id: projectID, title: projectTitle)

        let repository = ConversationRepository(database: database)
        let room = try repository.createRoom(.init(stableKey: "test.project-intake", title: "Project intake source"))
        let first = try repository.upsertMessage(.init(
            roomID: room.id,
            role: "user",
            contentText: "We should preserve chat ideas as project intake."
        ), intent: .historicalReplay).message
        let last = try repository.upsertMessage(.init(
            roomID: room.id,
            role: "assistant",
            contentText: "Capture first, then review before changing the accepted path."
        ), intent: .historicalReplay).message
        let digest = SecondBrainProjectIntakeService.contentDigest(messages: [first, last])
        let source = ProjectIntakeSourceDescriptor(
            sourceOwner: SecondBrainOwnerRef(ownerType: "conversation_room", ownerID: room.id.uuidString),
            sourceKind: .ciderChapter,
            roomID: room.id.uuidString,
            chapterID: "chapter-intake",
            firstMessageID: first.id.uuidString,
            lastMessageID: last.id.uuidString,
            contentDigest: digest,
            capturedAt: Date(timeIntervalSince1970: 10_000),
            capturedBy: "erik"
        )
        return Fixture(
            database: database,
            databaseURL: url,
            service: SecondBrainProjectIntakeService(database: database),
            projectService: projectService,
            source: source
        )
    }

    private func cleanup(_ fixture: Fixture) {
        fixture.database.close()
        try? FileManager.default.removeItem(at: fixture.databaseURL)
        try? FileManager.default.removeItem(atPath: fixture.databaseURL.path + "-wal")
        try? FileManager.default.removeItem(atPath: fixture.databaseURL.path + "-shm")
    }

    private func request(
        projectRef: String = "Universal Cider",
        source: ProjectIntakeSourceDescriptor,
        requestID: String = "capture-request-1"
    ) -> ProjectIntakeCaptureRequest {
        ProjectIntakeCaptureRequest(
            projectRef: projectRef,
            source: source,
            title: "Durable chat-to-project intake",
            conciseSummary: "Preserve useful chat ideas without scheduling or reordering accepted work.",
            reasoning: "Chat contains decisions and alternatives that should remain traceable after the conversation ends.",
            decisions: ["Capture is intake, not authorization to build."],
            alternatives: ["Create a Kanban card immediately."],
            openQuestions: ["How should intake be reviewed in the UI?"],
            requestID: requestID,
            actor: "moxie"
        )
    }

    @Test("Successful capture creates one durable captured intake node")
    func successfulCapture() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }

        let receipt = try fixture.service.capture(request(projectRef: "universal-cider", source: fixture.source))
        let node = try #require(try fixture.service.node(id: receipt.node.id))
        let sections = try fixture.service.sections(nodeID: node.id)
        let relations = try fixture.service.relations(nodeID: node.id)
        let events = try fixture.service.events(nodeID: node.id)
        let state = try fixture.service.graphState(projectID: "universal-cider")

        #expect(receipt.status == .succeeded)
        #expect(receipt.changed)
        #expect(!receipt.scheduled)
        #expect(!receipt.orderedPathChanged)
        #expect(node.lifecycleState == .captured)
        #expect(node.placementKind == .intake)
        #expect(Set(sections.map(\.sectionKey)) == Set(["reasoning", "decisions", "alternatives", "open_questions", "source_provenance"]))
        #expect(relations.contains {
            $0.relationType == "contains_project_node"
                && $0.sourceOwner == SecondBrainOwnerRef(ownerType: "project", ownerID: "universal-cider")
                && $0.targetOwner == node.owner
        })
        #expect(relations.contains {
            $0.relationType == "derived_from"
                && $0.sourceOwner == node.owner
                && $0.targetOwner == fixture.source.sourceOwner
        })
        #expect(events.map(\.eventKind) == ["captured"])
        #expect(state.graphRevision == 1)
        #expect(state.primaryPathRevision == 0)
        #expect(state.intakeSummary.contains(node.id))
        #expect(state.intakeSummary.contains(node.title))
    }

    @Test("Ambiguous and nonexistent project names fail without mutation")
    func projectResolutionFailsClosed() throws {
        let fixture = try makeFixture(projectID: "cider-one", projectTitle: "Cider")
        defer { cleanup(fixture) }
        _ = try fixture.projectService.upsertProject(id: "cider-two", title: "Cider")

        do {
            _ = try fixture.service.capture(request(projectRef: "Cider", source: fixture.source))
            Issue.record("Expected ambiguous project resolution to fail")
        } catch let error as ProjectIntakeError {
            #expect(error.code == "project_ambiguous")
        }
        do {
            _ = try fixture.service.capture(request(projectRef: "Project Phoenix", source: fixture.source, requestID: "missing-project"))
            Issue.record("Expected nonexistent project resolution to fail")
        } catch let error as ProjectIntakeError {
            #expect(error.code == "project_not_found")
        }
        #expect(try fixture.service.allNodes().isEmpty)
    }

    @Test("Changed source content fails digest validation without mutation")
    func changedSourceFailsClosed() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        var changed = fixture.source
        changed.contentDigest = String(repeating: "0", count: 64)

        do {
            _ = try fixture.service.capture(request(source: changed))
            Issue.record("Expected changed source content to fail")
        } catch let error as ProjectIntakeError {
            #expect(error.code == "source_digest_mismatch")
        }
        #expect(try fixture.service.allNodes().isEmpty)
    }

    @Test("Capture requires a preserved source context")
    func missingSourceContextFailsClosed() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        var missing = fixture.source
        missing.roomID = nil
        missing.firstMessageID = nil
        missing.lastMessageID = nil

        do {
            _ = try fixture.service.capture(request(source: missing))
            Issue.record("Expected missing source context to fail")
        } catch let error as ProjectIntakeError {
            #expect(error.code == "source_required")
        }
        #expect(try fixture.service.allNodes().isEmpty)
    }

    @Test("Exact retries reuse one node and conflicting request identity fails")
    func duplicateRetriesAreIdempotent() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let capture = request(source: fixture.source)

        let first = try fixture.service.capture(capture)
        let retry = try fixture.service.capture(capture)
        var conflictingSource = fixture.source
        conflictingSource.chapterID = "another-chapter"

        #expect(first.node.id == retry.node.id)
        #expect(!retry.changed)
        #expect(retry.status == .noChange)
        #expect(try fixture.service.allNodes().count == 1)
        #expect(try fixture.service.events(nodeID: first.node.id).count == 1)
        do {
            _ = try fixture.service.capture(request(source: conflictingSource))
            Issue.record("Expected request identity conflict")
        } catch let error as ProjectIntakeError {
            #expect(error.code == "idempotency_key_conflict")
        }
        #expect(try fixture.service.allNodes().count == 1)
    }

    @Test("Source provenance and digest persist on the durable node")
    func provenancePersists() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }

        let receipt = try fixture.service.capture(request(source: fixture.source))
        let provenance = try #require(
            try fixture.service.sections(nodeID: receipt.node.id).first { $0.sectionKey == "source_provenance" }
        )
        let evidence = try #require(try fixture.service.sourceEvidence(nodeID: receipt.node.id))
        let derivedFrom = try #require(
            try fixture.service.relations(nodeID: receipt.node.id).first { $0.relationType == "derived_from" }
        )

        #expect(provenance.body.contains(fixture.source.roomID!))
        #expect(provenance.body.contains(fixture.source.chapterID!))
        #expect(provenance.body.contains(fixture.source.contentDigest))
        #expect(evidence.contentDigest == fixture.source.contentDigest)
        #expect(evidence.sourceOwner == fixture.source.sourceOwner)
        #expect(derivedFrom.targetOwner == fixture.source.sourceOwner)
        #expect(derivedFrom.metadata["content_digest"] == fixture.source.contentDigest)
    }

    @Test("Capture leaves ordered membership and primary path revision unchanged")
    func captureDoesNotChangeProjectOrdering() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        try fixture.service.seedPrimaryPathForTesting(projectID: "universal-cider", nodeIDs: ["accepted-a", "accepted-b"], revision: 7)
        let before = try fixture.service.primaryPathNodeIDs(projectID: "universal-cider")

        let receipt = try fixture.service.capture(request(source: fixture.source))
        let after = try fixture.service.primaryPathNodeIDs(projectID: "universal-cider")
        let state = try fixture.service.graphState(projectID: "universal-cider")

        #expect(before == ["accepted-a", "accepted-b"])
        #expect(after == before)
        #expect(!after.contains(receipt.node.id))
        #expect(state.primaryPathRevision == 7)
        #expect(!receipt.orderedPathChanged)
        #expect(!receipt.scheduled)
    }
}
