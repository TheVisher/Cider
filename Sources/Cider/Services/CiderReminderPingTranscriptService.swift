import Foundation

struct CiderReminderPingTranscriptCounts: Equatable {
    var rows: Int
    var noSend: Int
    var delivered: Int
    var skipped: Int = 0
    var suppressed: Int
    var duplicates: Int
}

struct CiderReminderPingTranscriptRow: Identifiable, Equatable {
    var id: String
    var status: String = "not_delivered"
    var deliveryStatus: String = "not_delivered"
    var noSendReason: String = "transcript_preview_only_delivery_proof_required"
    var owner: SecondBrainOwnerRef
    var itemType: String
    var itemID: String
    var title: String
    var transport: String
    var surface: String
    var deliveryKey: String
    var duplicateKey: String
    var envelopeID: String
    var runKey: String
    var plannedPingID: String
    var message: String
    var sourceIntentID: String
    var sourceCandidateID: String
    var sourceRefs: [String]
    var safeRecordPingCommand: String
    var deliveryID: String? = nil
    var messageID: String? = nil
    var senderMetadata: [String: String] = [:]
}

struct CiderReminderPingTranscriptResult: Equatable {
    var command: String = "item.reminder-ping-transcript"
    var runKey: String
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "cider_items_plus_action_receipts_remain_source_of_truth_no_send_transcript"
    var transportBoundary: String = "no_transport_send_transcript_delivery_proof_required"
    var transport: String
    var surface: String
    var counts: CiderReminderPingTranscriptCounts
    var rows: [CiderReminderPingTranscriptRow]
    var suppressed: [CiderReminderPingSuppressedIntent]
    var duplicates: [CiderReminderPingDryRunDuplicate]
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]

    func jsonl() -> String {
        rows.map { row in
            let object = CiderReminderPingTranscriptService.rowDictionary(row)
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return line
        }
        .joined(separator: "\n")
    }
}

enum CiderReminderPingTranscriptService {
    static func produce(from dryRun: CiderReminderPingDryRunResult) -> CiderReminderPingTranscriptResult {
        let rows = dryRun.planned.map { planned -> CiderReminderPingTranscriptRow in
            let envelope = planned.envelope
            return CiderReminderPingTranscriptRow(
                id: "transcript:\(planned.id)",
                owner: envelope.owner,
                itemType: envelope.kind,
                itemID: envelope.owner.ownerID,
                title: envelope.title,
                transport: envelope.transport,
                surface: envelope.surface,
                deliveryKey: envelope.deliveryKey,
                duplicateKey: envelope.duplicateKey,
                envelopeID: envelope.id,
                runKey: dryRun.runKey,
                plannedPingID: planned.id,
                message: envelope.humanSafeMessage,
                sourceIntentID: envelope.sourceIntentID,
                sourceCandidateID: envelope.sourceCandidateID,
                sourceRefs: envelope.sourceRefs,
                safeRecordPingCommand: envelope.safeRecordPingCommand
            )
        }
        let counts = CiderReminderPingTranscriptCounts(
            rows: rows.count,
            noSend: rows.filter { $0.status == "not_delivered" }.count,
            delivered: 0,
            suppressed: dryRun.suppressed.count,
            duplicates: dryRun.duplicates.count
        )
        let safeVerificationCommands = orderedUniqueStrings(
            dryRun.safeVerificationCommands + [
                "cider-cli item reminder-ping-dry-run --transport \(dryRun.transport) --surface \(dryRun.surface) --json",
                "cider-cli item reminder-ping-import-ack --file <transport-transcript.jsonl> --json",
            ]
        )
        let safeNextCommands = orderedUniqueStrings([
            "cider-cli item reminder-ping-transcript --transport \(dryRun.transport) --surface \(dryRun.surface) --file <transport-transcript.jsonl> --json",
            "cider-cli item reminder-ping-import-ack --file <transport-transcript.jsonl> --json",
        ] + dryRun.safeNextCommands)

        return CiderReminderPingTranscriptResult(
            runKey: dryRun.runKey,
            generatedAt: dryRun.generatedAt,
            transport: dryRun.transport,
            surface: dryRun.surface,
            counts: counts,
            rows: rows,
            suppressed: dryRun.suppressed,
            duplicates: dryRun.duplicates,
            safeNextCommands: safeNextCommands,
            safeVerificationCommands: safeVerificationCommands
        )
    }

