import Foundation

@MainActor
final class ConversationShadowRuntimeComposition {
    let database: CiderDatabase
    let repository: ConversationRepository
    let healthStore: ConversationShadowHealthStore
    let mapper: LegacyConversationSnapshotMapper
    let writer: ConversationShadowWriter
    let reconciler: ConversationShadowReconciler
    let receiptReporter: ConversationShadowActivationReceiptReporter
    let coordinator: LegacyConversationPrimarySaveCoordinator

    init(
        database: CiderDatabase,
        diagnosticsDirectoryURL: URL,
        registry: CiderAgentChatRegistry,
        conversationStorage: AIConversationStorage,
        runtimeLogger: ConversationShadowRuntimeLogger
    ) throws {
        guard database.isOpen else {
            throw ConversationShadowRuntimeCompositionError.databaseClosed
        }
        let repository = ConversationRepository(database: database)
        let healthStore = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: diagnosticsDirectoryURL
        )
        let mapper = LegacyConversationSnapshotMapper()
        let writer = ConversationShadowWriter(
            database: database,
            repository: repository,
            mapper: mapper
        )
        let reconciler = ConversationShadowReconciler(
            writer: writer,
            healthStore: healthStore
        )
        let receiptReporter = ConversationShadowActivationReceiptReporter(
            runtimeLogger: runtimeLogger
        )
        let coordinator = LegacyConversationPrimarySaveCoordinator(
            registry: registry,
            conversationStorage: conversationStorage,
            healthStore: healthStore,
            shadowWriter: writer,
            reconciler: reconciler,
            receiptReporter: receiptReporter
        )

        self.database = database
        self.repository = repository
        self.healthStore = healthStore
        self.mapper = mapper
        self.writer = writer
        self.reconciler = reconciler
        self.receiptReporter = receiptReporter
        self.coordinator = coordinator
    }
}

enum ConversationShadowRuntimeCompositionError: Error, Equatable {
    case databaseClosed
}
