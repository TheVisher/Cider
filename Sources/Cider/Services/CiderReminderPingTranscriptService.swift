import Foundation
import Yams

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
            if let contract = row.senderMetadata["transportWorkerContract"] {
                dict["transportWorkerContract"] = contract
            }
            if row.senderMetadata["adapter"] == "cider_transport_worker_contract_stub" {
                dict["transportBoundary"] = "transport_worker_contract_stub_no_real_send_delivery_proof_only"
            } else {
                dict["transportBoundary"] = "fake_transport_no_real_send_delivery_proof_only"
            }
        }
        return dict
    }

    static func parseRows(_ input: String, errorDomain: String) throws -> [CiderReminderPingTranscriptRow] {
        let lines = input
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return try lines.map { line in
            guard let data = line.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: errorDomain, code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcript row is not valid JSON."])
            }
            return try row(from: object, errorDomain: errorDomain)
        }
    }

    static func row(from object: [String: Any], errorDomain: String) throws -> CiderReminderPingTranscriptRow {
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
            throw NSError(domain: errorDomain, code: 2, userInfo: [NSLocalizedDescriptionKey: "Transcript row is missing owner selector fields."])
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
        "cider-cli item reminder-ping-validate-delivered --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
        "cider-cli item reminder-ping-import-ack --file <delivered-transcript.jsonl> --json",
    ]
    var safeVerificationCommands: [String] = [
        "cider-cli item reminder-ping-validate-delivered --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
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
        let rows = try CiderReminderPingTranscriptService.parseRows(
            transcriptJSONL,
            errorDomain: "CiderReminderPingFakeTransportSenderService"
        )
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

}

struct CiderReminderPingTransportWorkerConfiguration: Equatable {
    var schemaVersion: Int = 1
    var workerID: String
    var senderID: String
    var transport: String
    var senderMetadataDefaults: [String: String] = [:]

