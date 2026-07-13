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
