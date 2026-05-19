import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Reference Extraction Tests")
@MainActor
struct SecondBrainReferenceExtractionTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reference-extraction-\(UUID().uuidString).db")
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

    @Test("Explicit card and note references rebuild into owner relations")
    func explicitReferencesBecomeRelations() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let source = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let store = SecondBrainStore(database: db)
        let extractor = SecondBrainReferenceExtractionService(store: store)

        let result = try extractor.rebuild(
            sourceOwner: source,
            surface: "note",
            title: "Audit follow-up",
            text: "This cites card 663943 and note 504E0686 for context."
        )

        #expect(result.relations.count == 2)
        let outgoing = try store.outgoingRelations(for: source)
        #expect(outgoing.count == 2)
        #expect(outgoing.contains { $0.targetOwner.ownerType == "kanban_card" && ($0.targetOwner.ownerID == "663943" || $0.targetOwner.ownerID.hasSuffix("/663943")) })
        #expect(outgoing.contains { $0.targetOwner.ownerType == "note" && $0.targetOwner.ownerID.lowercased().hasPrefix("504e0686") })
        #expect(outgoing.allSatisfy { $0.source == "reference_extraction.note" })
        #expect(outgoing.allSatisfy { !$0.evidence.isEmpty })
    }

    @Test("Reference rebuild is idempotent and removes stale extracted relations")
    func rebuildReplacesExtractedRelations() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let source = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board/card")
        let store = SecondBrainStore(database: db)
        let extractor = SecondBrainReferenceExtractionService(store: store)

        _ = try extractor.rebuild(
            sourceOwner: source,
            surface: "kanban_card",
            title: "Plan",
            text: "Depends on note CF06DD4E."
        )
        #expect(try store.outgoingRelations(for: source).count == 1)

        _ = try extractor.rebuild(
            sourceOwner: source,
            surface: "kanban_card",
            title: "Plan",
            text: "No explicit references remain."
        )
        #expect(try store.outgoingRelations(for: source).isEmpty)
    }

    @Test("Markdown links and Cider URLs extract queryable targets")
    func markdownLinksExtractTargets() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let source = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let store = SecondBrainStore(database: db)
        let extractor = SecondBrainReferenceExtractionService(store: store)

        _ = try extractor.rebuild(
            sourceOwner: source,
            surface: "note",
            title: nil,
            text: """
            See [roadmap card](cider://item/card/3d45ca/15a5a4) and [source](https://example.com/audit).
            """
        )

        let outgoing = try store.outgoingRelations(for: source)
        #expect(outgoing.count == 2)
        #expect(outgoing.contains { $0.targetOwner == SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "3d45ca/15a5a4") })
        #expect(outgoing.contains { $0.targetOwner == SecondBrainOwnerRef(ownerType: "url", ownerID: "https://example.com/audit") })
    }
}