    static func rowDictionary(_ row: CiderReminderPingTranscriptRow) -> [String: Any] {
        var dict: [String: Any] = [
            "id": row.id,
            "status": row.status,
            "deliveryStatus": row.deliveryStatus,
            "noSendReason": row.noSendReason,
            "itemType": row.itemType,
            "itemID": row.itemID,
            "kind": row.itemType,
            "owner": [
                "ownerType": row.owner.ownerType,
                "ownerID": row.owner.ownerID,
                "ref": row.owner.canonicalRef,
            ],
            "ownerRef": row.owner.canonicalRef,
            "title": row.title,
            "transport": row.transport,
            "surface": row.surface,
            "deliveryKey": row.deliveryKey,
            "duplicateKey": row.duplicateKey,
            "envelopeID": row.envelopeID,
            "runKey": row.runKey,
            "plannedPingID": row.plannedPingID,
            "message": row.message,
            "humanSafeMessage": row.message,
            "sourceIntentID": row.sourceIntentID,
            "sourceCandidateID": row.sourceCandidateID,
            "sourceRefs": row.sourceRefs,
            "safeRecordPingCommand": row.safeRecordPingCommand,
            "transportBoundary": "no_transport_send_transcript_delivery_proof_required",
        ]
        if let deliveryID = row.deliveryID, !deliveryID.isEmpty {
            dict["deliveryID"] = deliveryID
        }
        if let messageID = row.messageID, !messageID.isEmpty {
            dict["messageID"] = messageID
        }
        if !row.senderMetadata.isEmpty {
            dict["sender"] = row.senderMetadata
            dict["senderMetadata"] = row.senderMetadata
            dict["fakeTransport"] = row.senderMetadata["fakeTransport"] == "true"
            dict["noRealSend"] = row.senderMetadata["noRealSend"] == "true"
            dict["senderAdapter"] = row.senderMetadata["adapter"]
            dict["sentBy"] = row.senderMetadata["sentBy"]
            dict["transportBoundary"] = "fake_transport_no_real_send_delivery_proof_only"
        }
        return dict
    }

    private static func orderedUniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

struct CiderReminderPingFakeTransportSenderResult: Equatable {
    var command: String = "item.reminder-ping-fake-send"
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "cider_items_plus_action_receipts_remain_source_of_truth_fake_transport_no_receipts"
    var transportBoundary: String = "fake_transport_no_real_send_delivery_proof_only"
    var counts: CiderReminderPingTranscriptCounts
    var rows: [CiderReminderPingTranscriptRow]
    var safeNextCommands: [String] = [
        "cider-cli item reminder-ping-import-ack --file <delivered-transcript.jsonl> --json",
    ]
    var safeVerificationCommands: [String] = [
        "cider-cli item action-ledger list --action record_ping_surface --json",
        "cider-cli item reminder-ping-dry-run --json",
    ]

