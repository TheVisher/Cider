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
        guard try writer.hasVerifiedSequentialCompletedSnapshotParity(payload) else { return 0 }
        return try healthStore.resolveRepresented(
            conversationID: payload.conversation.metadata.id,
            newerPayload: payload,
            representationProof: { record in
                guard let fingerprint = record.semanticFingerprint else { return false }
                return (try? self.writer.provesRepresentation(of: fingerprint, by: payload)) == true
            },
            detail: "Resolved after newer repository parity proved the older semantic high-water is an exact prefix.",
            at: now()
        )
    }
}