    static func parseConfigFile(_ input: String, fileName: String) throws -> CiderReminderPingTransportWorkerConfiguration {
        let object: Any
        if fileName.lowercased().hasSuffix(".json") {
            guard let data = input.data(using: .utf8) else {
                throw configError("Transport worker config file is not valid UTF-8.")
            }
            object = try JSONSerialization.jsonObject(with: data)
        } else {
            object = try Yams.load(yaml: input) as Any
        }
        guard let dict = object as? [String: Any] else {
            throw configError("Transport worker config must be a top-level object.")
        }
        let allowedKeys: Set<String> = [
            "schemaVersion",
            "transport",
            "workerID",
            "senderID",
            "senderMetadataDefaults",
        ]
        if let unknown = dict.keys.first(where: { !allowedKeys.contains($0) }) {
            throw configError("Transport worker config contains unsupported field \(unknown).")
        }
        guard let schemaVersion = dict["schemaVersion"] as? Int else {
            throw configError("Transport worker config is missing required schemaVersion.")
        }
        guard schemaVersion == 1 else {
            throw configError("Unsupported transport worker config schemaVersion \(schemaVersion).")
        }
        let transport = try requiredString("transport", in: dict)
        let workerID = try requiredString("workerID", in: dict)
        let senderID = try requiredString("senderID", in: dict)
        var metadata: [String: String] = [:]
        if let rawMetadata = dict["senderMetadataDefaults"] {
            guard let metadataDict = rawMetadata as? [String: Any] else {
                throw configError("Transport worker config senderMetadataDefaults must be an object of string values.")
            }
            for (key, value) in metadataDict {
                guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let stringValue = value as? String,
                      !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw configError("Transport worker config senderMetadataDefaults must use non-empty string keys and values.")
                }
                metadata[key] = stringValue
            }
        }
        return CiderReminderPingTransportWorkerConfiguration(
            schemaVersion: schemaVersion,
            workerID: workerID,
            senderID: senderID,
            transport: transport,
            senderMetadataDefaults: metadata
        )
    }

    static func resolve(
        config: CiderReminderPingTransportWorkerConfiguration?,
        transport cliTransport: String?,
        workerID cliWorkerID: String?,
        senderID cliSenderID: String?
    ) throws -> CiderReminderPingTransportWorkerConfiguration {
        if let config {
            try assertNoConflict(field: "transport", configValue: config.transport, cliValue: cliTransport)
            try assertNoConflict(field: "workerID", configValue: config.workerID, cliValue: cliWorkerID)
            try assertNoConflict(field: "senderID", configValue: config.senderID, cliValue: cliSenderID)
            return config
        }
        guard let cliTransport, let cliWorkerID, let cliSenderID else {
            throw configError("Usage: cider-cli item reminder-ping-transport-worker --file <planned-jsonl> --output <delivered-jsonl> (--config-file <json-or-yaml>|--transport <name> --worker-id <id> --sender-id <id>) [--limit <n>] [--json]")
        }
        return CiderReminderPingTransportWorkerConfiguration(
            workerID: cliWorkerID,
            senderID: cliSenderID,
            transport: cliTransport
        )
    }

    private static func requiredString(_ key: String, in dict: [String: Any]) throws -> String {
        guard let value = dict[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw configError("Transport worker config is missing required \(key).")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func assertNoConflict(field: String, configValue: String, cliValue: String?) throws {
        guard let cliValue = cliValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !cliValue.isEmpty else { return }
        guard cliValue == configValue else {
            throw configError("Transport worker CLI \(field) conflicts with config-file \(field).")
        }
    }

    private static func configError(_ message: String) -> NSError {
        NSError(domain: "CiderReminderPingTransportWorkerConfiguration", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

struct CiderReminderPingTransportWorkerContractResult: Equatable {
    var command: String = "item.reminder-ping-transport-worker"
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var noRealSend: Bool = true
    var truthBoundary: String = "cider_items_plus_action_receipts_remain_source_of_truth_transport_worker_no_receipts"
    var transportBoundary: String = "transport_worker_contract_stub_no_real_send_delivery_proof_only"
    var counts: CiderReminderPingTranscriptCounts
    var rows: [CiderReminderPingTranscriptRow]
    var safeNextCommands: [String] = [
        "cider-cli item reminder-ping-validate-delivered --file <transport-worker-delivered.jsonl> --planned-file <planned-transcript.jsonl> --json",
        "cider-cli item reminder-ping-import-ack --file <transport-worker-delivered.jsonl> --json",
    ]
    var safeVerificationCommands: [String] = [
        "cider-cli item reminder-ping-validate-delivered --file <transport-worker-delivered.jsonl> --planned-file <planned-transcript.jsonl> --json",
        "cider-cli item action-ledger list --action record_ping_surface --json",
        "cider-cli item reminder-ping-import-ack --file <transport-worker-delivered.jsonl> --json",
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

enum CiderReminderPingTransportWorkerContractService {
    static func deliver(
        transcriptJSONL: String,
        configuration: CiderReminderPingTransportWorkerConfiguration,
        limit: Int? = nil
    ) throws -> CiderReminderPingTransportWorkerContractResult {
        let workerID = configuration.workerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let senderID = configuration.senderID.trimmingCharacters(in: .whitespacesAndNewlines)
        let transport = configuration.transport.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !workerID.isEmpty else {
            throw NSError(domain: "CiderReminderPingTransportWorkerContractService", code: 10, userInfo: [NSLocalizedDescriptionKey: "Transport worker configuration is missing workerID."])
        }
        guard !senderID.isEmpty else {
            throw NSError(domain: "CiderReminderPingTransportWorkerContractService", code: 11, userInfo: [NSLocalizedDescriptionKey: "Transport worker configuration is missing senderID."])
        }
        guard !transport.isEmpty else {
            throw NSError(domain: "CiderReminderPingTransportWorkerContractService", code: 12, userInfo: [NSLocalizedDescriptionKey: "Transport worker configuration is missing transport."])
        }

        let rows = try CiderReminderPingTranscriptService.parseRows(
            transcriptJSONL,
            errorDomain: "CiderReminderPingTransportWorkerContractService"
        )
        let maxDeliveries = limit ?? rows.count
        var deliveredCount = 0
        let deliveredRows = try rows.map { row -> CiderReminderPingTranscriptRow in
            try validate(row: row, transport: transport)
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
            next.noSendReason = "transport_worker_contract_stub_no_real_send"
            next.deliveryID = "transport-worker:\(workerID):\(row.envelopeID)"
            next.messageID = "transport-worker-message:\(workerID):\(row.envelopeID)"
            var metadata = configuration.senderMetadataDefaults
            metadata.merge([
                "adapter": "cider_transport_worker_contract_stub",
                "noRealSend": "true",
                "senderID": senderID,
                "sentBy": "cider-cli",
                "transport": transport,
                "transportWorkerContract": "stub",
                "workerID": workerID,
            ]) { _, new in new }
            next.senderMetadata = metadata
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
        return CiderReminderPingTransportWorkerContractResult(
            generatedAt: Date(),
            counts: counts,
            rows: deliveredRows
        )
    }

    private static func validate(row: CiderReminderPingTranscriptRow, transport: String) throws {
        let required: [(String, String)] = [
            ("id", row.id),
            ("ownerRef", row.owner.canonicalRef),
            ("itemType", row.itemType),
            ("itemID", row.itemID),
            ("transport", row.transport),
            ("surface", row.surface),
            ("deliveryKey", row.deliveryKey),
            ("duplicateKey", row.duplicateKey),
            ("envelopeID", row.envelopeID),
            ("runKey", row.runKey),
            ("plannedPingID", row.plannedPingID),
            ("message", row.message),
        ]
        if let missing = required.first(where: { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            throw NSError(domain: "CiderReminderPingTransportWorkerContractService", code: 20, userInfo: [NSLocalizedDescriptionKey: "Transcript row is missing required delivery proof field \(missing.0)."])
        }
        guard row.transport == transport else {
            throw NSError(domain: "CiderReminderPingTransportWorkerContractService", code: 21, userInfo: [NSLocalizedDescriptionKey: "Transcript row transport \(row.transport) does not match worker transport \(transport)."])
        }
    }
}

struct CiderReminderPingDeliveredTranscriptValidationCounts: Equatable {
    var total: Int
    var valid: Int
    var failed: Int
    var skipped: Int
}

struct CiderReminderPingDeliveredTranscriptValidationRow: Equatable {
    var status: String
    var changed: Bool = false
    var itemType: String
    var itemID: String
    var transport: String
    var surface: String
    var plannedPingID: String
    var deliveryID: String?
    var messageID: String?
    var errorCode: String?
    var error: String?
}

struct CiderReminderPingDeliveredTranscriptValidationResult: Equatable {
    var command: String = "item.reminder-ping-validate-delivered"
    var ok: Bool
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "planned_reminder_ping_transcript_selectors_gate_delivery_receipts"
    var transportBoundary: String = "validation_only_no_send_no_receipts"
    var counts: CiderReminderPingDeliveredTranscriptValidationCounts
    var rows: [CiderReminderPingDeliveredTranscriptValidationRow]
    var safeNextCommands: [String] = [
        "cider-cli item reminder-ping-import-ack --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
    ]
    var safeVerificationCommands: [String] = [
        "cider-cli item reminder-ping-validate-delivered --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
        "cider-cli item action-ledger list --action record_ping_surface --json",
    ]
}

enum CiderReminderPingDeliveredTranscriptValidationService {
    static func validate(
        deliveredTranscriptJSONL: String,
        plannedTranscriptJSONL: String
    ) throws -> CiderReminderPingDeliveredTranscriptValidationResult {
        let deliveredRows = try CiderReminderPingTranscriptService.parseRows(
            deliveredTranscriptJSONL,
            errorDomain: "CiderReminderPingDeliveredTranscriptValidationService"
        )
        let plannedRows = try CiderReminderPingTranscriptService.parseRows(
            plannedTranscriptJSONL,
            errorDomain: "CiderReminderPingDeliveredTranscriptValidationService"
        )
        let plannedByKey = Dictionary(uniqueKeysWithValues: plannedRows.map { (selectorKey($0), $0) })
        var seenDeliveredKeys = Set<String>()
        let validationRows = deliveredRows.map { delivered -> CiderReminderPingDeliveredTranscriptValidationRow in
            let key = selectorKey(delivered)
            let base = validationBase(delivered)
            guard isDelivered(delivered) else {
                return base.with(status: "skipped")
            }
            guard hasDeliveryProof(delivered) else {
                return base.failed(code: "missing_delivery_proof", error: "Delivered transcript row requires deliveryID or messageID before import.")
            }
            guard !seenDeliveredKeys.contains(key) else {
                return base.failed(code: "duplicate_delivered_row", error: "Delivered transcript contains duplicate or ambiguous rows for the same planned selector.")
            }
            seenDeliveredKeys.insert(key)
            guard let planned = plannedByKey[key] else {
                return base.failed(code: "planned_row_not_found", error: "Delivered transcript row is not present in the supplied planned transcript.")
            }
            guard delivered.itemType == planned.itemType,
                  delivered.itemID == planned.itemID,
                  delivered.owner == planned.owner else {
                return base.failed(code: "item_selector_mismatch", error: "Delivered row item selector does not match the planned transcript row.")
            }
            guard delivered.transport == planned.transport,
                  delivered.surface == planned.surface else {
                return base.failed(code: "transport_surface_mismatch", error: "Delivered row transport or surface does not match the planned transcript row.")
            }
            return base.with(status: "valid")
        }
        let counts = CiderReminderPingDeliveredTranscriptValidationCounts(
            total: validationRows.count,
            valid: validationRows.filter { $0.status == "valid" }.count,
            failed: validationRows.filter { $0.status == "failed" }.count,
            skipped: validationRows.filter { $0.status == "skipped" }.count
        )
        return CiderReminderPingDeliveredTranscriptValidationResult(
            ok: counts.failed == 0,
            counts: counts,
            rows: validationRows
        )
    }

    private static func selectorKey(_ row: CiderReminderPingTranscriptRow) -> String {
        if !row.plannedPingID.isEmpty { return "plannedPingID:\(row.plannedPingID)" }
        if !row.envelopeID.isEmpty { return "envelopeID:\(row.envelopeID)" }
        if !row.deliveryKey.isEmpty { return "deliveryKey:\(row.deliveryKey)" }
        return "owner:\(row.owner.canonicalRef):\(row.transport):\(row.surface)"
    }

    private static func isDelivered(_ row: CiderReminderPingTranscriptRow) -> Bool {
        ["delivered", "confirmed", "sent", "ok", "success"].contains(row.status.lowercased())
            || ["delivered", "confirmed", "sent", "ok", "success"].contains(row.deliveryStatus.lowercased())
            || hasDeliveryProof(row)
    }

    private static func hasDeliveryProof(_ row: CiderReminderPingTranscriptRow) -> Bool {
        !(row.deliveryID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(row.messageID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func validationBase(_ row: CiderReminderPingTranscriptRow) -> CiderReminderPingDeliveredTranscriptValidationRow {
        CiderReminderPingDeliveredTranscriptValidationRow(
            status: "valid",
            itemType: row.itemType,
            itemID: row.itemID,
            transport: row.transport,
            surface: row.surface,
            plannedPingID: row.plannedPingID,
            deliveryID: row.deliveryID,
            messageID: row.messageID
        )
    }
}

struct CiderReminderPingRunStatusCounts: Equatable {
    var plannedRows: Int
    var deliveredRows: Int
    var validationValid: Int
    var validationFailed: Int
    var validationSkipped: Int
    var existingReceiptMatches: Int
    var missingReceipts: Int
    var duplicateOrImportSkippedRows: Int
}

struct CiderReminderPingRunStatusRow: Equatable {
    var status: String
    var receiptStatus: String
    var itemType: String
    var itemID: String
    var ownerRef: String
    var transport: String
    var surface: String
    var plannedPingID: String
    var duplicateKey: String
    var deliveryID: String?
    var messageID: String?
    var matchingReceiptID: String?
    var validationStatus: String?
    var validationErrorCode: String?
    var validationError: String?
    var safeVerificationCommands: [String]
}

struct CiderReminderPingRunStatusResult: Equatable {
    var ok: Bool
    var command: String = "item.reminder-ping-status"
    var readOnly: Bool = true
    var changed: Bool = false
    var runState: String
    var truthBoundary: String = "planned_transcript_and_action_receipts_are_evidence_not_human_seen_truth"
    var transportBoundary: String = "status_replay_only_no_send_no_receipts"
    var counts: CiderReminderPingRunStatusCounts
    var rows: [CiderReminderPingRunStatusRow]
    var validation: CiderReminderPingDeliveredTranscriptValidationResult?
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]
}

@MainActor
enum CiderReminderPingRunStatusService {
    static func summarize(
        plannedTranscriptJSONL: String,
        deliveredTranscriptJSONL: String?,
        ledger: SecondBrainActionReceiptLedgerService
    ) throws -> CiderReminderPingRunStatusResult {
        let plannedRows = try CiderReminderPingTranscriptService.parseRows(
            plannedTranscriptJSONL,
            errorDomain: "CiderReminderPingRunStatusService"
        )
        let deliveredRows = try deliveredTranscriptJSONL.map {
            try CiderReminderPingTranscriptService.parseRows(
                $0,
                errorDomain: "CiderReminderPingRunStatusService"
            )
        } ?? []
        let validation = try deliveredTranscriptJSONL.map {
            try CiderReminderPingDeliveredTranscriptValidationService.validate(
                deliveredTranscriptJSONL: $0,
                plannedTranscriptJSONL: plannedTranscriptJSONL
            )
        }

        var validationByKey: [String: CiderReminderPingDeliveredTranscriptValidationRow] = [:]
        for row in validation?.rows ?? [] {
            let key = validationKey(itemType: row.itemType, itemID: row.itemID, transport: row.transport, surface: row.surface, plannedPingID: row.plannedPingID)
            if validationByKey[key] == nil {
                validationByKey[key] = row
            }
        }
        var deliveredByKey: [String: CiderReminderPingTranscriptRow] = [:]
        for row in deliveredRows where deliveredByKey[selectorKey(row)] == nil {
            deliveredByKey[selectorKey(row)] = row
        }
        let evidenceRows = deliveredRows.isEmpty ? plannedRows : plannedRows.map { planned in
            deliveredByKey[selectorKey(planned)] ?? planned
        }

        var statusRows: [CiderReminderPingRunStatusRow] = []
        var receiptMatchCount = 0
        var missingReceiptCount = 0
        var duplicateOrImportSkippedCount = 0

        for row in evidenceRows {
            let receipt = try matchingReceipt(for: row, ledger: ledger)
            let validationRow = validationByKey[selectorKey(row)]
            let hasReceipt = receipt != nil
            if hasReceipt {
                receiptMatchCount += 1
                if isDelivered(row) {
                    duplicateOrImportSkippedCount += 1
                }
            } else {
                missingReceiptCount += 1
            }
            let receiptStatus = hasReceipt ? "receipt_exists" : "missing_receipt"
            let status: String
            if let validationRow, validationRow.status == "failed" {
                status = "validation_failed"
            } else if hasReceipt {
                status = "imported_or_duplicate_suppressed"
            } else if isDelivered(row) {
                status = "delivered_not_imported"
            } else {
                status = "planned_not_delivered"
            }
            statusRows.append(CiderReminderPingRunStatusRow(
                status: status,
                receiptStatus: receiptStatus,
                itemType: row.itemType,
                itemID: row.itemID,
                ownerRef: row.owner.canonicalRef,
                transport: row.transport,
                surface: row.surface,
                plannedPingID: row.plannedPingID,
                duplicateKey: row.duplicateKey,
                deliveryID: row.deliveryID,
                messageID: row.messageID,
                matchingReceiptID: receipt?.id,
                validationStatus: validationRow?.status,
                validationErrorCode: validationRow?.errorCode,
                validationError: validationRow?.error,
                safeVerificationCommands: safeVerificationCommands(for: row, receiptID: receipt?.id)
            ))
        }

        let validationFailed = validation?.counts.failed ?? 0
        let counts = CiderReminderPingRunStatusCounts(
            plannedRows: plannedRows.count,
            deliveredRows: deliveredRows.count,
            validationValid: validation?.counts.valid ?? 0,
            validationFailed: validationFailed,
            validationSkipped: validation?.counts.skipped ?? 0,
            existingReceiptMatches: receiptMatchCount,
            missingReceipts: missingReceiptCount,
            duplicateOrImportSkippedRows: duplicateOrImportSkippedCount
        )
        let runState: String
        if validationFailed > 0 {
            runState = "blocked_by_validation"
        } else if deliveredRows.isEmpty {
            runState = "planned_not_delivered"
        } else if missingReceiptCount == 0 {
            runState = "imported"
        } else if receiptMatchCount > 0 {
            runState = "partially_imported"
        } else {
            runState = "delivered_not_imported"
        }

        let safeNextCommands = orderedUniqueStrings([
            "cider-cli item reminder-ping-validate-delivered --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
            "cider-cli item reminder-ping-transport-worker --file <planned-transcript.jsonl> --output <delivered-transcript.jsonl> --config-file <worker-config.yaml> --json",
            "cider-cli item reminder-ping-import-ack --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
            "cider-cli item action-ledger list --action record_ping_surface --json",
        ])
        let safeVerificationCommands = orderedUniqueStrings(
            statusRows.flatMap(\.safeVerificationCommands) + [
                "cider-cli item reminder-ping-status --planned-file <planned-transcript.jsonl> --delivered-file <delivered-transcript.jsonl> --json",
                "cider-cli item reminder-ping-validate-delivered --file <delivered-transcript.jsonl> --planned-file <planned-transcript.jsonl> --json",
                "cider-cli item action-ledger list --action record_ping_surface --json",
            ]
        )

        return CiderReminderPingRunStatusResult(
            ok: validationFailed == 0,
            runState: runState,
            counts: counts,
            rows: statusRows,
            validation: validation,
            safeNextCommands: safeNextCommands,
            safeVerificationCommands: safeVerificationCommands
        )
    }

    private static func matchingReceipt(
        for row: CiderReminderPingTranscriptRow,
        ledger: SecondBrainActionReceiptLedgerService
    ) throws -> SecondBrainActionReceiptRecord? {
        let receipts = try ledger.list(filter: .init(
            owner: row.owner,
            action: "record_ping_surface",
            status: "succeeded",
            limit: 100
        ))
        return receipts.first { receipt in
            receiptDuplicateKey(receipt) == row.duplicateKey
        }
    }

    private static func receiptDuplicateKey(_ receipt: SecondBrainActionReceiptRecord) -> String? {
        for json in [receipt.receiptJSON, receipt.afterJSON] {
            guard let json,
                  let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let duplicateKey = object["duplicateKey"] as? String,
                  !duplicateKey.isEmpty else { continue }
            return duplicateKey
        }
        return nil
    }

    private static func selectorKey(_ row: CiderReminderPingTranscriptRow) -> String {
        validationKey(
            itemType: row.itemType,
            itemID: row.itemID,
            transport: row.transport,
            surface: row.surface,
            plannedPingID: row.plannedPingID
        )
    }

    private static func validationKey(
        itemType: String,
        itemID: String,
        transport: String,
        surface: String,
        plannedPingID: String
    ) -> String {
        if !plannedPingID.isEmpty { return "plannedPingID:\(plannedPingID)" }
        return "owner:\(itemType):\(itemID):\(transport):\(surface)"
    }

    private static func isDelivered(_ row: CiderReminderPingTranscriptRow) -> Bool {
        ["delivered", "confirmed", "sent", "ok", "success"].contains(row.status.lowercased())
            || ["delivered", "confirmed", "sent", "ok", "success"].contains(row.deliveryStatus.lowercased())
            || !(row.deliveryID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(row.messageID?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }

    private static func safeVerificationCommands(for row: CiderReminderPingTranscriptRow, receiptID: String?) -> [String] {
        var commands = [
            "cider-cli item action-ledger list --owner \(row.owner.canonicalRef) --action record_ping_surface --json",
            "cider-cli item context \(row.owner.ownerType) \(row.owner.ownerID) --max-history 10 --json",
        ]
        if let receiptID {
            commands.insert("cider-cli item action-ledger inspect \(receiptID) --json", at: 0)
        }
        return commands
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

private extension CiderReminderPingDeliveredTranscriptValidationRow {
    func with(status: String) -> CiderReminderPingDeliveredTranscriptValidationRow {
        var copy = self
        copy.status = status
        return copy
    }

    func failed(code: String, error: String) -> CiderReminderPingDeliveredTranscriptValidationRow {
        var copy = self
        copy.status = "failed"
        copy.errorCode = code
        copy.error = error
        return copy
    }
}
