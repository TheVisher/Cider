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
    private let now: () -> Date

    init(
        registry: CiderAgentChatRegistry,
        conversationStorage: AIConversationStorage,
        healthStore: ConversationShadowHealthStore,
        shadowWriter: ConversationShadowWriter,
        reconciler: ConversationShadowReconciler,
        now: @escaping () -> Date = Date.init
    ) {
        self.registry = registry
        self.conversationStorage = conversationStorage
        self.healthStore = healthStore
        self.shadowWriter = shadowWriter
        self.reconciler = reconciler
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
            return .init(
                generation: generation,
                registryReceipt: registryReceipt,
                registryFailureDetail: registryFailureDetail,
                primaryReceipt: primaryReceipt,
                shadowCorrelationID: nil,
                shadowStatus: nil,
                shadowCode: nil,
                shadowDetail: nil,
                invokedShadowWriter: false
            )
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
                try shadowWriter.write(payload)
            } catch ConversationShadowWriterError.parity(let detail) {
                return .parityFailed(detail)
            }
            exactPayloadForImmediateReconciliation = payload
            return .synchronized
        }
        if attempt.status == .synchronized, let payload = exactPayloadForImmediateReconciliation {
            _ = try? reconciler.reconcileAfterExactRetry(payload)
        }
        return .init(
            generation: generation,
            registryReceipt: registryReceipt,
            registryFailureDetail: registryFailureDetail,
            primaryReceipt: primaryReceipt,
            shadowCorrelationID: attempt.correlationID,
            shadowStatus: attempt.status,
            shadowCode: attempt.code,
            shadowDetail: attempt.detail,
            invokedShadowWriter: attempt.invokedShadowClosure
        )
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
