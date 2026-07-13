import Foundation

@MainActor
protocol AgentRoomsSelectionPersisting: AnyObject {
    func loadSelectedRoomID() -> String?
    func saveSelectedRoomID(_ roomID: String)
}

/// Client-local navigation preference. Canonical room identity remains in SQLite.
@MainActor
final class AgentRoomsSelectionStore: AgentRoomsSelectionPersisting {
    static let application = AgentRoomsSelectionStore()

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "cider.agentRooms.selectedCanonicalRoomID"
    ) {
        self.defaults = defaults
        self.key = key
    }

    func loadSelectedRoomID() -> String? {
        guard let value = defaults.string(forKey: key), UUID(uuidString: value) != nil else { return nil }
        return value
    }

    func saveSelectedRoomID(_ roomID: String) {
        guard UUID(uuidString: roomID) != nil else { return }
        defaults.set(roomID, forKey: key)
    }
}

@MainActor
protocol AgentRoomsDraftPersisting: AnyObject {
    func loadDraft(roomID: String) -> String?
    func saveDraft(_ text: String, roomID: String)
}

/// Client-local unsent composer recovery keyed by canonical Cider room UUID.
/// Drafts are never projected into Conversation Core or transport history.
@MainActor
final class AgentRoomsDraftStore: AgentRoomsDraftPersisting {
    static let application = AgentRoomsDraftStore()

    private static let maximumDraftCount = 64
    private static let maximumDraftLength = AgentRoomsLiveChatModel.maximumStreamingMessageLength
    private let defaults: UserDefaults
    private let key: String
    private let orderKey: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "cider.agentRooms.draftsByCanonicalRoomID"
    ) {
        self.defaults = defaults
        self.key = key
        self.orderKey = "\(key).order"
    }

    func loadDraft(roomID: String) -> String? {
        guard UUID(uuidString: roomID) != nil,
              let draft = defaults.dictionary(forKey: key)?[roomID] as? String,
              !draft.isEmpty,
              draft.count <= Self.maximumDraftLength
        else { return nil }
        return draft
    }

    func saveDraft(_ text: String, roomID: String) {
        guard UUID(uuidString: roomID) != nil else { return }
        var drafts = defaults.dictionary(forKey: key) as? [String: String] ?? [:]
        drafts = drafts.filter { UUID(uuidString: $0.key) != nil && $0.value.count <= Self.maximumDraftLength }
        var order = defaults.stringArray(forKey: orderKey) ?? []
        order = order.filter { drafts[$0] != nil && $0 != roomID }
        if text.isEmpty {
            drafts.removeValue(forKey: roomID)
        } else {
            drafts[roomID] = String(text.prefix(Self.maximumDraftLength))
            order.append(roomID)
        }
        while order.count > Self.maximumDraftCount {
            drafts.removeValue(forKey: order.removeFirst())
        }
        defaults.set(drafts, forKey: key)
        defaults.set(order, forKey: orderKey)
    }
}

@MainActor
private final class AgentRoomsMemoryDraftStore: AgentRoomsDraftPersisting {
    private var drafts: [String: String] = [:]

    func loadDraft(roomID: String) -> String? { drafts[roomID] }

    func saveDraft(_ text: String, roomID: String) {
        guard UUID(uuidString: roomID) != nil else { return }
        if text.isEmpty { drafts.removeValue(forKey: roomID) }
        else { drafts[roomID] = text }
    }
}

@MainActor
func makeAgentRoomsMemoryDraftStore() -> any AgentRoomsDraftPersisting {
    AgentRoomsMemoryDraftStore()
}
