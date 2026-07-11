import Foundation

enum LegacyConversationImportState: String, Codable, Equatable, Sendable {
    case empty
    case ready
    case blocked
}

enum ConversationParityDisposition: String, Codable, Equatable, Sendable {
    case plannedInsert
    case equivalent
    case conflict
}

enum ConversationParityDiagnosticSeverity: String, Codable, Equatable, Sendable {
    case warning
    case blocker
}

enum ConversationParityDiagnosticCode: String, Codable, Equatable, Hashable, Sendable {
    case inputLimitExceeded
    case unreadableInput
    case malformedRegistryRecord
    case malformedMetadataLine
    case malformedMessageLine
    case invalidMetadataType
    case missingRegistryRecord
    case missingConversationFile
    case duplicateRoomID
    case duplicateStableID
    case duplicateConversationFile
    case duplicateRuntimeSessionID
    case duplicateMessageID
    case invalidSourceIdentity
    case conflictingSourceIdentity
    case registryMetadataMismatch
    case messageCountMismatch
    case missingGraphReference
    case graphCycle
    case attachmentsUnsupported
    case coreParityConflict
}

struct ConversationParityDiagnostic: Codable, Equatable, Sendable {
    var code: ConversationParityDiagnosticCode
    var severity: ConversationParityDiagnosticSeverity
    var location: String
    var detail: String
}

struct LegacyConversationImportInput: Codable, Equatable, Sendable {
    var path: String
    var byteCount: Int
    var sha256: String
}

struct LegacyConversationImportCounts: Codable, Equatable, Sendable {
    var registryFiles = 0
    var conversationFiles = 0
    var inputRooms = 0
    var inputMessages = 0
    var physicalMessageRows = 0
    var attachmentBearingMessages = 0
    var plannedRooms = 0
    var plannedBindings = 0
    var plannedTurns = 0
    var plannedMessages = 0
    var plannedInserts = 0
    var equivalents = 0
    var conflicts = 0
    var warningDiagnostics = 0
    var blockingDiagnostics = 0
    var omittedDiagnosticSamples = 0
}

struct LegacyConversationRoomPlanRecord: Codable, Equatable, Sendable {
    var id: UUID
    var stableKey: String
    var title: String
    var kind: String
    var lifecycleState: ConversationRoomLifecycle
    var nextTurnSequence: Int64
    var nextMessageSequence: Int64
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var disposition: ConversationParityDisposition
}

struct LegacyConversationBindingPlanRecord: Codable, Equatable, Sendable {
    var id: UUID
    var roomID: UUID
    var parentBindingID: UUID?
    var runtimeID: String
    var transportID: String
    var sourceNamespace: String
    var externalSessionID: String
    var state: ConversationRuntimeBindingState
    var cursorMessageID: String?
    var cursorTimestamp: Date?
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var disposition: ConversationParityDisposition
}

struct LegacyConversationTurnPlanRecord: Codable, Equatable, Sendable {
    var id: UUID
    var roomID: UUID
    var sequence: Int64
    var runtimeBindingID: UUID?
    var source: ConversationSourceIdentity
    var status: ConversationTurnStatus
    var metadata: [String: String]
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date
    var disposition: ConversationParityDisposition
}

struct LegacyConversationMessagePlanRecord: Codable, Equatable, Sendable {
    var id: UUID
    var roomID: UUID
    var turnID: UUID?
    var runtimeBindingID: UUID?
    var parentMessageID: UUID?
    var sequence: Int64
    var role: String
    var contentText: String
    var status: ConversationMessageStatus
    var finishReason: ConversationMessageFinishReason?
    var source: ConversationSourceIdentity?
    var sourceCreatedAt: Date
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var disposition: ConversationParityDisposition
}

struct LegacyConversationImportPlan: Codable, Equatable, Sendable {
    var rooms: [LegacyConversationRoomPlanRecord] = []
    var bindings: [LegacyConversationBindingPlanRecord] = []
    var turns: [LegacyConversationTurnPlanRecord] = []
    var messages: [LegacyConversationMessagePlanRecord] = []
}

struct LegacyConversationImportPreview: Codable, Equatable, Sendable {
    let formatVersion: String
    let readOnly: Bool
    let changed: Bool
    var state: LegacyConversationImportState
    var safeForBackfill: Bool
    var safeForShadowWrites: Bool
    var inputs: [LegacyConversationImportInput]
    var counts: LegacyConversationImportCounts
    var diagnosticCounts: [String: Int]
    var diagnosticSamples: [ConversationParityDiagnostic]
    var plan: LegacyConversationImportPlan

    init(
        state: LegacyConversationImportState,
        safeForBackfill: Bool,
        safeForShadowWrites: Bool,
        inputs: [LegacyConversationImportInput],
        counts: LegacyConversationImportCounts,
        diagnosticCounts: [String: Int],
        diagnosticSamples: [ConversationParityDiagnostic],
        plan: LegacyConversationImportPlan
    ) {
        formatVersion = "cider.legacy-conversation-import-preview.v1"
        readOnly = true
        changed = false
        self.state = state
        self.safeForBackfill = safeForBackfill
        self.safeForShadowWrites = safeForShadowWrites
        self.inputs = inputs
        self.counts = counts
        self.diagnosticCounts = diagnosticCounts
        self.diagnosticSamples = diagnosticSamples
        self.plan = plan
    }
}
