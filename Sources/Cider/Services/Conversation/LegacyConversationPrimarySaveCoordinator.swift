import Foundation

struct LegacyConversationCoordinatedSaveResult: Equatable, Sendable {
    let generation: LegacyConversationWriteGeneration
    let registryReceipt: LegacyRegistryWriteReceipt?
    let registryFailureDetail: String?
    let primaryReceipt: LegacyConversationWriteReceipt
    let shadowCorrelationID: UUID?
    let shadowStatus: ConversationShadowHealthStatus?
    let shadowCode: ConversationShadowDiagnosticCode?
    let shadowDetail: String?
    let invokedShadowWriter: Bool
}

/// Dormant coordination boundary. No production caller is registered in this slice.
@MainActor
final class LegacyConversationPrimarySaveCoordinator {
    private let registry: CiderAgentChatRegistry
    private let conversationStorage: AIConversationStorage
    private let healthStore: ConversationShadowHealthStore
    private let shadowWriter: ConversationShadowWriter
    private let reconciler: ConversationShadowReconciler
    private let receiptReporter: ConversationShadowActivationReceiptReporter?
    private let now: () -> Date

    init(
        registry: CiderAgentChatRegistry,
        conversationStorage: AIConversationStorage,
        healthStore: ConversationShadowHealthStore,
        shadowWriter: ConversationShadowWriter,
        reconciler: ConversationShadowReconciler,
        receiptReporter: ConversationShadowActivationReceiptReporter? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.conversationStorage = conversationStorage
        self.healthStore = healthStore
        self.shadowWriter = shadowWriter
        self.reconciler = reconciler
        self.receiptReporter = receiptReporter
        self.now = now
    }

    func save(
        record: CiderAgentChatRecord,
        title: String,
        messages: [AIAssistantMessage],
        model: String,
        hermesState: HermesConversationState
    ) -> LegacyConversationCoordinatedSaveResult {
        let generation = LegacyConversationWriteGeneration()
        let registryReceipt: LegacyRegistryWriteReceipt?
        let registryFailureDetail: String?
        do {
            registryReceipt = try registry.updateChat(record, generation: generation)
            registryFailureDetail = nil
        } catch {
            registryReceipt = nil
            registryFailureDetail = String(String(describing: error).prefix(ConversationShadowHealthStore.maximumDetailCharacters))
        }

        // The legacy JSONL save is attempted even when the independent registry write failed.
        let primaryReceipt = conversationStorage.save(
            id: record.conversationID,
            title: title,
            messages: messages,
            model: model,
            hermesState: hermesState,
            generation: generation
        )

        guard let registryReceipt,
              receiptsMatch(
                  generation: generation,
                  registryReceipt: registryReceipt,
                  conversationReceipt: primaryReceipt
              ) else {
            return reported(.init(
                generation: generation,
                registryReceipt: registryReceipt,
                registryFailureDetail: registryFailureDetail,
                primaryReceipt: primaryReceipt,
                shadowCorrelationID: nil,
                shadowStatus: nil,
                shadowCode: nil,
                shadowDetail: nil,
                invokedShadowWriter: false
            ), payload: nil)
        }

        let gate = ConversationShadowSafetyGate(
            conversationReceipt: primaryReceipt,
            registryReceipt: registryReceipt,
            healthStore: healthStore,
            now: now
        )
        var exactPayloadForImmediateReconciliation: ConversationShadowPayload?
        let attempt = gate.perform { payload in
            do {
                try shadowWriter.writeVerifiedSequentialCompletedSnapshot(payload)
            } catch ConversationShadowWriterError.parity(let detail) {
                return .parityFailed(detail)
            }
            exactPayloadForImmediateReconciliation = payload
            return .synchronized
        }
        if attempt.status == .synchronized, let payload = exactPayloadForImmediateReconciliation {
            _ = try? reconciler.reconcileAfterExactRetry(payload)
        }
        return reported(.init(
            generation: generation,
            registryReceipt: registryReceipt,
            registryFailureDetail: registryFailureDetail,
            primaryReceipt: primaryReceipt,
            shadowCorrelationID: attempt.correlationID,
            shadowStatus: attempt.status,
            shadowCode: attempt.code,
            shadowDetail: attempt.detail,
            invokedShadowWriter: attempt.invokedShadowClosure
        ), payload: attempt.payload)
    }

    private func reported(
        _ result: LegacyConversationCoordinatedSaveResult,
        payload: ConversationShadowPayload?
    ) -> LegacyConversationCoordinatedSaveResult {
        guard let receiptReporter else { return result }
        let receiptPayload = payload ?? result.registryReceipt.flatMap { registryReceipt in
            result.primaryReceipt.snapshot.map {
                ConversationShadowPayload(
                    generation: result.generation,
                    registry: registryReceipt.snapshot,
                    conversation: $0
                )
            }
        }
        let fingerprint = receiptPayload.flatMap { try? shadowWriter.semanticFingerprint($0) }
        receiptReporter.report(.init(
            generationID: result.generation.id,
            conversationID: result.primaryReceipt.conversationID,
            registryCommitted: result.registryReceipt != nil,
            jsonlStatus: result.primaryReceipt.status,
            shadowCorrelationID: result.shadowCorrelationID,
            shadowStatus: result.shadowStatus,
            shadowCode: result.shadowCode,
            planFingerprint: fingerprint?.planFingerprint,
            messageCount: result.primaryReceipt.messageCount,
            terminalSourceNamespace: fingerprint?.terminalSource?.namespace,
            terminalSourceID: fingerprint?.terminalSource?.id
        ))
        return result
    }

    private func receiptsMatch(
        generation: LegacyConversationWriteGeneration,
        registryReceipt: LegacyRegistryWriteReceipt,
        conversationReceipt: LegacyConversationWriteReceipt
    ) -> Bool {
        guard conversationReceipt.isCommitted,
              let conversation = conversationReceipt.snapshot else { return false }
        return registryReceipt.generation == generation &&
            conversationReceipt.generation == generation &&
            registryReceipt.snapshot.generation == generation &&
            conversation.generation == generation &&
            registryReceipt.conversationID == conversationReceipt.conversationID &&
            registryReceipt.conversationID == conversation.metadata.id &&
            registryReceipt.sha256 == registryReceipt.snapshot.sha256 &&
            conversationReceipt.sha256 == conversation.sha256
    }
}
