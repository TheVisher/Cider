import Foundation

/// A bounded, read-only presentation adapter for the secondary canonical conversation store.
@MainActor
final class AgentRoomsReadService {
    static let fallbackPreview = "No supported messages in this canonical record."
    static let unavailableMessage = "Canonical Rooms data is temporarily unavailable. Try again."

    private static let roomLimit = 20
    private static let messageLimit = 100
    private static let runtimeBindingLimit = 20

    private let loadRooms: (ConversationRoomLifecycle, Int) throws -> [ConversationRoom]
    private let loadRecentMessages: (UUID, Int) throws -> [ConversationMessage]
    private let loadRuntimeBindings: (UUID, Int) throws -> [ConversationRuntimeBinding]
    private let now: () -> Date

    init(repository: ConversationRepository, now: @escaping () -> Date = Date.init) {
        self.loadRooms = repository.rooms(lifecycle:limit:)
        self.loadRecentMessages = repository.recentMessages(roomID:limit:)
        self.loadRuntimeBindings = repository.runtimeBindings(roomID:limit:)
        self.now = now
    }

    /// Internal injection keeps tests temporary and failure paths deterministic without exposing writes.
    init(
        loadRooms: @escaping (ConversationRoomLifecycle, Int) throws -> [ConversationRoom],
        loadRecentMessages: @escaping (UUID, Int) throws -> [ConversationMessage],
        loadRuntimeBindings: @escaping (UUID, Int) throws -> [ConversationRuntimeBinding],
        now: @escaping () -> Date = Date.init
    ) {
        self.loadRooms = loadRooms
        self.loadRecentMessages = loadRecentMessages
        self.loadRuntimeBindings = loadRuntimeBindings
        self.now = now
    }

    func loadWorkspace() -> AgentRoomsWorkspaceState {
        do {
            let canonicalRooms = try loadRooms(.active, Self.roomLimit)
            guard !canonicalRooms.isEmpty else { return .empty }

            let rooms = try canonicalRooms.map { room in
                let messages = try loadRecentMessages(room.id, Self.messageLimit)
                let bindings = try loadRuntimeBindings(room.id, Self.runtimeBindingLimit)
                return mapRoom(room, messages: messages, bindings: bindings)
            }
            guard let selectedRoomID = rooms.first?.id else { return .empty }
            return .loaded(rooms: rooms, selectedRoomID: selectedRoomID)
        } catch {
            return .failed(message: Self.unavailableMessage)
        }
    }

    private func mapRoom(
        _ room: ConversationRoom,
        messages: [ConversationMessage],
        bindings: [ConversationRuntimeBinding]
    ) -> AgentRoom {
        let binding = bindings.first(where: { $0.state == .active }) ?? bindings.first
        let runtimeLabel = binding.map { displayRuntime($0.runtimeID) } ?? "Unknown"
        let supportedMessages = messages.compactMap { message -> AgentRoomMessage? in
            switch message.role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "user":
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .human,
                    author: "You",
                    body: message.contentText
                )
            case "assistant":
                return AgentRoomMessage(
                    id: message.id.uuidString,
                    role: .agent,
                    author: runtimeLabel,
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
                receipt: nil,
                futureArtifact: nil
            )
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
