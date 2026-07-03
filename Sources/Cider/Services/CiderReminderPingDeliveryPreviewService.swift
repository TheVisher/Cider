import Foundation

struct CiderReminderPingDeliveryPreviewResult: Equatable {
    var command: String = "item.reminder-ping-delivery-preview"
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "cider_items_plus_action_receipts_no_send_preview"
    var transport: String
    var surface: String
    var envelopes: [CiderReminderPingDeliveryEnvelope]
    var suppressed: [CiderReminderPingSuppressedIntent]
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]
}

struct CiderReminderPingDeliveryEnvelope: Identifiable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var kind: String
    var title: String
    var itemType: String
    var dueAt: Date?
    var dueStatus: String?
    var window: CiderDueToSurfaceWindow
    var duplicateKey: String
    var transport: String
    var surface: String
    var deliveryKey: String
    var idempotencyGuidance: String
    var humanSafeMessage: String
    var sourceIntentID: String
    var sourceCandidateID: String
    var sourceRefs: [String]
    var safeRecordPingCommand: String
    var safeVerificationCommands: [String]
}

enum CiderReminderPingDeliveryPreviewService {
    static let defaultTransport = "preview-transport"
    static let defaultSurface = "reminder-ping-preview"

    static func preview(
        from eligibility: CiderReminderPingEligibilityResult,
        transport rawTransport: String = defaultTransport,
        surface rawSurface: String = defaultSurface
    ) -> CiderReminderPingDeliveryPreviewResult {
        let transport = normalized(rawTransport, fallback: defaultTransport)
        let surface = normalized(rawSurface, fallback: defaultSurface)
        let envelopes = eligibility.intents.map { intent in
            envelope(from: intent, transport: transport, surface: surface)
        }
        let previewCommand = "cider-cli item reminder-ping-delivery-preview --transport \(transport) --surface \(surface) --json"
        let safeVerificationCommands = orderedUniqueStrings(
            envelopes.flatMap(\.safeVerificationCommands)
            + eligibility.suppressed.flatMap(\.safeVerificationCommands)
            + [previewCommand, "cider-cli item reminder-ping-intents --json"]
        )
        let safeNextCommands = orderedUniqueStrings(
            envelopes.map(\.safeRecordPingCommand)
            + [previewCommand, "cider-cli item reminder-ping-intents --json"]
        )

        return CiderReminderPingDeliveryPreviewResult(
            generatedAt: eligibility.generatedAt,
            transport: transport,
            surface: surface,
            envelopes: envelopes,
            suppressed: eligibility.suppressed,
            safeNextCommands: safeNextCommands,
            safeVerificationCommands: safeVerificationCommands
        )
    }

    private static func envelope(
        from intent: CiderReminderPingIntent,
        transport: String,
        surface: String
    ) -> CiderReminderPingDeliveryEnvelope {
        let deliveryKey = "\(intent.duplicateKey):\(transport):\(surface)"
        let command = "cider-cli item ping-receipt record \(intent.kind) \(intent.owner.ownerID) --transport \(transport) --surface \(surface) --json"
        let verificationCommands = orderedUniqueStrings(
            intent.safeVerificationCommands + [
                "cider-cli item reminder-ping-delivery-preview --transport \(transport) --surface \(surface) --json",
            ]
        )
        return CiderReminderPingDeliveryEnvelope(
            id: "ping_delivery_preview:\(intent.id):\(transport):\(surface)",
            owner: intent.owner,
            kind: intent.kind,
            title: intent.title,
            itemType: intent.itemType,
            dueAt: intent.dueAt,
            dueStatus: intent.dueStatus,
            window: intent.window,
            duplicateKey: intent.duplicateKey,
            transport: transport,
            surface: surface,
            deliveryKey: deliveryKey,
            idempotencyGuidance: "Use deliveryKey \(deliveryKey) for transport attempts and record duplicateKey \(intent.duplicateKey) only after confirmed delivery.",
            humanSafeMessage: humanSafeMessage(for: intent),
            sourceIntentID: intent.id,
            sourceCandidateID: intent.sourceCandidateID,
            sourceRefs: intent.sourceRefs,
            safeRecordPingCommand: command,
            safeVerificationCommands: verificationCommands
        )
    }

    private static func humanSafeMessage(for intent: CiderReminderPingIntent) -> String {
        var pieces = ["Reminder: \(intent.title)"]
        if let dueStatus = intent.dueStatus, !dueStatus.isEmpty {
            pieces.append("Status: \(dueStatus).")
        }
        if let dueAt = intent.dueAt {
            pieces.append("Due: \(ISO8601DateFormatter().string(from: dueAt)).")
        }
        return pieces.joined(separator: " ")
    }

    private static func normalized(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
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
