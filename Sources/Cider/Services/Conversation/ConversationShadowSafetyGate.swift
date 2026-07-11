import Foundation
import CryptoKit

enum ConversationShadowClosureOutcome: Equatable, Sendable {
    case synchronized
    case parityFailed(String)
}

struct ConversationShadowAttemptResult: Equatable, Sendable {
    let primaryReceipt: LegacyConversationWriteReceipt
    let payload: ConversationShadowPayload?
    let correlationID: UUID?
    let status: ConversationShadowHealthStatus?
    let code: ConversationShadowDiagnosticCode?
    let detail: String?
    let invokedShadowClosure: Bool
}

@MainActor
final class ConversationShadowSafetyGate {
    private let conversationReceipt: LegacyConversationWriteReceipt
    private let registryReceipt: LegacyRegistryWriteReceipt
    private let healthStore: ConversationShadowHealthStore
    private let now: () -> Date
    private let maximumReceiptAge: TimeInterval
    private var consumed = false

    init(
        conversationReceipt: LegacyConversationWriteReceipt,
        registryReceipt: LegacyRegistryWriteReceipt,
        healthStore: ConversationShadowHealthStore,
        maximumReceiptAge: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.conversationReceipt = conversationReceipt
        self.registryReceipt = registryReceipt
        self.healthStore = healthStore
        self.maximumReceiptAge = maximumReceiptAge
        self.now = now
    }

    func perform(
        _ shadowClosure: (ConversationShadowPayload) throws -> ConversationShadowClosureOutcome
    ) -> ConversationShadowAttemptResult {
        guard !consumed else {
            return blocked(.gateBlocked, "Shadow safety gate was already consumed.")
        }
        consumed = true

        let payload: ConversationShadowPayload
        do {
            payload = try validatedPayload()
        } catch let error as GateError {
            return blocked(error.code, error.detail)
        } catch {
            return blocked(.gateBlocked, String(describing: error))
        }

        let correlationID = UUID()
        do {
            try healthStore.reserve(payload: payload, correlationID: correlationID, at: now())
        } catch ConversationShadowHealthStoreError.saturated {
            return result(
                payload: payload,
                correlationID: nil,
                status: nil,
                code: .diagnosticStoreSaturated,
                detail: "Shadow diagnostic store is saturated; shadow operation was skipped.",
                invoked: false
            )
        } catch {
            return result(
                payload: payload,
                correlationID: nil,
                status: nil,
                code: .gateBlocked,
                detail: "Shadow reservation failed: \(String(describing: error))",
                invoked: false
            )
        }

        do {
            switch try shadowClosure(payload) {
            case .synchronized:
                do {
                    try healthStore.markSynchronized(correlationID: correlationID, at: now())
                    return result(payload: payload, correlationID: correlationID, status: .synchronized, code: nil, detail: nil, invoked: true)
                } catch {
                    let detail = "Shadow finalization failed after successful closure: \(String(describing: error))"
                    try? healthStore.markOutcomeUnknown(correlationID: correlationID, detail: detail, at: now())
                    let persistedStatus = healthStore.snapshot().unresolved.first(where: { $0.correlationID == correlationID })?.status ?? .reserved
                    return result(payload: payload, correlationID: correlationID, status: persistedStatus, code: nil, detail: detail, invoked: true)
                }
            case .parityFailed(let detail):
                let status = finalizeFailure(
                    correlationID: correlationID,
                    code: .shadowParityFailed,
                    detail: detail
                )
                return result(payload: payload, correlationID: correlationID, status: status, code: .shadowParityFailed, detail: detail, invoked: true)
            }
        } catch {
            let detail = String(describing: error)
            let status = finalizeFailure(
                correlationID: correlationID,
                code: .shadowRepositoryFailed,
                detail: detail
            )
            return result(payload: payload, correlationID: correlationID, status: status, code: .shadowRepositoryFailed, detail: detail, invoked: true)
        }
    }

    private func finalizeFailure(
        correlationID: UUID,
        code: ConversationShadowDiagnosticCode,
        detail: String
    ) -> ConversationShadowHealthStatus {
        do {
            try healthStore.markRepairNeeded(
                correlationID: correlationID,
                code: code,
                detail: detail,
                at: now()
            )
            return .repairNeeded
        } catch {
            let uncertainty = "Shadow failure finalization also failed: \(String(describing: error))"
            try? healthStore.markOutcomeUnknown(correlationID: correlationID, detail: uncertainty, at: now())
            return healthStore.snapshot().unresolved.first(where: { $0.correlationID == correlationID })?.status ?? .reserved
        }
    }

