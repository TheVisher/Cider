import Foundation

/// Explicit retry reconciliation only. Construction/restart performs no repository work.
@MainActor
final class ConversationShadowReconciler {
    private let writer: ConversationShadowWriter
    private let healthStore: ConversationShadowHealthStore
    private let now: () -> Date

    init(
        writer: ConversationShadowWriter,
        healthStore: ConversationShadowHealthStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.writer = writer
        self.healthStore = healthStore
        self.now = now
    }

    @discardableResult
    func reconcileAfterExactRetry(_ payload: ConversationShadowPayload) throws -> Int {
        guard try writer.hasExactParity(payload) else { return 0 }
        return try healthStore.resolveMatching(
            conversationID: payload.conversation.metadata.id,
            jsonlHash: payload.conversation.sha256,
            registryHash: payload.registry.sha256,
            detail: "Resolved after an exact same-hash historical replay and repository parity check.",
            at: now()
        )
    }
}
