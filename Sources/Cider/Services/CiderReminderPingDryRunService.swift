import Foundation

struct CiderReminderPingDryRunCounts: Equatable {
    var eligible: Int
    var planned: Int
    var suppressed: Int
    var duplicates: Int
}

struct CiderReminderPingDryRunPlannedPing: Identifiable, Equatable {
    var id: String
    var envelope: CiderReminderPingDeliveryEnvelope
    var wouldSend: Bool = false
    var readOnly: Bool = true
    var changed: Bool = false
    var noSendReason: String = "dry_run_preview_only"
}

struct CiderReminderPingDryRunDuplicate: Identifiable, Equatable {
    var id: String
    var envelope: CiderReminderPingDeliveryEnvelope
    var duplicateOfEnvelopeID: String
    var reason: String = "duplicate_delivery_key_in_preview"
}

struct CiderReminderPingDryRunResult: Equatable {
    var command: String = "item.reminder-ping-dry-run"
    var runKey: String
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "cider_items_plus_action_receipts_remain_source_of_truth_no_send_dry_run"
    var transport: String
    var surface: String
    var counts: CiderReminderPingDryRunCounts
    var eligibleEnvelopeRefs: [String]
    var planned: [CiderReminderPingDryRunPlannedPing]
    var suppressed: [CiderReminderPingSuppressedIntent]
    var duplicates: [CiderReminderPingDryRunDuplicate]
    var safeRecordPingCommands: [String]
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]
}

enum CiderReminderPingDryRunService {
    static func run(from preview: CiderReminderPingDeliveryPreviewResult) -> CiderReminderPingDryRunResult {
        var firstEnvelopeByDeliveryKey: [String: CiderReminderPingDeliveryEnvelope] = [:]
        var planned: [CiderReminderPingDryRunPlannedPing] = []
        var duplicates: [CiderReminderPingDryRunDuplicate] = []

        for envelope in preview.envelopes {
            if let original = firstEnvelopeByDeliveryKey[envelope.deliveryKey] {
                duplicates.append(CiderReminderPingDryRunDuplicate(
                    id: "duplicate:\(envelope.id)",
                    envelope: envelope,
                    duplicateOfEnvelopeID: original.id
                ))
            } else {
                firstEnvelopeByDeliveryKey[envelope.deliveryKey] = envelope
                planned.append(CiderReminderPingDryRunPlannedPing(
                    id: "planned:\(envelope.id)",
                    envelope: envelope
                ))
            }
        }

        let eligibleEnvelopeRefs = planned.map(\.envelope.id)
        let safeRecordPingCommands = orderedUniqueStrings(planned.map(\.envelope.safeRecordPingCommand))
        let safeVerificationCommands = orderedUniqueStrings(
            preview.safeVerificationCommands
            + planned.flatMap(\.envelope.safeVerificationCommands)
            + preview.suppressed.flatMap(\.safeVerificationCommands)
            + [
                "cider-cli item reminder-ping-dry-run --transport \(preview.transport) --surface \(preview.surface) --json",
                "cider-cli item reminder-ping-delivery-preview --transport \(preview.transport) --surface \(preview.surface) --json",
            ]
        )
        let safeNextCommands = orderedUniqueStrings(
            safeRecordPingCommands
            + [
                "cider-cli item reminder-ping-dry-run --transport \(preview.transport) --surface \(preview.surface) --json",
                "cider-cli item reminder-ping-delivery-preview --transport \(preview.transport) --surface \(preview.surface) --json",
            ]
        )
        let counts = CiderReminderPingDryRunCounts(
            eligible: planned.count,
            planned: planned.count,
            suppressed: preview.suppressed.count,
            duplicates: duplicates.count
        )

        return CiderReminderPingDryRunResult(
            runKey: runKey(
                transport: preview.transport,
                surface: preview.surface,
                eligibleEnvelopeRefs: eligibleEnvelopeRefs,
                suppressedRefs: preview.suppressed.map(\.id),
                duplicateRefs: duplicates.map(\.id)
            ),
            generatedAt: preview.generatedAt,
            transport: preview.transport,
            surface: preview.surface,
            counts: counts,
            eligibleEnvelopeRefs: eligibleEnvelopeRefs,
            planned: planned,
            suppressed: preview.suppressed,
            duplicates: duplicates,
            safeRecordPingCommands: safeRecordPingCommands,
            safeVerificationCommands: safeVerificationCommands,
            safeNextCommands: safeNextCommands
        )
    }

    private static func runKey(
        transport: String,
        surface: String,
        eligibleEnvelopeRefs: [String],
        suppressedRefs: [String],
        duplicateRefs: [String]
    ) -> String {
        let material = ([transport, surface] + eligibleEnvelopeRefs + suppressedRefs + duplicateRefs)
            .joined(separator: "|")
        return "reminder_ping_dry_run:\(stableDJB2Hex(material))"
    }

    private static func stableDJB2Hex(_ value: String) -> String {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
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
