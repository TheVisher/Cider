import Foundation

enum AgentRoomsAgentSendEligibility: Equatable, Sendable {
    case eligible(profile: ConversationAgentProfile)
    case ineligible(profileID: String?, displayName: String?, reason: String)
}

@MainActor
protocol AgentRoomsAgentAssignmentReading: AnyObject {
    var profiles: [ConversationAgentProfile] { get }
    var defaultProfile: ConversationAgentProfile { get }
    func assignment(roomID: UUID) throws -> ConversationRoomAgentAssignment?
    func sendEligibility(roomID: UUID) throws -> AgentRoomsAgentSendEligibility
    func presentation(roomID: UUID) throws -> AgentRoomActingAgent?
}

@MainActor
protocol AgentRoomsAgentAssignmentActing: AgentRoomsAgentAssignmentReading {
    @discardableResult
    func assign(profileID: String, roomID: UUID) throws -> ConversationRoomAgentAssignment
}

/// Provider-neutral assignment boundary over one canonical Cider room UUID.
/// Runtime sessions are deliberately absent from profiles and assignments.
@MainActor
final class AgentRoomsAgentAssignmentService: AgentRoomsAgentAssignmentActing {
    private let repository: ConversationRepository
    private let catalog: ConversationAgentProfileCatalog
    private let now: () -> Date

    init(
        repository: ConversationRepository,
        catalog: ConversationAgentProfileCatalog = AgentRoomsProductionAgentProfiles.catalog,
        now: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.catalog = catalog
        self.now = now
    }

    var profiles: [ConversationAgentProfile] { catalog.profiles }
    var defaultProfile: ConversationAgentProfile { catalog.defaultProfile }

    func defaultAssignment(at date: Date) -> ConversationRoomAgentAssignment {
        ConversationRoomAgentAssignment(profile: defaultProfile, assignedAt: date)
    }

    func assignment(roomID: UUID) throws -> ConversationRoomAgentAssignment? {
        try repository.agentAssignment(roomID: roomID)
    }

    @discardableResult
    func assign(profileID: String, roomID: UUID) throws -> ConversationRoomAgentAssignment {
        guard let profile = catalog.profile(id: profileID) else {
            throw ConversationRepositoryError.invalidDraft("The selected agent profile is not configured.")
        }
        let room = try requireAssignableRoom(id: roomID)
        guard room.lifecycleState == .active else {
            throw ConversationRepositoryError.invalidDraft(
                "Archived or trashed conversations cannot change acting agent."
            )
        }
        let timestamp = now()
        return try repository.setAgentAssignment(
            roomID: room.id,
            assignment: .init(profile: profile, assignedAt: timestamp),
            at: timestamp
        )
    }

    func sendEligibility(roomID: UUID) throws -> AgentRoomsAgentSendEligibility {
        _ = try requireAssignableRoom(id: roomID)
        guard let assignment = try repository.agentAssignment(roomID: roomID) else {
            return .ineligible(
                profileID: nil,
                displayName: nil,
                reason: "Choose an acting agent before sending."
            )
        }
        let assigned = assignment.profile
        guard let configured = catalog.profile(id: assigned.id) else {
            return .ineligible(
                profileID: assigned.id,
                displayName: assigned.displayName,
                reason: "This room’s assigned agent is no longer configured. Choose another agent."
            )
        }
        guard configured.displayName == assigned.displayName,
              configured.runtimeBinding == assigned.runtimeBinding,
              configured.capabilities == assigned.capabilities
        else {
            return .ineligible(
                profileID: assigned.id,
                displayName: assigned.displayName,
                reason: "This agent’s runtime configuration changed. Re-select it before sending."
            )
        }
        switch configured.availability {
        case .available:
            return .eligible(profile: configured)
        case .unavailable(let reason):
            return .ineligible(
                profileID: configured.id,
                displayName: configured.displayName,
                reason: reason
            )
        }
    }

    func presentation(roomID: UUID) throws -> AgentRoomActingAgent? {
        guard let assignment = try repository.agentAssignment(roomID: roomID) else { return nil }
        let eligibility = try sendEligibility(roomID: roomID)
        let sendEligible: Bool
        let unavailableReason: String?
        switch eligibility {
        case .eligible:
            sendEligible = true
            unavailableReason = nil
        case .ineligible(_, _, let reason):
            sendEligible = false
            unavailableReason = reason
        }
        return AgentRoomActingAgent(
            profileID: assignment.profile.id,
            displayName: assignment.profile.displayName,
            providerID: assignment.profile.runtimeBinding.providerID,
            runtimeID: assignment.profile.runtimeBinding.runtimeID,
            capabilities: assignment.profile.capabilities.map(\.displayName),
            sendEligible: sendEligible,
            unavailableReason: unavailableReason
        )
    }

    private func requireAssignableRoom(id: UUID) throws -> ConversationRoom {
        guard let room = try repository.room(id: id) else {
            throw ConversationRepositoryError.notFound("Conversation room was not found.")
        }
        let metadata = ConversationRepository.metadataWithoutAgentConfiguration(room.metadata)
        let isNative = room.stableKey == nil
            && room.kind == "chat"
            && metadata["authority"] == AgentRoomsConversationPersistence.nativeRoomAuthority
            && metadata["schema_version"] == "1"
            && metadata.count == 2
        let isReservedTestChat = room.stableKey == AgentRoomsTestChatPersistence.stableRoomKey
            && room.kind == "cider-test-chat"
            && metadata["authority"] == AgentRoomsConversationPersistence.testRoomAuthority
            && metadata["schema_version"] == "1"
            && metadata["source"] == "cider-rooms-live-continuation"
            && metadata.count == 3
        guard isNative || isReservedTestChat else {
            throw ConversationRepositoryError.invalidDraft(
                "Only Cider-owned canonical rooms can change acting agent."
            )
        }
        return room
    }
}
