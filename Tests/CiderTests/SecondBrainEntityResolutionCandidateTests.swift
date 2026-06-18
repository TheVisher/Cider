import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Second Brain Entity Resolution Candidate Tests")
@MainActor
struct SecondBrainEntityResolutionCandidateTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-entity-resolution-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("entity resolution candidates are reviewable with evidence lifecycle conflicts and safe commands")
    func entityResolutionCandidatesExposeReviewableEvidenceLifecycleAndConflicts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let sourceEntity = SecondBrainOwnerRef(ownerType: "entity_alias", ownerID: "person:jami")
        let targetA = SecondBrainOwnerRef(ownerType: "contact", ownerID: UUID().uuidString)
        let targetB = SecondBrainOwnerRef(ownerType: "contact", ownerID: UUID().uuidString)
        try insertItem(ref: targetA, title: "Jami Smith", into: db)
        try insertItem(ref: targetB, title: "Jami S.", into: db)

        let service = SecondBrainEntityResolutionService(database: db, store: SecondBrainStore(database: db))
        let candidate = try service.suggest(
            candidateType: "person_alias",
            sourceEntity: sourceEntity,
            sourceLabel: "Jami",
            inputMention: "Jami",
            targetEntity: targetA,
            targetLabel: "Jami Smith",
            sourceOwner: note,
            sourceQuote: "Jami told me her mom still asks her to do hair.",
            confidence: 0.64,
            confidenceReasons: ["name_match", "journal_context"],
            conflicts: [SecondBrainEntityResolutionConflict(kind: "ambiguous_target", severity: "review", message: "Another Jami contact is also plausible.", conflictingOwner: targetB)],
            actor: "test-agent",
            source: "entity_resolution.test"
        )

        #expect(candidate.reviewState == "suggested")
        #expect(candidate.truthBoundary == "reviewable_candidate_not_truth")
        #expect(candidate.hasConflicts == true)
        #expect(candidate.conflictCount == 1)
        #expect(candidate.safeNextCommands.contains("cider-cli item entity-resolution inspect \(candidate.id) --json"))
        #expect(candidate.safeNextCommands.contains("cider-cli item entity-resolution merge \(candidate.id) --json"))

        let listed = try service.candidates(reviewStates: ["suggested"])
        #expect(listed.map(\.id).contains(candidate.id))

        let inspected = try #require(try service.candidate(id: candidate.id))
        let evidence = try #require(inspected.sourceEvidenceRecord)
        #expect(evidence.sourceOwner == note)
        #expect(evidence.sourceQuote == "Jami told me her mom still asks her to do hair.")
        #expect(evidence.candidateRef == "entity_resolution_candidate:\(candidate.id)")
        #expect(inspected.lifecycleHistory.map(\.eventKind) == ["suggested"])

        let dict = CiderCLI.entityResolutionCandidateToDict(inspected)
        #expect(dict["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect((dict["sourceEvidenceRecord"] as? [String: Any])?["candidateRef"] as? String == "entity_resolution_candidate:\(candidate.id)")
        #expect((dict["lifecycleHistory"] as? [[String: Any]])?.first?["eventKind"] as? String == "suggested")
        #expect((dict["conflicts"] as? [[String: Any]])?.first?["kind"] as? String == "ambiguous_target")
    }

    @Test("entity resolution merge is explicit and records accepted relation without mutating source candidate history")
    func entityResolutionMergeIsExplicitAndRecordsAcceptedRelation() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let sourceEntity = SecondBrainOwnerRef(ownerType: "entity_alias", ownerID: "place:cactus")
        let targetEntity = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)
        try insertItem(ref: targetEntity, title: "Cactus Restaurant", into: db)

        let store = SecondBrainStore(database: db)
        let service = SecondBrainEntityResolutionService(database: db, store: store)
        let candidate = try service.suggest(
            candidateType: "place_alias",
            sourceEntity: sourceEntity,
            sourceLabel: "Cactus",
            inputMention: "Cactus",
            targetEntity: targetEntity,
            targetLabel: "Cactus Restaurant",
            sourceOwner: note,
            sourceQuote: "We went to Cactus for dinner.",
            confidence: 0.91,
            confidenceReasons: ["exact_alias", "place_visit_context"],
            actor: "test-agent",
            source: "entity_resolution.test"
        )

        #expect(try store.outgoingRelations(for: sourceEntity).isEmpty)
        #expect(try store.backlinks(for: targetEntity).isEmpty)

        let merged = try service.merge(candidateID: candidate.id, actor: "reviewer", reason: "Confirmed Cactus mention points at saved restaurant entity.")
        #expect(merged.reviewState == "accepted")
        #expect(merged.truthBoundary == "accepted_entity_resolution")
        #expect(merged.lifecycleHistory.map(\.eventKind).contains("accepted"))

        let relations = try store.outgoingRelations(for: sourceEntity)
        let relation = try #require(relations.first { $0.targetOwner == targetEntity && $0.relationType == "entity_alias_of" })
        #expect(relation.metadata["candidate_ref"] == "entity_resolution_candidate:\(candidate.id)")
        #expect(relation.metadata["source_evidence_id"] != nil)
        #expect(relation.metadata["decision_note"] == "Confirmed Cactus mention points at saved restaurant entity.")

        let rejected = try service.reject(candidateID: candidate.id, actor: "reviewer", reason: "Duplicate review action should not undo accepted truth.")
        #expect(rejected.reviewState == "accepted")
        #expect(rejected.lifecycleHistory.map(\.eventKind).contains("accepted"))
    }

    private func insertItem(ref: SecondBrainOwnerRef, title: String, into db: CiderDatabase) throws {
        let now = DatabaseHelpers.encode(Date())
        let type = ref.ownerType == "contact" ? "contact" : "bookmark"
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(ref.ownerID, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(now, at: 4)
            .bind(now, at: 5)
            .bind("Inbox/\(title)", at: 6)
        try stmt.step()
        if type == "contact" {
            let contact = try db.prepare("INSERT INTO contacts (item_id, relationship_label, notes, email, phone, address, has_avatar, custom_fields) VALUES (?, '', '', '', '', '', 0, '[]');")
            contact.bind(ref.ownerID, at: 1)
            try contact.step()
        } else {
            let bookmark = try db.prepare("INSERT INTO bookmarks (item_id, url, notes) VALUES (?, 'https://example.com/entity', '');")
            bookmark.bind(ref.ownerID, at: 1)
            try bookmark.step()
        }
    }
}