    private func validatedPayload() throws -> ConversationShadowPayload {
        guard conversationReceipt.isCommitted,
              let conversation = conversationReceipt.snapshot
        else {
            throw GateError(.gateBlocked, "Conversation receipt is not a verified commit.")
        }
        let registry = registryReceipt.snapshot
        guard conversationReceipt.generation == registryReceipt.generation,
              conversation.generation == registry.generation,
              conversationReceipt.generation == conversation.generation
        else {
            throw GateError(.gateBlocked, "Conversation and registry receipts do not prove the same generation.")
        }
        guard conversationReceipt.conversationID == registryReceipt.conversationID,
              conversation.metadata.id == registry.record.conversationID
        else {
            throw GateError(.registryMismatch, "Registry and conversation room identities differ.")
        }
        let current = now()
        guard let conversationCommittedAt = conversationReceipt.committedAt,
              isFresh(conversationCommittedAt, relativeTo: current),
              isFresh(registryReceipt.committedAt, relativeTo: current)
        else {
            throw GateError(.gateStale, "One or more verified receipts are stale or future-dated.")
        }
        guard conversationReceipt.sha256 == conversation.sha256,
              registryReceipt.sha256 == registry.sha256,
              Self.sha256(conversation.bytes) == conversation.sha256,
              Self.sha256(registry.bytes) == registry.sha256,
              conversation.metadata.messageCount == conversation.messages.count
        else {
            throw GateError(.gateBlocked, "Receipt hashes or message counts no longer match the immutable payload.")
        }
        try validateRegistry(registry.record, metadata: conversation.metadata)
        try validateMessages(conversation.messages, registry: registry.record)
        return ConversationShadowPayload(
            generation: conversation.generation,
            registry: registry,
            conversation: conversation
        )
    }

    private func validateRegistry(
        _ record: CiderAgentChatRecord,
        metadata: LegacyConversationMetadataSnapshot
    ) throws {
        guard metadata.type == "metadata",
              record.title == metadata.title,
              record.runtimeID == (metadata.runtimeID ?? ""),
              record.activeRuntimeSessionID == (metadata.activeRuntimeSessionID ?? ""),
              record.runtimeSessionLineage == (metadata.runtimeSessionLineage ?? []),
              record.lastSyncedMessageID == metadata.runtimeLastSyncedMessageID,
              record.lastSyncedTimestamp == metadata.runtimeLastSyncedTimestamp,
              record.lastImportedRuntimeSessionID == metadata.runtimeLastImportedSessionID
        else {
            throw GateError(.registryMismatch, "Registry and JSONL metadata do not match.")
        }
        let lineage = record.runtimeSessionLineage
        guard !lineage.contains(where: \.isEmpty),
              Set(lineage).count == lineage.count,
              record.activeRuntimeSessionID.isEmpty || lineage.contains(record.activeRuntimeSessionID)
        else {
            throw GateError(.gateBlocked, "Runtime session identities are empty, duplicated, or inconsistent.")
        }
    }

    private func validateMessages(
        _ messages: [LegacyConversationMessageSnapshot],
        registry: CiderAgentChatRecord
    ) throws {
        guard Set(messages.map(\.id)).count == messages.count else {
            throw GateError(.gateBlocked, "Message UUIDs are duplicated.")
        }
        let mapper = LegacyConversationSourceIdentityMapper()
        var sources = Set<ConversationSourceIdentity>()
        let sessions = Set(registry.runtimeSessionLineage + (registry.activeRuntimeSessionID.isEmpty ? [] : [registry.activeRuntimeSessionID]))
        for message in messages {
            guard message.attachments.isEmpty else {
                throw GateError(.gateBlocked, "Attachment-bearing messages are not supported by this shadow gate.")
            }
            let mapping = mapper.map(message.sourceID, role: message.role.rawValue)
            guard !mapping.malformedRecognizedStyle else {
                throw GateError(.gateBlocked, "A recognized Hermes source identity has an invalid shape.")
            }
            if let source = mapping.source, !sources.insert(source).inserted {
                throw GateError(.gateBlocked, "A message source identity is duplicated.")
            }
            if let sessionID = message.sourceSessionID {
                guard !sessionID.isEmpty, sessions.contains(sessionID) else {
                    throw GateError(.gateBlocked, "A message source session is unsupported by the verified registry generation.")
                }
            }
        }
    }

    private func isFresh(_ date: Date, relativeTo current: Date) -> Bool {
        let age = current.timeIntervalSince(date)
        return age >= -1 && age <= maximumReceiptAge
    }

    private func blocked(_ code: ConversationShadowDiagnosticCode, _ detail: String) -> ConversationShadowAttemptResult {
        result(payload: nil, correlationID: nil, status: nil, code: code, detail: detail, invoked: false)
    }

    private func result(
        payload: ConversationShadowPayload?,
        correlationID: UUID?,
        status: ConversationShadowHealthStatus?,
        code: ConversationShadowDiagnosticCode?,
        detail: String?,
        invoked: Bool
    ) -> ConversationShadowAttemptResult {
        ConversationShadowAttemptResult(
            primaryReceipt: conversationReceipt,
            payload: payload,
            correlationID: correlationID,
            status: status,
            code: code,
            detail: detail.map { String($0.prefix(ConversationShadowHealthStore.maximumDetailCharacters)) },
            invokedShadowClosure: invoked
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct GateError: Error {
        let code: ConversationShadowDiagnosticCode
        let detail: String

        init(_ code: ConversationShadowDiagnosticCode, _ detail: String) {
            self.code = code
            self.detail = detail
        }
    }
}
