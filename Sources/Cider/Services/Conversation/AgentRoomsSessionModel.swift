import Foundation

/// Owns selected-room UI state while the live model delegates durable turns to Conversation Core.
@MainActor
final class AgentRoomsSessionModel: ObservableObject {
    let liveChat: AgentRoomsLiveChatModel

    @Published var selectedRoomID: String?
    @Published var composerText = ""
    private(set) var preferredCanonicalRoomID: String?
    private let selectionStore: (any AgentRoomsSelectionPersisting)?

    init(
        liveChat: AgentRoomsLiveChatModel,
        selectionStore: (any AgentRoomsSelectionPersisting)? = nil
    ) {
        self.liveChat = liveChat
        self.selectionStore = selectionStore
        let restoredSelection = selectionStore?.loadSelectedRoomID()
        self.selectedRoomID = restoredSelection
        self.preferredCanonicalRoomID = restoredSelection
    }

    convenience init(transport: any HermesBridgeTransport) {
        self.init(liveChat: AgentRoomsLiveChatModel(
            transport: transport,
            persistence: AgentRoomsConversationPersistence()
        ), selectionStore: AgentRoomsSelectionStore.application)
    }

    func selectRoom(id: String?, persistIfCanonical: Bool) {
        selectedRoomID = id
        guard persistIfCanonical, let id, let canonicalID = UUID(uuidString: id) else {
            if id != liveChat.activeRoom?.id { liveChat.deactivateRoom() }
            return
        }
        preferredCanonicalRoomID = id
        selectionStore?.saveSelectedRoomID(id)
        if liveChat.testRoom?.id != id {
            let activated = liveChat.activateCanonicalRoom(id: canonicalID)
            if !activated, liveChat.activeRoom?.id != id {
                liveChat.deactivateRoom()
            }
        }
    }

    @discardableResult
    func restoreDurableTestChat() -> Bool {
        liveChat.restoreDurableTestChat()
    }

    func startTestChat() async {
        await liveChat.startTestChat()
        selectRoom(id: liveChat.testRoom?.id, persistIfCanonical: true)
    }

    func createTestChat() {
        liveChat.createTestChat()
        selectRoom(id: liveChat.testRoom?.id, persistIfCanonical: true)
    }

    @discardableResult
    func restoreRecoveredDraftIfNeeded() -> Bool {
        guard composerText.isEmpty, let recovered = liveChat.takeRecoveredDraft() else { return false }
        composerText = recovered
        return true
    }
}
