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

    @Test("delivery preview turns pending intents into no-send envelopes without receipts")
    func deliveryPreviewTurnsPendingIntentsIntoNoSendEnvelopesWithoutReceipts() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let ledger = SecondBrainActionReceiptLedgerService(database: db)
        let now = date(2026, 7, 13)
        let todo = TodoCard(title: "Preview delivery todo", dueDate: now)
        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [todo], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )
        let intents = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)

        let preview = CiderReminderPingDeliveryPreviewService.preview(
            from: intents,
            transport: "discord",
            surface: "agent-chat"
        )

        #expect(preview.readOnly == true)
        #expect(preview.changed == false)
        #expect(preview.truthBoundary == "cider_items_plus_action_receipts_no_send_preview")
        let envelope = try #require(preview.envelopes.first)
        #expect(envelope.owner == SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString))
        #expect(envelope.title == "Preview delivery todo")
        #expect(envelope.transport == "discord")
        #expect(envelope.surface == "agent-chat")
        #expect(envelope.duplicateKey == "todo:\(todo.id.uuidString):\(now.timeIntervalSince1970):surface")
        #expect(envelope.deliveryKey == "todo:\(todo.id.uuidString):\(now.timeIntervalSince1970):surface:discord:agent-chat")
        #expect(envelope.humanSafeMessage.contains("Preview delivery todo"))
        #expect(envelope.idempotencyGuidance.contains(envelope.duplicateKey))
        #expect(envelope.safeRecordPingCommand == "cider-cli item reminder-ping-confirm-delivery todo \(todo.id.uuidString) --transport discord --surface agent-chat --delivery-id <delivery-id> --json")
        #expect(envelope.safeVerificationCommands.contains("cider-cli item action-ledger list --owner todo:\(todo.id.uuidString) --action record_ping_surface --json"))
        #expect(try ledger.list(filter: .init(limit: 10)).isEmpty)
    }

    @Test("delivery preview carries suppression through after matching receipt")
    func deliveryPreviewCarriesSuppressionThroughAfterMatchingReceipt() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let ledger = SecondBrainActionReceiptLedgerService(database: db)
        let now = date(2026, 7, 13)
        let todo = TodoCard(title: "Preview suppressed todo", dueDate: now)
        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [todo], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )
        let duplicateKey = "todo:\(todo.id.uuidString):\(now.timeIntervalSince1970):surface"
        try recordPingReceipt(
            ledger: ledger,
            owner: SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString),
            action: "record_ping_surface",
            duplicateKey: duplicateKey
        )

        let intents = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)
        let preview = CiderReminderPingDeliveryPreviewService.preview(from: intents, transport: "discord", surface: "agent-chat")

        #expect(preview.envelopes.isEmpty)
        #expect(preview.suppressed.count == 1)
        #expect(preview.suppressed.first?.duplicateKey == duplicateKey)
        #expect(preview.suppressed.first?.reason == "matching_record_ping_surface_receipt")
    }

    @Test("scheduler dry run summarizes preview envelopes without recording receipts")
    func schedulerDryRunSummarizesPreviewEnvelopesWithoutRecordingReceipts() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let ledger = SecondBrainActionReceiptLedgerService(database: db)
        let now = date(2026, 7, 13)
        let todo = TodoCard(title: "Dry run scheduler todo", dueDate: now)
        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [todo], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )
        let intents = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)
        let preview = CiderReminderPingDeliveryPreviewService.preview(
            from: intents,
            transport: "discord",
            surface: "agent-chat"
        )

        let run = CiderReminderPingDryRunService.run(from: preview)

        #expect(run.command == "item.reminder-ping-dry-run")
        #expect(run.generatedAt == preview.generatedAt)
        #expect(run.readOnly == true)
        #expect(run.changed == false)
        #expect(run.transport == "discord")
        #expect(run.surface == "agent-chat")
        #expect(run.truthBoundary == "cider_items_plus_action_receipts_remain_source_of_truth_no_send_dry_run")
        #expect(run.counts.eligible == 1)
        #expect(run.counts.planned == 1)
        #expect(run.counts.suppressed == 0)
        #expect(run.counts.duplicates == 0)
        let planned = try #require(run.planned.first)
        #expect(run.eligibleEnvelopeRefs == [planned.envelope.id])
        #expect(run.safeRecordPingCommands == ["cider-cli item reminder-ping-confirm-delivery todo \(todo.id.uuidString) --transport discord --surface agent-chat --delivery-id <delivery-id> --json"])
        #expect(run.safeVerificationCommands.contains("cider-cli item reminder-ping-delivery-preview --transport discord --surface agent-chat --json"))
        #expect(planned.envelope.owner == SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString))
        #expect(planned.wouldSend == false)
        #expect(planned.readOnly == true)
        #expect(planned.changed == false)
        #expect(planned.noSendReason == "dry_run_preview_only")
        #expect(try ledger.list(filter: .init(limit: 10)).isEmpty)

        let secondRun = CiderReminderPingDryRunService.run(from: preview)
        #expect(secondRun.runKey == run.runKey)
    }

    @Test("scheduler dry run carries receipt suppression after matching ping receipt")
    func schedulerDryRunCarriesReceiptSuppressionAfterMatchingPingReceipt() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let ledger = SecondBrainActionReceiptLedgerService(database: db)
        let now = date(2026, 7, 13)
        let todo = TodoCard(title: "Dry run suppressed todo", dueDate: now)
        let feed = CiderDueToSurfaceFeedService.build(
            agenda: AgendaBriefingService.build(todos: [todo], dateCards: [], now: now, calendar: calendar),
            reviewItems: [],
            staleCaptures: [],
            linkedContext: [],
            now: now,
            limit: 10
        )
        let duplicateKey = "todo:\(todo.id.uuidString):\(now.timeIntervalSince1970):surface"
        try recordPingReceipt(
            ledger: ledger,
            owner: SecondBrainOwnerRef(ownerType: "todo", ownerID: todo.id.uuidString),
            action: "record_ping_surface",
            duplicateKey: duplicateKey
        )
        let intents = try CiderReminderPingEligibilityService.pendingIntents(from: feed, ledger: ledger)
        let preview = CiderReminderPingDeliveryPreviewService.preview(from: intents, transport: "discord", surface: "agent-chat")

        let run = CiderReminderPingDryRunService.run(from: preview)

        #expect(run.planned.isEmpty)
        #expect(run.eligibleEnvelopeRefs.isEmpty)
        #expect(run.counts.eligible == 0)
        #expect(run.counts.planned == 0)
        #expect(run.counts.suppressed == 1)
        let suppressed = try #require(run.suppressed.first)
        #expect(suppressed.duplicateKey == duplicateKey)
        #expect(suppressed.reason == "matching_record_ping_surface_receipt")
        #expect(run.safeVerificationCommands.contains("cider-cli item action-ledger list --owner todo:\(todo.id.uuidString) --action record_ping_surface --json"))
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
