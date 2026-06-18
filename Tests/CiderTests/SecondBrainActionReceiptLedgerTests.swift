import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Second Brain Action Receipt Ledger Tests")
@MainActor
struct SecondBrainActionReceiptLedgerTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-action-ledger-\(UUID().uuidString).db")
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func cleanup(_ url: URL) {
        let path = url.path
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    @Test("schema creates action receipts table")
    func schemaCreatesActionReceiptsTable() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }

        let stmt = try db.prepare("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='action_receipts';")
        try stmt.step()
        #expect(stmt.int(at: 0) == 1)
    }

    @Test("service records lists inspects and filters action receipts")
    func serviceRecordsListsInspectsAndFiltersActionReceipts() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let service = SecondBrainActionReceiptLedgerService(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "dateCard", ownerID: UUID().uuidString)
        let otherOwner = SecondBrainOwnerRef(ownerType: "todo", ownerID: UUID().uuidString)

        let readOnly = SecondBrainActionReceiptRecord(
            command: "item.why-surfaced",
            action: "inspect_surfacing",
            actor: "cider-cli",
            status: "succeeded",
            owner: owner,
            sourceRefs: [owner.canonicalRef],
            evidenceRefs: ["source_evidence:e1"],
            readOnly: true,
            changed: false,
            safeVerificationCommands: ["cider-cli item why-surfaced dateCard \(owner.ownerID) --json"],
            safeNextCommands: ["cider-cli item context dateCard \(owner.ownerID) --json"],
            correlationID: "run-1"
        )
        let mutation = SecondBrainActionReceiptRecord(
            command: "reminder.complete",
            action: "complete",
            actor: "cider-cli",
            status: "succeeded",
            owner: owner,
            sourceRefs: [owner.canonicalRef],
            evidenceRefs: [],
            readOnly: false,
            changed: true,
            beforeJSON: "{\"completed\":false}",
            afterJSON: "{\"completed\":true}",
            safeVerificationCommands: ["cider-cli item why-surfaced dateCard \(owner.ownerID) --json"],
            safeNextCommands: ["cider-cli item due-to-surface --json"],
            correlationID: "run-1"
        )
        let failure = SecondBrainActionReceiptRecord(
            command: "item.why-surfaced",
            action: "inspect_surfacing",
            actor: "cider-cli",
            status: "failed",
            owner: otherOwner,
            sourceRefs: [],
            evidenceRefs: [],
            readOnly: true,
            changed: false,
            errorCode: "unsupported_item_type",
            safeVerificationCommands: ["cider-cli item due-to-surface --json"],
            safeNextCommands: []
        )

        let readID = try service.record(readOnly)
        _ = try service.record(mutation)
        _ = try service.record(failure)

        let ownerEntries = try service.list(filter: .init(owner: owner, limit: 10))
        #expect(ownerEntries.map(\.command).contains("item.why-surfaced"))
        #expect(ownerEntries.map(\.command).contains("reminder.complete"))
        #expect(ownerEntries.allSatisfy { $0.owner == owner })
        #expect(ownerEntries.contains { $0.evidenceRefs == ["source_evidence:e1"] && $0.readOnly && !$0.changed })
        #expect(ownerEntries.contains { $0.action == "complete" && $0.changed && $0.beforeJSON?.contains("false") == true })

        let failures = try service.list(filter: .init(status: "failed", limit: 10))
        #expect(failures.count == 1)
        #expect(failures.first?.errorCode == "unsupported_item_type")

        let inspected = try #require(try service.inspect(id: readID))
        #expect(inspected.command == "item.why-surfaced")
        #expect(inspected.safeVerificationCommands == ["cider-cli item why-surfaced dateCard \(owner.ownerID) --json"])
    }

    @Test("service filters action receipts by command refs and time windows")
    func serviceFiltersActionReceiptsByCommandRefsAndTimeWindows() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let service = SecondBrainActionReceiptLedgerService(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let sourceRef = "fact_validity_candidate:cid-531"
        let evidenceRef = "source_evidence:cid-531"
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        let middle = Date(timeIntervalSince1970: 1_700_000_100)
        let newest = Date(timeIntervalSince1970: 1_700_000_200)

        _ = try service.record(SecondBrainActionReceiptRecord(
            command: "item.fact-validity.inspect",
            action: "inspect",
            actor: "cider-cli",
            status: "failed",
            owner: owner,
            sourceRefs: [sourceRef],
            evidenceRefs: [evidenceRef],
            readOnly: true,
            changed: false,
            errorCode: "fact_validity_candidate_not_found",
            safeVerificationCommands: [],
            safeNextCommands: [],
            createdAt: old
        ))
        _ = try service.record(SecondBrainActionReceiptRecord(
            command: "item.fact-validity.accept",
            action: "accept",
            actor: "cider-cli",
            status: "succeeded",
            owner: owner,
            sourceRefs: [sourceRef],
            evidenceRefs: [evidenceRef],
            readOnly: false,
            changed: true,
            safeVerificationCommands: [],
            safeNextCommands: [],
            createdAt: middle
        ))
        _ = try service.record(SecondBrainActionReceiptRecord(
            command: "item.entity-resolution.inspect",
            action: "inspect",
            actor: "cider-cli",
            status: "succeeded",
            owner: owner,
            sourceRefs: ["entity_resolution_candidate:cid-531"],
            evidenceRefs: [],
            readOnly: true,
            changed: false,
            safeVerificationCommands: [],
            safeNextCommands: [],
            createdAt: newest
        ))

        let commandMatches = try service.list(filter: .init(command: "item.fact-validity.inspect", limit: 10))
        #expect(commandMatches.map(\.command) == ["item.fact-validity.inspect"])
        #expect(commandMatches.first?.errorCode == "fact_validity_candidate_not_found")

        let refMatches = try service.list(filter: .init(sourceRef: sourceRef, evidenceRef: evidenceRef, limit: 10))
        #expect(refMatches.map(\.command) == ["item.fact-validity.accept", "item.fact-validity.inspect"])

        let windowMatches = try service.list(filter: .init(owner: owner, since: old.addingTimeInterval(50), before: newest, limit: 10))
        #expect(windowMatches.map(\.command) == ["item.fact-validity.accept"])

        let limited = try service.list(filter: .init(owner: owner, limit: 2))
        #expect(limited.map(\.command) == ["item.entity-resolution.inspect", "item.fact-validity.accept"])
    }

    @Test("ledger recording does not silently accept graph candidates")
    func ledgerRecordingDoesNotSilentlyAcceptGraphCandidates() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let service = SecondBrainActionReceiptLedgerService(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)

        let insert = try db.prepare("""
            INSERT INTO enrichment_outputs (id, owner_type, owner_id, kind, value, normalized_value, evidence, confidence, source, review_state, metadata, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        insert.bind(UUID().uuidString, at: 1)
            .bind(owner.ownerType, at: 2)
            .bind(owner.ownerID, at: 3)
            .bind("graph_candidate", at: 4)
            .bind("Cactus", at: 5)
            .bind("cactus", at: 6)
            .bind("We went to Cactus", at: 7)
            .bind(0.6, at: 8)
            .bind("test", at: 9)
            .bind("suggested", at: 10)
            .bind("{}", at: 11)
            .bind(Date().timeIntervalSince1970, at: 12)
            .bind(Date().timeIntervalSince1970, at: 13)
        try insert.step()

        _ = try service.record(SecondBrainActionReceiptRecord(
            command: "item.why-surfaced",
            action: "inspect_surfacing",
            actor: "cider-cli",
            status: "succeeded",
            owner: owner,
            sourceRefs: [owner.canonicalRef],
            evidenceRefs: [],
            readOnly: true,
            changed: false,
            safeVerificationCommands: [],
            safeNextCommands: []
        ))

        let count = try db.prepare("SELECT count(*) FROM enrichment_outputs WHERE kind='graph_candidate' AND review_state='accepted';")
        try count.step()
        #expect(count.int(at: 0) == 0)
    }

    @Test("CLI JSON dictionaries expose ledger-compatible receipt records")
    func cliReceiptDictionaryCanRoundTripThroughLedger() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let service = SecondBrainActionReceiptLedgerService(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "todo", ownerID: UUID().uuidString)
        let receipt = agentActionReceiptToDict(
            command: "item.why-surfaced",
            action: "inspect_surfacing",
            owner: owner,
            sourceRefs: [owner.canonicalRef],
            evidenceRefs: ["recall_access_event:e2"],
            readOnly: true,
            changed: false,
            safeVerificationCommands: ["cider-cli item why-surfaced todo \(owner.ownerID) --json"],
            safeNextCommands: []
        )

        let record = try SecondBrainActionReceiptRecord(receiptDictionary: receipt)
        let id = try service.record(record)
        let inspected = try #require(try service.inspect(id: id))
        let dict = actionReceiptRecordToDict(inspected)

        #expect(dict["command"] as? String == "item.why-surfaced")
        #expect(dict["readOnly"] as? Bool == true)
        #expect(dict["changed"] as? Bool == false)
        #expect((dict["evidenceRefs"] as? [String]) == ["recall_access_event:e2"])
    }
}
