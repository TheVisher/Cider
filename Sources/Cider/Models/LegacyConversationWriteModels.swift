import Foundation

enum ConversationShadowDiagnosticCode: String, Codable, Equatable, Hashable, Sendable {
    case primaryEncodeFailed = "primary_encode_failed"
    case primaryWriteFailed = "primary_write_failed"
    case primaryVerificationFailed = "primary_verification_failed"
    case registryMismatch = "registry_mismatch"
    case gateStale = "gate_stale"
    case gateBlocked = "gate_blocked"
    case shadowRepositoryFailed = "shadow_repository_failed"
    case shadowParityFailed = "shadow_parity_failed"
    case diagnosticStoreSaturated = "diagnostic_store_saturated"
}

enum ConversationShadowHealthStatus: String, Codable, Equatable, Sendable {
    case reserved
    case synchronized
    case repairNeeded = "repair_needed"
    case outcomeUnknown = "outcome_unknown"
    case resolved
}

struct LegacyConversationWriteGeneration: Equatable, Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

struct LegacyConversationMetadataSnapshot: Equatable, Sendable {
    let id: UUID
    let title: String
    let created: Date
    let updated: Date
    let model: String
    let messageCount: Int
    let type: String
    let runtimeID: String?
    let activeRuntimeSessionID: String?
    let runtimeSessionLineage: [String]?
    let runtimeSource: String?
    let runtimeLastSyncedAt: Date?
    let runtimeLastSyncedMessageID: String?
    let runtimeLastSyncedTimestamp: Date?
    let runtimeLastImportedSessionID: String?

    init(_ metadata: AIConversationMeta) {
        id = metadata.id
        title = metadata.title
        created = metadata.created
        updated = metadata.updated
        model = metadata.model
        messageCount = metadata.messageCount
        type = metadata.type
        runtimeID = metadata.runtimeID
        activeRuntimeSessionID = metadata.activeRuntimeSessionID
        runtimeSessionLineage = metadata.runtimeSessionLineage
        runtimeSource = metadata.runtimeSource
        runtimeLastSyncedAt = metadata.runtimeLastSyncedAt
        runtimeLastSyncedMessageID = metadata.runtimeLastSyncedMessageID
        runtimeLastSyncedTimestamp = metadata.runtimeLastSyncedTimestamp
        runtimeLastImportedSessionID = metadata.runtimeLastImportedSessionID
    }
}

struct LegacyConversationMessageSnapshot: Equatable, Sendable {
    let id: UUID
    let role: AIAssistantMessage.Role
    let content: String
    let timestamp: Date
    let sourceID: String?
    let sourceSessionID: String?
    let sourceName: String?
    let attachments: [AIAssistantAttachment]

    init(_ message: AIAssistantMessage) {
        id = message.id
        role = message.role
        content = message.content
        timestamp = message.timestamp
        sourceID = message.sourceID
        sourceSessionID = message.sourceSessionID
        sourceName = message.sourceName
        attachments = message.attachments
    }
}

struct LegacyConversationSnapshot: Equatable, Sendable {
    let generation: LegacyConversationWriteGeneration
    let metadata: LegacyConversationMetadataSnapshot
    let messages: [LegacyConversationMessageSnapshot]
    let filename: String
    let bytes: Data
    let sha256: String
}

enum LegacyConversationWriteStatus: String, Equatable, Sendable {
    case committed
    case failed
}

struct LegacyConversationWriteReceipt: Equatable, Sendable {
    let status: LegacyConversationWriteStatus
    let generation: LegacyConversationWriteGeneration
    let conversationID: UUID
    let committedAt: Date?
    let filename: String?
    let sha256: String?
    let messageCount: Int
    let code: ConversationShadowDiagnosticCode?
    let detail: String?
    let snapshot: LegacyConversationSnapshot?

    var isCommitted: Bool { status == .committed && snapshot != nil }
}

struct LegacyRegistrySnapshot: Equatable, Sendable {
    let generation: LegacyConversationWriteGeneration
    let record: CiderAgentChatRecord
    let filename: String
    let bytes: Data
    let sha256: String
}

struct LegacyRegistryWriteReceipt: Equatable, Sendable {
    let generation: LegacyConversationWriteGeneration
    let conversationID: UUID
    let committedAt: Date
    let filename: String
    let sha256: String
    let snapshot: LegacyRegistrySnapshot
}

struct ConversationShadowPayload: Equatable, Sendable {
    let generation: LegacyConversationWriteGeneration
    let registry: LegacyRegistrySnapshot
    let conversation: LegacyConversationSnapshot
}
