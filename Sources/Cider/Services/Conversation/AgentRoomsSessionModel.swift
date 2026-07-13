import Foundation

/// Owns selected-room UI state while the live model delegates durable turns to Conversation Core.
@MainActor
final class AgentRoomsSessionModel: ObservableObject {
    let liveChat: AgentRoomsLiveChatModel
    let agentAssignments: (any AgentRoomsAgentAssignmentActing)?
    let messagePresentationStore = AgentRoomsMessagePresentationStore()

    @Published var selectedRoomID: String?
    @Published var composerText = "" {
        didSet {
            guard !isRestoringDraft, let selectedRoomID else { return }
            draftStore.saveDraft(composerText, roomID: selectedRoomID)
        }
    }
    private(set) var preferredCanonicalRoomID: String?
    private let selectionStore: (any AgentRoomsSelectionPersisting)?
    private let draftStore: any AgentRoomsDraftPersisting
    private var isRestoringDraft = false

    init(
        liveChat: AgentRoomsLiveChatModel,
        selectionStore: (any AgentRoomsSelectionPersisting)? = nil,
        draftStore: (any AgentRoomsDraftPersisting)? = nil,
        agentAssignments: (any AgentRoomsAgentAssignmentActing)? = nil
    ) {
        self.liveChat = liveChat
        self.agentAssignments = agentAssignments
        self.selectionStore = selectionStore
        self.draftStore = draftStore ?? makeAgentRoomsMemoryDraftStore()
        let restoredSelection = selectionStore?.loadSelectedRoomID()
        self.selectedRoomID = restoredSelection
        self.preferredCanonicalRoomID = restoredSelection
        self.composerText = restoredSelection.flatMap { self.draftStore.loadDraft(roomID: $0) } ?? ""
    }

    convenience init(transport: any HermesBridgeTransport) {
        let repository = ConversationRepository(database: CiderDatabase.shared)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository)
        self.init(liveChat: AgentRoomsLiveChatModel(
            transport: transport,
            persistence: AgentRoomsConversationPersistence(
                repository: repository,
                defaultAgentProfile: assignments.defaultProfile
            ),
            agentAssignments: assignments
        ), selectionStore: AgentRoomsSelectionStore.application,
           draftStore: AgentRoomsDraftStore.application,
           agentAssignments: assignments)
    }

    func selectRoom(id: String?, persistIfCanonical: Bool) {
        if selectedRoomID != id {
            if let selectedRoomID { draftStore.saveDraft(composerText, roomID: selectedRoomID) }
            selectedRoomID = id
            restoreStoredDraft(for: id)
        }
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
        guard let recovered = liveChat.takeRecoveredDraftRecovery() else { return false }
        draftStore.saveDraft(recovered.text, roomID: recovered.roomID)
        guard selectedRoomID == recovered.roomID, composerText.isEmpty else { return false }
        restoreStoredDraft(for: recovered.roomID)
        return composerText == recovered.text
    }

    private func restoreStoredDraft(for roomID: String?) {
        isRestoringDraft = true
        composerText = roomID.flatMap { draftStore.loadDraft(roomID: $0) } ?? ""
        isRestoringDraft = false
    }
}