    func jsonl() -> String {
        rows.map { row in
            let object = CiderReminderPingTranscriptService.rowDictionary(row)
            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
                  let line = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return line
        }
        .joined(separator: "\n")
    }
}

enum CiderReminderPingFakeTransportSenderService {
    static func deliver(
        transcriptJSONL: String,
        limit: Int? = nil,
        senderID: String = "cider-fake-transport"
    ) throws -> CiderReminderPingFakeTransportSenderResult {
        let rows = try parseRows(transcriptJSONL)
        let maxDeliveries = limit ?? rows.count
        var deliveredCount = 0
        let deliveredRows = rows.map { row -> CiderReminderPingTranscriptRow in
            guard deliveredCount < maxDeliveries,
                  row.deliveryID?.isEmpty ?? true,
                  row.messageID?.isEmpty ?? true,
                  row.status != "delivered" else {
                return row
            }
            deliveredCount += 1
            var next = row
            next.status = "delivered"
            next.deliveryStatus = "delivered"
            next.noSendReason = "fake_transport_no_real_send"
            next.deliveryID = "fake-delivery:\(row.envelopeID)"
            next.messageID = "fake-message:\(row.envelopeID)"
            next.senderMetadata = [
                "adapter": "cider_fake_transport",
                "fakeTransport": "true",
                "noRealSend": "true",
                "senderID": senderID,
                "sentBy": "cider-cli",
            ]
            return next
        }
        let counts = CiderReminderPingTranscriptCounts(
            rows: deliveredRows.count,
            noSend: deliveredRows.filter { $0.status != "delivered" }.count,
            delivered: deliveredRows.filter { $0.status == "delivered" }.count,
            skipped: max(0, deliveredRows.count - deliveredCount),
            suppressed: 0,
            duplicates: 0
        )
        return CiderReminderPingFakeTransportSenderResult(
            generatedAt: Date(),
            counts: counts,
            rows: deliveredRows
        )
    }

    private static func parseRows(_ input: String) throws -> [CiderReminderPingTranscriptRow] {
        let lines = input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return try lines.map { line in
            guard let data = line.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "CiderReminderPingFakeTransportSenderService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcript row is not valid JSON."])
            }
            return try row(from: object)
        }
    }

    private static func row(from object: [String: Any]) throws -> CiderReminderPingTranscriptRow {
        func string(_ key: String) -> String {
            (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        func strings(_ key: String) -> [String] {
            object[key] as? [String] ?? []
        }
        let ownerObject = object["owner"] as? [String: Any]
        let ownerType = (ownerObject?["ownerType"] as? String) ?? string("itemType")
        let ownerID = (ownerObject?["ownerID"] as? String) ?? string("itemID")
        guard !ownerType.isEmpty, !ownerID.isEmpty else {
            throw NSError(domain: "CiderReminderPingFakeTransportSenderService", code: 2, userInfo: [NSLocalizedDescriptionKey: "Transcript row is missing owner selector fields."])
        }
        let owner = SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID)
        var row = CiderReminderPingTranscriptRow(
            id: string("id"),
            status: string("status").isEmpty ? "not_delivered" : string("status"),
            deliveryStatus: string("deliveryStatus").isEmpty ? "not_delivered" : string("deliveryStatus"),
            noSendReason: string("noSendReason").isEmpty ? "transcript_preview_only_delivery_proof_required" : string("noSendReason"),
            owner: owner,
            itemType: string("itemType").isEmpty ? string("kind") : string("itemType"),
            itemID: string("itemID").isEmpty ? ownerID : string("itemID"),
            title: string("title"),
            transport: string("transport"),
            surface: string("surface"),
            deliveryKey: string("deliveryKey"),
            duplicateKey: string("duplicateKey"),
            envelopeID: string("envelopeID"),
            runKey: string("runKey"),
            plannedPingID: string("plannedPingID"),
            message: string("message").isEmpty ? string("humanSafeMessage") : string("message"),
            sourceIntentID: string("sourceIntentID"),
            sourceCandidateID: string("sourceCandidateID"),
            sourceRefs: strings("sourceRefs"),
            safeRecordPingCommand: string("safeRecordPingCommand"),
            deliveryID: string("deliveryID").isEmpty ? nil : string("deliveryID"),
            messageID: string("messageID").isEmpty ? nil : string("messageID")
        )
        if row.id.isEmpty {
            row.id = "transcript:\(row.plannedPingID)"
        }
        return row
    }
}
