import Foundation
import Testing
@testable import Cider

struct AgentRoomsContextCheckpointTests {
    private let noteID = UUID(uuidString: "A1000000-0000-4000-8000-000000000001")!
    private let bookmarkID = UUID(uuidString: "A1000000-0000-4000-8000-000000000002")!

    @MainActor
    @Test("context checkpoint distinguishes selected context from citations")
    func contextCheckpointDistinguishesSelectedContextFromCitations() throws {
        let note = reference(kind: "note", id: noteID.uuidString, title: "Daily context")
        let bookmark = reference(kind: "bookmark", id: bookmarkID.uuidString, title: "Source bookmark")
        let checkpoint = HermesCiderContextCheckpoint(
            id: "checkpoint-1",
            selected: [note, bookmark],
            citations: [bookmark],
            omissionReason: nil,
            source: "cider",
            sourceRef: "context_checkpoint:checkpoint-1"
        )

        let projected = AgentRoomsContextCheckpointProjector.project(
            factState: .validated,
            checkpoint: checkpoint,
            bookmarkThumbnail: { _ in nil }
        )
        let projection = try #require(projected)

        #expect(projection.state == .available)
        #expect(projection.selectedContext.map(\.openRoute.stableIdentity) == [
            "bookmark:\(bookmarkID.uuidString)",
            "note:\(noteID.uuidString)",
        ])
        #expect(projection.citations.map(\.openRoute.stableIdentity) == [
            "bookmark:\(bookmarkID.uuidString)",
        ])
        #expect(projection.truthBoundary == "Selected context and citations do not independently verify assistant prose")
    }

    @MainActor
    @Test("unreported and rejected context expose bounded omission truth without payload")
    func contextOmissionTruthIsBounded() throws {
        let unreportedProjection = AgentRoomsContextCheckpointProjector.project(
            factState: .notReported,
            checkpoint: nil,
            bookmarkThumbnail: { _ in nil }
        )
        let unreported = try #require(unreportedProjection)
        #expect(unreported.state == .omitted)
        #expect(unreported.selectedContext.isEmpty)
        #expect(unreported.citations.isEmpty)
        #expect(unreported.detail == "No structured Cider context checkpoint was reported for this turn.")

        let rejectedProjection = AgentRoomsContextCheckpointProjector.project(
            factState: .rejected,
            checkpoint: nil,
            bookmarkThumbnail: { _ in nil }
        )
        let rejected = try #require(rejectedProjection)
        #expect(rejected.state == .rejected)
        #expect(rejected.detail == "Cider withheld unsupported or malformed context details.")
        #expect(!rejected.detail.contains("/Users/"))
    }

    @MainActor
    @Test("context projection rejects cross-set and conflicting identities without partial rows")
    func contextProjectionFailsClosed() {
        let note = reference(kind: "note", id: noteID.uuidString, title: "Daily context")
        let conflicting = reference(kind: "note", id: noteID.uuidString, title: "Different title")
        let bookmark = reference(kind: "bookmark", id: bookmarkID.uuidString, title: "Unselected citation")
        let privateTitle = reference(kind: "note", id: noteID.uuidString, title: "/Users/private/.env")

        #expect(AgentRoomsContextCheckpointProjector.project(
            factState: .validated,
            checkpoint: .init(
                id: "checkpoint-cross-set",
                selected: [note],
                citations: [bookmark],
                omissionReason: nil,
                source: "cider",
                sourceRef: "context_checkpoint:checkpoint-cross-set"
            ),
            bookmarkThumbnail: { _ in nil }
        ) == nil)
        #expect(AgentRoomsContextCheckpointProjector.project(
            factState: .validated,
            checkpoint: .init(
                id: "checkpoint-private",
                selected: [privateTitle],
                citations: [],
                omissionReason: nil,
                source: "cider",
                sourceRef: "context_checkpoint:checkpoint-private"
            ),
            bookmarkThumbnail: { _ in nil }
        ) == nil)
        #expect(AgentRoomsContextCheckpointProjector.project(
            factState: .validated,
            checkpoint: .init(
                id: "checkpoint-conflict",
                selected: [note, conflicting],
                citations: [],
                omissionReason: nil,
                source: "cider",
                sourceRef: "context_checkpoint:checkpoint-conflict"
            ),
            bookmarkThumbnail: { _ in nil }
        ) == nil)
    }

    @MainActor
    @Test("approval projection is read-only, scoped, source-backed, and canonical-target aware")
    func approvalProjectionIsBoundedAndReadOnly() throws {
        let target = reference(kind: "note", id: noteID.uuidString, title: "Trip plan")
        let request = HermesApprovalRequest(
            id: "approval-1",
            action: "Update note",
            target: target,
            risk: "medium",
            scope: "write",
            status: "requested",
            source: "hermes_runs_api",
            sourceRef: "approval:approval-1"
        )

        let rows = try #require(AgentRoomsApprovalProjector.project(
            factState: .validated,
            requests: [request]
        ))
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.action == "Update note")
        #expect(row.target == "Trip plan · Note")
        #expect(row.risk == .medium)
        #expect(row.scope == .write)
        #expect(row.status == .requested)
        #expect(row.provenance == "Hermes Runs API · Source-backed request")
        #expect(row.isReadOnly)
    }

    @MainActor
    @Test("approval projection rejects paths, credentials, conflicts, and raw transport shapes")
    func approvalProjectionFailsClosed() {
        let unsafe = HermesApprovalRequest(
            id: "approval-unsafe",
            action: "Edit /Users/private/.env API_KEY=secret",
            target: nil,
            risk: "high",
            scope: "write",
            status: "requested",
            source: "hermes_runs_api",
            sourceRef: "approval:approval-unsafe"
        )
        let first = HermesApprovalRequest(
            id: "approval-conflict",
            action: "Update note",
            target: reference(kind: "note", id: noteID.uuidString, title: "Trip plan"),
            risk: "medium",
            scope: "write",
            status: "requested",
            source: "hermes_runs_api",
            sourceRef: "approval:approval-conflict"
        )
        let conflicting = HermesApprovalRequest(
            id: "approval-conflict",
            action: "Delete note",
            target: reference(kind: "note", id: noteID.uuidString, title: "Trip plan"),
            risk: "critical",
            scope: "delete",
            status: "requested",
            source: "hermes_runs_api",
            sourceRef: "approval:approval-conflict"
        )

        #expect(AgentRoomsApprovalProjector.project(factState: .validated, requests: [unsafe]) == nil)
        #expect(AgentRoomsApprovalProjector.project(factState: .validated, requests: [first, conflicting]) == nil)
        #expect(AgentRoomsApprovalProjector.project(factState: .rejected, requests: [first]) == nil)
    }

    private func reference(kind: String, id: String, title: String) -> HermesCiderReference {
        HermesCiderReference(
            kind: kind,
            id: id,
            title: title,
            boardID: nil,
            projectID: nil,
            artifactType: nil,
            source: "cider",
            sourceRef: "\(kind):\(id)"
        )
    }
}
