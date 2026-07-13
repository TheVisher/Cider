import Foundation

/// Owns the explicit Test Chat UI state and delegates durable completed turns to Conversation Core.
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
            persistence: AgentRoomsTestChatPersistence()
        ), selectionStore: AgentRoomsSelectionStore.application)
    }

    func selectRoom(id: String?, persistIfCanonical: Bool) {
        selectedRoomID = id
        guard persistIfCanonical, let id, UUID(uuidString: id) != nil else { return }
        preferredCanonicalRoomID = id
        selectionStore?.saveSelectedRoomID(id)
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
