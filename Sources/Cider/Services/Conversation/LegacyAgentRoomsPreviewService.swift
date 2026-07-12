import Foundation

/// Bounded presentation adapter over the strict, read-only legacy preview contract.
/// Production Rooms may use it only behind explicit canonical-empty arbitration.
@MainActor
final class LegacyAgentRoomsPreviewService {
    static let blockedMessage = "Legacy preview unavailable because provenance validation did not pass."
    static let unavailableMessage = "Legacy Rooms preview is temporarily unavailable. Try again."
    static let fallbackPreview = "No supported user or assistant messages in this legacy preview."

    private static let roomLimit = 20
    private static let messageLimit = 100

    private let loadPreview: () throws -> LegacyConversationImportPreview
    private let now: () -> Date

    init(
        loadPreview: @escaping () throws -> LegacyConversationImportPreview,
        now: @escaping () -> Date = Date.init
    ) {
        self.loadPreview = loadPreview
        self.now = now
    }

    /// Strict path-based construction never creates or writes legacy storage.
    init(
        registryDirectory: URL,
        conversationDirectory: URL,
        parityReader: any ConversationCoreParityReading,
        limits: LegacyConversationImportPreviewService.Limits = .init(),
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        let strictService = LegacyConversationImportPreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: parityReader,
            limits: limits,
            fileManager: fileManager
        )
        self.loadPreview = strictService.preview
        self.now = now
    }

    func loadWorkspace() -> AgentRoomsWorkspaceState {
        do {
            let preview = try loadPreview()
            guard preview.readOnly, !preview.changed else { return blocked() }
            guard preview.counts.blockingDiagnostics == 0,
                  !preview.diagnosticSamples.contains(where: { $0.severity == .blocker }) else {
                return blocked()
            }

            switch preview.state {
            case .empty:
                return .empty(authority: .legacyAuthoritativePreview)
            case .blocked:
                return blocked()
            case .ready:
                guard planIsStrictlyValid(preview) else { return blocked() }
                return mapReadyPlan(preview.plan)
            }
        } catch {
            return .failed(
                authority: .legacyAuthoritativePreview,
                message: Self.unavailableMessage
            )
        }
    }

    private func mapReadyPlan(_ plan: LegacyConversationImportPlan) -> AgentRoomsWorkspaceState {
        let activeRooms = plan.rooms
            .filter { $0.lifecycleState == .active }
            .sorted(by: roomSort)
            .prefix(Self.roomLimit)
        guard !activeRooms.isEmpty else {
            return .empty(authority: .legacyAuthoritativePreview)
        }

        let rooms = activeRooms.map { room in
            mapRoom(
                room,
                bindings: plan.bindings.filter { $0.roomID == room.id },
                messages: plan.messages.filter { $0.roomID == room.id }
            )
        }
        return .loaded(
            authority: .legacyAuthoritativePreview,
            rooms: rooms,
            selectedRoomID: rooms[0].id
        )
    }

    private func mapRoom(
        _ room: LegacyConversationRoomPlanRecord,
        bindings: [LegacyConversationBindingPlanRecord],
        messages: [LegacyConversationMessagePlanRecord]
    ) -> AgentRoom {
        let newestBindings = bindings.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let binding = newestBindings.first(where: { $0.state == .active }) ?? newestBindings.first
        let runtimeLabel = displayRuntime(binding?.runtimeID)
        let newestMessages = messages
            .sorted(by: messageDescendingSort)
            .prefix(Self.messageLimit)
            .sorted(by: messageAscendingSort)
        let supportedMessages = newestMessages.compactMap { message -> AgentRoomMessage? in
            switch message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "user":
                return .init(id: message.id.uuidString, role: .human, author: "You", body: message.contentText)
            case "assistant":
                return .init(id: message.id.uuidString, role: .agent, author: runtimeLabel, body: message.contentText)
            default:
                return nil
            }
        }
        let preview = supportedMessages.reversed().lazy
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? Self.fallbackPreview
        let title = room.title.trimmingCharacters(in: .whitespacesAndNewlines)

        return AgentRoom(
            id: room.id.uuidString,
            title: title.isEmpty ? "Untitled Room" : title,
            preview: preview,
            updatedAt: room.updatedAt,
            relativeTime: relativeTime(from: room.updatedAt),
            transcript: .init(
                runtimeLabel: runtimeLabel,
                messages: supportedMessages,
                link: nil,
                receipt: nil,
                futureArtifact: nil
            )
        )
    }

    private func planIsStrictlyValid(_ preview: LegacyConversationImportPreview) -> Bool {
        let plan = preview.plan
        guard preview.counts.plannedRooms == plan.rooms.count,
              preview.counts.plannedBindings == plan.bindings.count,
              preview.counts.plannedTurns == plan.turns.count,
              preview.counts.plannedMessages == plan.messages.count,
              preview.counts.conflicts == 0,
              preview.counts.attachmentBearingMessages == 0 else {
            return false
        }
        let dispositions = plan.rooms.map(\.disposition) + plan.bindings.map(\.disposition) +
            plan.turns.map(\.disposition) + plan.messages.map(\.disposition)
        guard !dispositions.contains(.conflict),
              unique(plan.rooms.map(\.id)),
              unique(plan.rooms.map(\.stableKey)),
              unique(plan.bindings.map(\.id)),
              unique(plan.messages.map(\.id)),
              unique(plan.turns.map(\.id)),
              unique(plan.messages.compactMap(\.source)) else {
            return false
        }

        let roomIDs = Set(plan.rooms.map(\.id))
        let bindingsByID = Dictionary(uniqueKeysWithValues: plan.bindings.map { ($0.id, $0) })
        let turnsByID = Dictionary(uniqueKeysWithValues: plan.turns.map { ($0.id, $0) })
        let messagesByID = Dictionary(uniqueKeysWithValues: plan.messages.map { ($0.id, $0) })

        for room in plan.rooms where room.lifecycleState == .active {
            guard plan.bindings.contains(where: { $0.roomID == room.id }) else { return false }
        }
        for binding in plan.bindings {
            guard roomIDs.contains(binding.roomID) else { return false }
            if let parentID = binding.parentBindingID {
                guard let parent = bindingsByID[parentID], parent.roomID == binding.roomID else { return false }
            }
            guard !containsCycle(start: binding.id, next: { bindingsByID[$0]?.parentBindingID }) else { return false }
        }
        for turn in plan.turns {
            guard roomIDs.contains(turn.roomID) else { return false }
            if let bindingID = turn.runtimeBindingID {
                guard bindingsByID[bindingID]?.roomID == turn.roomID else { return false }
            }
        }
        for message in plan.messages {
            guard roomIDs.contains(message.roomID),
                  message.metadata["attachmentCount"] == nil || message.metadata["attachmentCount"] == "0" else {
                return false
            }
            if let bindingID = message.runtimeBindingID {
                guard bindingsByID[bindingID]?.roomID == message.roomID else { return false }
            }
            if let turnID = message.turnID {
                guard turnsByID[turnID]?.roomID == message.roomID else { return false }
            }
            if let parentID = message.parentMessageID {
                guard messagesByID[parentID]?.roomID == message.roomID else { return false }
            }
            guard !containsCycle(start: message.id, next: { messagesByID[$0]?.parentMessageID }) else { return false }
        }
        return true
    }

    private func unique<T: Hashable>(_ values: [T]) -> Bool {
        Set(values).count == values.count
    }

    private func containsCycle<T: Hashable>(start: T, next: (T) -> T?) -> Bool {
        var visited = Set<T>()
        var cursor: T? = start
        while let value = cursor {
            guard visited.insert(value).inserted else { return true }
            cursor = next(value)
        }
        return false
    }

    private func blocked() -> AgentRoomsWorkspaceState {
        .blocked(authority: .legacyAuthoritativePreview, message: Self.blockedMessage)
    }

    private func roomSort(
        _ lhs: LegacyConversationRoomPlanRecord,
        _ rhs: LegacyConversationRoomPlanRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func messageAscendingSort(
        _ lhs: LegacyConversationMessagePlanRecord,
        _ rhs: LegacyConversationMessagePlanRecord
    ) -> Bool {
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func messageDescendingSort(
        _ lhs: LegacyConversationMessagePlanRecord,
        _ rhs: LegacyConversationMessagePlanRecord
    ) -> Bool {
        if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func displayRuntime(_ runtimeID: String?) -> String {
        switch runtimeID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hermes": "Hermes"
        case "codex": "Codex"
        case "cider-cli": "Cider CLI"
        default: "Legacy runtime"
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

/// Selects one authority without merging; only explicit canonical-incomplete emptiness consults legacy.
@MainActor
final class AgentRoomsWorkspaceLoader {
    private let loadCanonical: () -> AgentRoomsWorkspaceState
    private let loadLegacy: () -> AgentRoomsWorkspaceState

    init(
        loadCanonical: @escaping () -> AgentRoomsWorkspaceState,
        loadLegacy: @escaping () -> AgentRoomsWorkspaceState
    ) {
        self.loadCanonical = loadCanonical
        self.loadLegacy = loadLegacy
    }

    func loadWorkspace() -> AgentRoomsWorkspaceState {
        let canonical = loadCanonical()
        guard case .empty(authority: .canonicalIncomplete) = canonical else { return canonical }
        return loadLegacy()
    }
}
