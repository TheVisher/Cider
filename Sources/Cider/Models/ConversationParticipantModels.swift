import Foundation

enum ConversationRoomParticipantRole: String, Codable, CaseIterable, Sendable {
    case actingAgent = "acting_agent"
    case advisor
    case delegate
}

struct ConversationRoomParticipant: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let profile: ConversationAgentProfile
    var role: ConversationRoomParticipantRole
    let addedAt: Date
}

struct ConversationRoomParticipantDraft: Equatable, Sendable {
    let profileID: String
    let role: ConversationRoomParticipantRole
}

struct ConversationRoomParticipantRoster: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    static let maximumParticipantCount = 8

    let schemaVersion: Int
    let members: [ConversationRoomParticipant]
    let updatedAt: Date

    init(
        members: [ConversationRoomParticipant],
        updatedAt: Date,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.members = members
        self.updatedAt = updatedAt
    }

    var actingAgent: ConversationRoomParticipant? {
        members.first(where: { $0.role == .actingAgent })
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion else {
            throw ConversationParticipantInvocationError.invalid(
                "The room participant roster uses an unsupported schema version."
            )
        }
        guard !members.isEmpty, members.count <= Self.maximumParticipantCount else {
            throw ConversationParticipantInvocationError.invalid(
                "Room rosters must contain between 1 and \(Self.maximumParticipantCount) participants."
            )
        }
        guard members.filter({ $0.role == .actingAgent }).count == 1 else {
            throw ConversationParticipantInvocationError.invalid(
                "Room rosters must contain exactly one acting agent."
            )
        }
        var participantIDs = Set<UUID>()
        var profileIDs = Set<String>()
        for member in members {
            try ConversationAgentProfile.validate(member.profile)
            guard participantIDs.insert(member.id).inserted,
                  profileIDs.insert(member.profile.id).inserted
            else {
                throw ConversationParticipantInvocationError.invalid(
                    "Room participant and profile identities must be unique."
                )
            }
        }
    }
}

enum ConversationParticipantInvocationOrigin: Codable, Equatable, Sendable {
    case user
    case participant(UUID)
}

struct ConversationParticipantInvocationLimits: Codable, Equatable, Sendable {
    let maximumParticipants: Int
    let maximumConcurrency: Int
    let maximumUpdatesPerParticipant: Int
    let maximumOutputCharactersPerParticipant: Int
    let tokenBudgetPerParticipant: Int
    let recursionDepth: Int

    static let checkpoint = ConversationParticipantInvocationLimits(
        maximumParticipants: 4,
        maximumConcurrency: 1,
        maximumUpdatesPerParticipant: 24,
        maximumOutputCharactersPerParticipant: 24_000,
        tokenBudgetPerParticipant: 8_000,
        recursionDepth: 0
    )

    func validate() throws {
        guard (1...4).contains(maximumParticipants),
              maximumConcurrency == 1,
              (1...24).contains(maximumUpdatesPerParticipant),
              (1...24_000).contains(maximumOutputCharactersPerParticipant),
              (1...8_000).contains(tokenBudgetPerParticipant),
              recursionDepth == 0
        else {
            throw ConversationParticipantInvocationError.invalid(
                "Participant invocations require checkpoint-bounded participants, sequential execution, updates, output, budget, and zero recursion depth."
            )
        }
    }
}

struct ConversationParticipantInvocationRequest: Equatable, Sendable {
    let id: UUID
    let roomID: UUID
    let prompt: String
    let selectedParticipantIDs: [UUID]
    let origin: ConversationParticipantInvocationOrigin
    let limits: ConversationParticipantInvocationLimits

    init(
        id: UUID = UUID(),
        roomID: UUID,
        prompt: String,
        selectedParticipantIDs: [UUID],
        origin: ConversationParticipantInvocationOrigin,
        limits: ConversationParticipantInvocationLimits
    ) {
        self.id = id
        self.roomID = roomID
        self.prompt = prompt
        self.selectedParticipantIDs = selectedParticipantIDs
        self.origin = origin
        self.limits = limits
    }
}

enum ConversationParticipantActivityKind: String, Codable, Equatable, Sendable {
    case work
    case tool
    case status
}

struct ConversationParticipantExecutionUpdate: Codable, Equatable, Sendable {
    let kind: ConversationParticipantActivityKind
    let summary: String
}

struct ConversationParticipantActivity: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let invocationID: UUID
    let runID: UUID
    let participantID: UUID
    let sequence: Int
    let kind: ConversationParticipantActivityKind
    let summary: String
}

struct ConversationParticipantRunAttribution: Codable, Equatable, Sendable {
    let invocationID: UUID
    let runID: UUID
    let participantID: UUID
    let profileID: String
    let participantRole: ConversationRoomParticipantRole
    let selectionSequence: Int
}

struct ConversationParticipantMessageAttribution: Codable, Equatable, Sendable {
    let invocationID: UUID
    let runID: UUID?
    let participantID: UUID?
    let profileID: String?
    let participantRole: ConversationRoomParticipantRole?
}

struct ConversationParticipantExecutionRequest: Equatable, Sendable {
    let invocationID: UUID
    let runID: UUID
    let roomID: UUID
    let participant: ConversationRoomParticipant
    let prompt: String
    let limits: ConversationParticipantInvocationLimits
}

struct ConversationParticipantExecutionResult: Equatable, Sendable {
    let text: String
    let source: ConversationSourceIdentity
    let updates: [ConversationParticipantExecutionUpdate]
}

protocol ConversationParticipantRuntimeExecuting: Sendable {
    var binding: ConversationAgentRuntimeBinding { get }
    func execute(_ request: ConversationParticipantExecutionRequest) async throws
        -> ConversationParticipantExecutionResult
    func cancel(executionID: UUID) async
}

struct ConversationParticipantRuntimeRegistry: Sendable {
    private let executors: [String: any ConversationParticipantRuntimeExecuting]

    init(executors: [any ConversationParticipantRuntimeExecuting]) throws {
        var indexed: [String: any ConversationParticipantRuntimeExecuting] = [:]
        for executor in executors {
            let key = Self.key(executor.binding)
            guard indexed[key] == nil else {
                throw ConversationParticipantInvocationError.invalid(
                    "Participant runtime bindings must have one explicit executor."
                )
            }
            indexed[key] = executor
        }
        self.executors = indexed
    }

    func executor(
        for binding: ConversationAgentRuntimeBinding
    ) -> (any ConversationParticipantRuntimeExecuting)? {
        executors[Self.key(binding)]
    }

    private static func key(_ binding: ConversationAgentRuntimeBinding) -> String {
        "\(binding.providerID)\u{1F}\(binding.runtimeID)"
    }
}

enum ConversationParticipantRunStatus: String, Codable, Equatable, Sendable {
    case running
    case completed
    case failed
    case cancelled
}

struct ConversationParticipantRunResult: Codable, Equatable, Sendable {
    let runID: UUID
    let participantID: UUID
    let status: ConversationParticipantRunStatus
}

struct ConversationParticipantInvocationResult: Codable, Equatable, Sendable {
    let invocationID: UUID
    let roomID: UUID
    let runs: [ConversationParticipantRunResult]
}

enum ConversationParticipantInvocationError: Error, Equatable, LocalizedError {
    case invalid(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message): message
        }
    }
}
