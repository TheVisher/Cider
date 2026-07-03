import Foundation

struct CiderReminderPingTranscriptCounts: Equatable {
    var rows: Int
    var noSend: Int
    var delivered: Int
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
