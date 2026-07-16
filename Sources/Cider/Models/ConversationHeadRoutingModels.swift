import Foundation

struct ConversationRoutingRecipient: Codable, Equatable, Hashable, Sendable {
    let profileID: String
    let displayName: String

    init(profileID: String, displayName: String) {
        self.profileID = profileID
        self.displayName = displayName
    }

    init(profile: ConversationAgentProfile) {
        self.init(profileID: profile.id, displayName: profile.displayName)
    }

    func validate() throws {
        guard !profileID.isEmpty,
              profileID.count <= ConversationAgentProfile.maximumIdentifierLength,
              profileID.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar)
                      || scalar == "-" || scalar == "_" || scalar == "."
              }),
              displayName == displayName.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty,
              displayName.count <= ConversationAgentProfile.maximumDisplayNameLength,
              !displayName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw ConversationRepositoryError.integrity(
                "Conversation routing contains an invalid recipient identity."
            )
        }
    }
}

struct ConversationSubmissionRoutingContext: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let recipients: [ConversationRoutingRecipient]
    let observedHeadRoutingEpoch: Int64
    let observedRoomMessageSequence: Int64

    init(
        recipients: [ConversationRoutingRecipient],
        observedHeadRoutingEpoch: Int64,
        observedRoomMessageSequence: Int64,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.recipients = recipients
        self.observedHeadRoutingEpoch = observedHeadRoutingEpoch
        self.observedRoomMessageSequence = observedRoomMessageSequence
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              !recipients.isEmpty,
              recipients.count <= ConversationRoomParticipantRoster.maximumParticipantCount,
              Set(recipients.map(\.profileID)).count == recipients.count,
              observedHeadRoutingEpoch >= 0,
              observedRoomMessageSequence >= 0
        else {
            throw ConversationRepositoryError.integrity(
                "Conversation submission contains invalid routing provenance."
            )
        }
        try recipients.forEach { try $0.validate() }
    }
}

struct ConversationRoutingAcceptanceRecord: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let userMessageID: UUID
    let sourceNamespace: String
    let routing: ConversationSubmissionRoutingContext

    init(
        userMessageID: UUID,
        sourceNamespace: String,
        routing: ConversationSubmissionRoutingContext,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.userMessageID = userMessageID
        self.sourceNamespace = sourceNamespace
        self.routing = routing
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              sourceNamespace == sourceNamespace.trimmingCharacters(in: .whitespacesAndNewlines),
              !sourceNamespace.isEmpty
        else {
            throw ConversationRepositoryError.integrity(
                "Conversation routing acceptance contains invalid authority provenance."
            )
        }
        try routing.validate()
    }
}

struct ConversationRoutingAcceptanceHistory: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let records: [ConversationRoutingAcceptanceRecord]

    init(
        records: [ConversationRoutingAcceptanceRecord],
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              Set(records.map(\.userMessageID)).count == records.count
        else {
            throw ConversationRepositoryError.integrity(
                "Conversation routing acceptance history is invalid."
            )
        }
        try records.forEach { try $0.validate() }
    }
}

struct ConversationGeneratedRoutingContext: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let recipient: ConversationRoutingRecipient
    let observedHeadRoutingEpoch: Int64
    let observedRoomMessageSequence: Int64
    let originatingUserMessageID: UUID

    init(
        recipient: ConversationRoutingRecipient,
        observedHeadRoutingEpoch: Int64,
        observedRoomMessageSequence: Int64,
        originatingUserMessageID: UUID,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.recipient = recipient
        self.observedHeadRoutingEpoch = observedHeadRoutingEpoch
        self.observedRoomMessageSequence = observedRoomMessageSequence
        self.originatingUserMessageID = originatingUserMessageID
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              observedHeadRoutingEpoch >= 0,
              observedRoomMessageSequence >= 0
        else {
            throw ConversationRepositoryError.integrity(
                "Generated conversation output contains invalid routing provenance."
            )
        }
        try recipient.validate()
    }
}

enum ConversationHeadRoutingChangeActor: String, Codable, Equatable, Sendable {
    case user
    case system
    case migration
}

struct ConversationHeadRoutingChangeEvent: Codable, Equatable, Sendable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let actor: ConversationHeadRoutingChangeActor
    let oldHead: ConversationRoutingRecipient?
    let newHead: ConversationRoutingRecipient
    let oldHeadRoutingEpoch: Int64
    let newHeadRoutingEpoch: Int64
    let changedAt: Date

    init(
        id: UUID = UUID(),
        actor: ConversationHeadRoutingChangeActor,
        oldHead: ConversationRoutingRecipient?,
        newHead: ConversationRoutingRecipient,
        oldHeadRoutingEpoch: Int64,
        newHeadRoutingEpoch: Int64,
        changedAt: Date,
        schemaVersion: Int = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.actor = actor
        self.oldHead = oldHead
        self.newHead = newHead
        self.oldHeadRoutingEpoch = oldHeadRoutingEpoch
        self.newHeadRoutingEpoch = newHeadRoutingEpoch
        self.changedAt = changedAt
    }

    func validate() throws {
        guard schemaVersion == Self.schemaVersion,
              oldHeadRoutingEpoch >= 0,
              newHeadRoutingEpoch == oldHeadRoutingEpoch + 1
        else {
            throw ConversationRepositoryError.integrity(
                "Conversation head-change event contains invalid routing versions."
            )
        }
        try oldHead?.validate()
        try newHead.validate()
    }
}

enum ConversationPublicationState: String, Codable, Equatable, Sendable {
    case heldStale = "held_stale"
}

enum ConversationResultPublicationOutcome: Equatable, Sendable {
    case published
    case heldStale
    case terminated
}
