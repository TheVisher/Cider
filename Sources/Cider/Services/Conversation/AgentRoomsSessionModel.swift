import Foundation

/// Owns the explicit Test Chat UI state and delegates durable completed turns to Conversation Core.
@MainActor
final class AgentRoomsSessionModel: ObservableObject {
    let liveChat: AgentRoomsLiveChatModel

    @Published var selectedRoomID: String?
    @Published var composerText = ""

    init(liveChat: AgentRoomsLiveChatModel) {
        self.liveChat = liveChat
    }

    convenience init(transport: any HermesBridgeTransport) {
        self.init(liveChat: AgentRoomsLiveChatModel(
            transport: transport,
            persistence: AgentRoomsTestChatPersistence()
        ))
    }

    @discardableResult
    func restoreDurableTestChat() -> Bool {
        liveChat.restoreDurableTestChat()
    }

    func startTestChat() async {
        await liveChat.startTestChat()
        selectedRoomID = liveChat.testRoom?.id
    }

    func createTestChat() {
        liveChat.createTestChat()
        selectedRoomID = liveChat.testRoom?.id
    }

    @discardableResult
    func restoreRecoveredDraftIfNeeded() -> Bool {
        guard composerText.isEmpty, let recovered = liveChat.takeRecoveredDraft() else { return false }
        composerText = recovered
        return true
    }
}
