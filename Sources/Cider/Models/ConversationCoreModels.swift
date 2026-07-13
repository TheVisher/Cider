import Foundation

enum ConversationRoomLifecycle: String, Codable, CaseIterable, Sendable {
    case active
    case archived
    case trashed
}

enum ConversationRuntimeBindingState: String, Codable, CaseIterable, Sendable {
    case active
    case inactive
    case disconnected
}

enum ConversationTurnStatus: String, Codable, CaseIterable, Sendable {
    case unknown
    case pending
    case running
    case waiting
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .unknown, .completed, .failed, .cancelled: true
        case .pending, .running, .waiting: false
        }
    }
}

enum ConversationMessageStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case streaming
    case complete
    case incomplete
}

enum ConversationMessageFinishReason: String, Codable, CaseIterable, Sendable {
    case stop
    case cancelled
    case error
    case length
    case contentFilter = "content_filter"
    case other
}

struct ConversationSourceIdentity: Codable, Equatable, Hashable, Sendable {
    var namespace: String
    var id: String
}

struct ConversationRoom: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var stableKey: String?
    var title: String
    var kind: String
    var lifecycleState: ConversationRoomLifecycle
    var nextTurnSequence: Int64
    var nextMessageSequence: Int64
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var trashedAt: Date?
}

struct ConversationRoomDraft: Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var stableKey: String?
    var title: String
    var kind: String = "chat"
    var metadata: [String: String] = [:]
    var agentAssignment: ConversationRoomAgentAssignment?
    var participantRoster: ConversationRoomParticipantRoster?
    var createdAt: Date = Date()
    var updatedAt: Date?
}

struct ConversationRuntimeBinding: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var roomID: UUID
    var parentBindingID: UUID?
    var runtimeID: String
    var transportID: String
    var sourceNamespace: String
    var externalSessionID: String?
    var state: ConversationRuntimeBindingState
    var cursorMessageID: String?
    var cursorTimestamp: Date?
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
}

struct ConversationRuntimeBindingDraft: Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var roomID: UUID
    var parentBindingID: UUID?
    var runtimeID: String
    var transportID: String
    var sourceNamespace: String
    var externalSessionID: String?
    var state: ConversationRuntimeBindingState = .active
    var cursorMessageID: String?
    var cursorTimestamp: Date?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
    var updatedAt: Date?
}

struct ConversationTurnError: Codable, Equatable, Sendable {
    var code: String
    var detail: String?
}

struct ConversationTurn: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var roomID: UUID
    var sequence: Int64
    var runtimeBindingID: UUID?
    var source: ConversationSourceIdentity?
    var status: ConversationTurnStatus
    var error: ConversationTurnError?
    var metadata: [String: String]
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var updatedAt: Date
}

struct ConversationTurnDraft: Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var roomID: UUID
    var runtimeBindingID: UUID?
    var source: ConversationSourceIdentity?
    var status: ConversationTurnStatus = .pending
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
}

struct ConversationMessage: Identifiable, Codable, Equatable, Sendable {
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
    var sourceCreatedAt: Date?
    var metadata: [String: String]
    var createdAt: Date
    var updatedAt: Date
}

struct ConversationMessageDraft: Codable, Equatable, Sendable {
    var id: UUID = UUID()
    var roomID: UUID
    var turnID: UUID?
    var runtimeBindingID: UUID?
    var parentMessageID: UUID?
    var role: String
    var contentText: String
    var status: ConversationMessageStatus = .complete
    var finishReason: ConversationMessageFinishReason?
    var source: ConversationSourceIdentity?
    var sourceCreatedAt: Date?
    var metadata: [String: String] = [:]
    var createdAt: Date = Date()
}

enum ConversationMessageUpsertDisposition: String, Codable, Equatable, Sendable {
    case inserted
    case updatedSameSource
    case unchangedReplay
}

enum ConversationMessageWriteIntent: String, Codable, Equatable, Sendable {
    case historicalReplay
    case liveContinuation
}

struct ConversationMessageUpsertResult: Codable, Equatable, Sendable {
    var disposition: ConversationMessageUpsertDisposition
    var message: ConversationMessage
}

struct ConversationTurnSnapshot: Codable, Equatable, Sendable {
    var turn: ConversationTurn
    var messages: [ConversationMessage]
}
