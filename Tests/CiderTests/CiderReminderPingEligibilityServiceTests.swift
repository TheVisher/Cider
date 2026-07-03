import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider reminder ping eligibility service")
@MainActor
struct CiderReminderPingEligibilityServiceTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-reminder-ping-eligibility-\(UUID().uuidString).db")
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

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour))!
    }

    @Test("due todo is eligible until matching owner action duplicate key receipt exists")
    func dueTodoIsEligibleUntilMatchingOwnerActionDuplicateKeyReceiptExists() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let ledger = SecondBrainActionReceiptLedgerService(database: db)
        let now = date(2026, 7, 13)
        let todo = TodoCard(title: "Scheduler ping todo", dueDate: now)
        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [todo], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )
        let expectedDuplicateKey = "todo:\(todo.id.uuidString):\(now.timeIntervalSince1970):surface"

        let beforeReceipt = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)

        let intent = try #require(beforeReceipt.intents.first)
        #expect(beforeReceipt.readOnly == true)
        #expect(beforeReceipt.changed == false)
        #expect(beforeReceipt.truthBoundary == "cider_items_plus_action_receipts")
        #expect(intent.owner == SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString))
        #expect(intent.duplicateKey == expectedDuplicateKey)
        #expect(intent.whyEligible.contains("No matching record_ping_surface receipt"))
        #expect(intent.safeRecordPingCommand == "cider-cli item ping-receipt record todo \(todo.id.uuidString) --transport <transport> --surface <surface> --json")
        #expect(intent.safeVerificationCommands.contains("cider-cli item action-ledger list --owner todo:\(todo.id.uuidString) --action record_ping_surface --json"))

        try recordPingReceipt(
            ledger: ledger,
            owner: SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString),
            action: "record_ping_surface",
            duplicateKey: "todo:\(UUID().uuidString):\(now.timeIntervalSince1970):surface"
        )
        try recordPingReceipt(
            ledger: ledger,
            owner: SecondBrainOwnerRef(ownerType: "todo", ownerID: UUID().uuidString),
            action: "record_ping_surface",
            duplicateKey: expectedDuplicateKey
        )
        try recordPingReceipt(
            ledger: ledger,
            owner: SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString),
            action: "inspect_surfacing",
            duplicateKey: expectedDuplicateKey
        )

        let afterUnrelatedReceipts = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)
        #expect(afterUnrelatedReceipts.intents.count == 1)

        try recordPingReceipt(
            ledger: ledger,
            owner: SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString),
            action: "record_ping_surface",
            duplicateKey: expectedDuplicateKey
        )

        let afterMatchingReceipt = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)
        #expect(afterMatchingReceipt.intents.isEmpty)
        #expect(afterMatchingReceipt.suppressed.count == 1)
        #expect(afterMatchingReceipt.suppressed.first?.duplicateKey == expectedDuplicateKey)
        #expect(afterMatchingReceipt.suppressed.first?.reason == "matching_record_ping_surface_receipt")
    }

    private func recordPingReceipt(
        ledger: SecondBrainActionReceiptLedgerService,
        owner: SecondBrainOwnerRef,
        action: String,
        duplicateKey: String
    ) throws {
        let receipt: [String: Any] = [
            "command": "item.ping-receipt.record",
            "action": action,
            "actor": "test",
            "status": "succeeded",
            "owner": [
                "ownerType": owner.ownerType,
                "ownerID": owner.ownerID,
                "ref": owner.canonicalRef,
            ],
            "sourceRefs": [owner.canonicalRef],
            "evidenceRefs": [owner.canonicalRef],
            "readOnly": false,
            "changed": true,
            "duplicateKey": duplicateKey,
            "truthBoundary": "ping_receipt_records_delivery_not_item_truth",
            "safeVerificationCommands": ["cider-cli item action-ledger list --owner \(owner.canonicalRef) --action record_ping_surface --json"],
            "safeNextCommands": ["cider-cli item due-to-surface --json"],
        ]
        try ledger.record(try SecondBrainActionReceiptRecord(receiptDictionary: receipt))
    }
}
