import Foundation

/// A bounded, read-only presentation adapter for the secondary canonical conversation store.
@MainActor
final class AgentRoomsReadService {
    static let fallbackPreview = "No supported messages in this canonical record."
    static let unavailableMessage = "Canonical Rooms data is temporarily unavailable. Try again."

    private static let roomLimit = 20
    private static let messageLimit = 100
    private static let runtimeBindingLimit = 20
    private static let turnLimit = 1

    private let loadRooms: (ConversationRoomLifecycle, Int) throws -> [ConversationRoom]
    private let searchRooms: (String, ConversationRoomLifecycle, Int) throws -> [ConversationRoom]
    private let loadRecentMessages: (UUID, Int) throws -> [ConversationMessage]
    private let loadRuntimeBindings: (UUID, Int) throws -> [ConversationRuntimeBinding]
    private let loadRecentTurns: (UUID, Int) throws -> [ConversationTurn]
    private let loadActingAgent: (UUID) throws -> AgentRoomActingAgent?
    private let loadParticipantRoster: (UUID) throws -> AgentRoomParticipantRoster?
    private let loadMessageAttribution: (ConversationMessage) throws -> ConversationParticipantMessageAttribution?
    private let loadTurnAttribution: (ConversationTurn) throws -> ConversationParticipantRunAttribution?
    private let loadParticipantActivity: (UUID, UUID) throws -> [ConversationParticipantActivity]
    private let now: () -> Date

    init(
        repository: ConversationRepository,
        agentAssignments: (any AgentRoomsAgentAssignmentReading)? = nil,
        participants: (any AgentRoomsParticipantReading)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let assignments = agentAssignments
            ?? AgentRoomsAgentAssignmentService(repository: repository, now: now)
        self.loadRooms = repository.rooms(lifecycle:limit:)
        self.searchRooms = repository.searchRooms(query:lifecycle:limit:)
        self.loadRecentMessages = repository.recentMessages(roomID:limit:)
        self.loadRuntimeBindings = repository.runtimeBindings(roomID:limit:)
        self.loadRecentTurns = repository.recentTurns(roomID:limit:)
        self.loadActingAgent = assignments.presentation(roomID:)
        let participantService: any AgentRoomsParticipantReading = participants
            ?? AgentRoomsParticipantService(repository: repository, now: now)
        self.loadParticipantRoster = participantService.presentation(roomID:)
        self.loadMessageAttribution = participantService.messageAttribution(_:)
        self.loadTurnAttribution = participantService.turnAttribution(_:)
        self.loadParticipantActivity = participantService.activity(roomID:invocationID:)
        self.now = now
    }

    /// Internal injection keeps tests temporary and failure paths deterministic without exposing writes.
    init(
        loadRooms: @escaping (ConversationRoomLifecycle, Int) throws -> [ConversationRoom],
        searchRooms: ((String, ConversationRoomLifecycle, Int) throws -> [ConversationRoom])? = nil,
        loadRecentMessages: @escaping (UUID, Int) throws -> [ConversationMessage],
        loadRuntimeBindings: @escaping (UUID, Int) throws -> [ConversationRuntimeBinding],
        loadRecentTurns: @escaping (UUID, Int) throws -> [ConversationTurn],
        loadActingAgent: @escaping (UUID) throws -> AgentRoomActingAgent? = { _ in nil },
        loadParticipantRoster: @escaping (UUID) throws -> AgentRoomParticipantRoster? = { _ in nil },
        loadMessageAttribution: @escaping (ConversationMessage) throws -> ConversationParticipantMessageAttribution? = { _ in nil },
        loadTurnAttribution: @escaping (ConversationTurn) throws -> ConversationParticipantRunAttribution? = { _ in nil },
        loadParticipantActivity: @escaping (UUID, UUID) throws -> [ConversationParticipantActivity] = { _, _ in [] },
        now: @escaping () -> Date = Date.init
    ) {
        self.loadRooms = loadRooms
        self.searchRooms = searchRooms ?? { query, lifecycle, limit in
            let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
            return try loadRooms(lifecycle, limit).filter {
                normalized.isEmpty || $0.title.localizedCaseInsensitiveContains(normalized)
            }
        }
        self.loadRecentMessages = loadRecentMessages
        self.loadRuntimeBindings = loadRuntimeBindings
        self.loadRecentTurns = loadRecentTurns
        self.loadActingAgent = loadActingAgent
        self.loadParticipantRoster = loadParticipantRoster
        self.loadMessageAttribution = loadMessageAttribution
        self.loadTurnAttribution = loadTurnAttribution
        self.loadParticipantActivity = loadParticipantActivity
        self.now = now
    }

    func loadWorkspace() -> AgentRoomsWorkspaceState {
        loadWorkspace(request: .init())
    }

