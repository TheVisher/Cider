import Foundation

/// Owns the explicit Test Chat for one Cider app-process lifetime.
/// This model is intentionally never encoded or written to the vault.
@MainActor
final class AgentRoomsSessionModel: ObservableObject {
    let liveChat: AgentRoomsLiveChatModel

    @Published var selectedRoomID: String?
    @Published var composerText = ""

    init(liveChat: AgentRoomsLiveChatModel) {
        self.liveChat = liveChat
    }

    convenience init(transport: any HermesBridgeTransport) {
        self.init(liveChat: AgentRoomsLiveChatModel(transport: transport))
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
