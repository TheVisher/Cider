import Foundation

struct CiderReminderPingEligibilityResult: Equatable {
    var command: String = "item.reminder-ping-intents"
    var generatedAt: Date
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "cider_items_plus_action_receipts"
    var intents: [CiderReminderPingIntent]
    var suppressed: [CiderReminderPingSuppressedIntent]
    var safeNextCommands: [String]
    var safeVerificationCommands: [String]
}

struct CiderReminderPingIntent: Identifiable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var kind: String
    var title: String
    var itemType: String
    var dueAt: Date?
    var dueStatus: String?
    var window: CiderDueToSurfaceWindow
    var duplicateKey: String
    var whyEligible: String
    var sourceCandidateID: String
    var sourceRefs: [String]
    var safeRecordPingCommand: String
    var safeVerificationCommands: [String]
}

struct CiderReminderPingSuppressedIntent: Identifiable, Equatable {
    var id: String
    var owner: SecondBrainOwnerRef
    var duplicateKey: String
    var reason: String
    var matchingReceiptID: String
    var sourceCandidateID: String
    var safeVerificationCommands: [String]
}

@MainActor
enum CiderReminderPingEligibilityService {
    static func pendingIntents(
        from feed: CiderDueToSurfaceFeed,
        ledger: SecondBrainActionReceiptLedgerService
    ) throws -> CiderReminderPingEligibilityResult {
        var intents: [CiderReminderPingIntent] = []
        var suppressed: [CiderReminderPingSuppressedIntent] = []

        for candidate in feed.candidates {
            guard let duplicateKey = candidate.pingDuplicateKey,
                  let recordCommand = candidate.pingReceiptCommand else { continue }
            let owner = candidate.owner
            let verificationCommands = orderedUniqueStrings([
                "cider-cli item action-ledger list --owner \(owner.canonicalRef) --action record_ping_surface --json",
                "cider-cli item due-to-surface --json",
                "cider-cli item context \(owner.ownerType) \(owner.ownerID) --max-history 10 --json",
            ] + candidate.safeVerificationCommands)
            let receipts = try ledger.list(filter: .init(
                owner: owner,
                action: "record_ping_surface",
                status: "succeeded",
                limit: 100
            ))
            if let matchingReceipt = receipts.first(where: { receiptDuplicateKey($0) == duplicateKey }) {
                suppressed.append(CiderReminderPingSuppressedIntent(
                    id: "suppressed:\(candidate.id)",
                    owner: owner,
                    duplicateKey: duplicateKey,
                    reason: "matching_record_ping_surface_receipt",
                    matchingReceiptID: matchingReceipt.id,
                    sourceCandidateID: candidate.id,
                    safeVerificationCommands: verificationCommands
                ))
                continue
            }

            intents.append(CiderReminderPingIntent(
                id: "ping_intent:\(candidate.id)",
                owner: owner,
                kind: owner.ownerType,
                title: candidate.title,
                itemType: candidate.itemType,
                dueAt: candidate.dueAt,
                dueStatus: candidate.dueStatus,
                window: candidate.window,
                duplicateKey: duplicateKey,
                whyEligible: "No matching record_ping_surface receipt exists for owner \(owner.canonicalRef) and duplicate key \(duplicateKey).",
                sourceCandidateID: candidate.id,
                sourceRefs: orderedUniqueStrings([owner.canonicalRef] + candidate.sourceRefs),
                safeRecordPingCommand: recordCommand,
                safeVerificationCommands: verificationCommands
            ))
        }

        let safeVerificationCommands = orderedUniqueStrings(
            intents.flatMap(\.safeVerificationCommands) + suppressed.flatMap(\.safeVerificationCommands)
        )
        let safeNextCommands = orderedUniqueStrings(
            intents.map(\.safeRecordPingCommand) + [
                "cider-cli item reminder-ping-intents --json",
                "cider-cli item due-to-surface --json",
            ]
        )

        return CiderReminderPingEligibilityResult(
            generatedAt: feed.generatedAt,
            intents: intents,
            suppressed: suppressed,
            safeNextCommands: safeNextCommands,
            safeVerificationCommands: safeVerificationCommands
        )
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