    func loadWorkspace(request: AgentRoomsWorkspaceRequest) -> AgentRoomsWorkspaceState {
        do {
            let query = request.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalRooms = query.isEmpty
                ? try loadRooms(request.scope.lifecycle, Self.roomLimit)
                : try searchRooms(query, request.scope.lifecycle, Self.roomLimit)
            let visibleRooms = canonicalRooms.filter {
                $0.stableKey != AgentRoomsTestChatPersistence.stableRoomKey
            }
            guard !visibleRooms.isEmpty else { return .empty(authority: .canonicalIncomplete) }

            let rooms = try visibleRooms.map { room in
                let messages = try loadRecentMessages(room.id, Self.messageLimit)
                let bindings = try loadRuntimeBindings(room.id, Self.runtimeBindingLimit)
                let newestTurn = try loadRecentTurns(room.id, Self.turnLimit).first
                return try mapRoom(room, messages: messages, bindings: bindings, newestTurn: newestTurn)
            }
            guard let selectedRoomID = rooms.first?.id else { return .empty(authority: .canonicalIncomplete) }
            return .loaded(
                authority: .canonicalIncomplete,
                rooms: rooms,
                selectedRoomID: selectedRoomID
            )
        } catch {
            return .failed(authority: .canonicalIncomplete, message: Self.unavailableMessage)
        }
    }

    private func mapRoom(
        _ room: ConversationRoom,
        messages: [ConversationMessage],
        bindings: [ConversationRuntimeBinding],
        newestTurn: ConversationTurn?
    ) throws -> AgentRoom {
        let actingAgent = try loadActingAgent(room.id)
        let participantRoster = try loadParticipantRoster(room.id)
        let binding = bindings.first(where: { $0.state == .active }) ?? bindings.first
        let runtimeLabel = actingAgent?.displayName
            ?? binding.map { displayRuntime($0.runtimeID) }
            ?? "Unassigned"
        let supportedMessages = try messages.compactMap { message -> AgentRoomMessage? in
            switch message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "user":
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .human,
                    author: "You",
                    body: message.contentText
                )
            case "assistant":
                let attribution = try loadMessageAttribution(message)
                let author = attribution?.participantID.flatMap { participantID in
                    participantRoster?.members.first(where: { $0.id == participantID })?.displayName
                } ?? runtimeLabel
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .agent,
                    author: author,
                    body: message.contentText
                )
            default:
                return nil
            }
        }
        let preview = supportedMessages.reversed().lazy
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? Self.fallbackPreview
        let title = room.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let receipt = mapReceipt(newestTurn, roomID: room.id, bindings: bindings)
        let participantActivity: AgentRoomParticipantActivitySummary?
        if let newestTurn,
           let attribution = try loadTurnAttribution(newestTurn) {
            let updates = try loadParticipantActivity(room.id, attribution.invocationID)
            let status: ConversationParticipantRunStatus = switch newestTurn.status {
            case .completed: .completed
            case .cancelled: .cancelled
            case .pending, .running, .waiting: .running
            case .unknown, .failed: .failed
            }
            participantActivity = AgentRoomParticipantActivitySummary(
                participantCount: max(1, Set(updates.map(\.participantID)).count),
                updateCount: updates.count,
                status: status,
                updates: updates
            )
        } else {
            participantActivity = nil
        }

        return AgentRoom(
            id: room.id.uuidString,
            title: title.isEmpty ? "Untitled Room" : title,
            preview: preview,
            updatedAt: room.updatedAt,
            relativeTime: relativeTime(from: room.updatedAt),
            transcript: AgentRoomTranscript(
                runtimeLabel: runtimeLabel,
                messages: supportedMessages,
                link: nil,
                receipt: receipt,
                futureArtifact: nil
            ),
            actingAgent: actingAgent,
            participantRoster: participantRoster,
            participantActivity: participantActivity,
            lifecycleState: room.lifecycleState
        )
    }

    private func mapReceipt(
        _ turn: ConversationTurn?,
        roomID: UUID,
        bindings: [ConversationRuntimeBinding]
    ) -> AgentRoomReceipt? {
        guard let turn,
              turn.roomID == roomID,
              let source = turn.source,
              !source.namespace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let bindingID = turn.runtimeBindingID,
              let binding = bindings.first(where: { $0.id == bindingID && $0.roomID == roomID }),
              let completedAt = turn.completedAt else {
            return nil
        }

        let runtimeLabel = displayRuntime(binding.runtimeID)
        let status: AgentRoomReceiptStatus
        let title: String
        switch turn.status {
        case .completed:
            status = .completed
            title = "\(runtimeLabel) completed a turn"
        case .failed:
            status = .failed
            title = "\(runtimeLabel) turn failed"
        case .cancelled:
            status = .cancelled
            title = "\(runtimeLabel) turn cancelled"
        case .unknown, .pending, .running, .waiting:
            return nil
        }

        return AgentRoomReceipt(
            id: turn.id.uuidString,
            title: title,
            detail: "Source-backed canonical turn · \(relativeTime(from: completedAt))",
            status: status
        )
    }

    private func displayRuntime(_ runtimeID: String) -> String {
        switch runtimeID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hermes": "Hermes"
        case "codex": "Codex"
        case "cider-cli": "Cider CLI"
        case let value where value.isEmpty: "Unknown"
        default: runtimeID
        }
    }

    private func relativeTime(from date: Date) -> String {
        let interval = max(0, now().timeIntervalSince(date))
        if interval < 60 { return "Now" }
        if interval < 3_600 { return "\(Int(interval / 60))m" }
        if interval < 86_400 { return "\(Int(interval / 3_600))h" }
        if interval < 172_800 { return "Yesterday" }
        return "\(Int(interval / 86_400))d"
    }
}
