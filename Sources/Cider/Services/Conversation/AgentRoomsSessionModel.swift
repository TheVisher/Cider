import Foundation

/// Owns selected-room UI state while the live model delegates durable turns to Conversation Core.
@MainActor
final class AgentRoomsSessionModel: ObservableObject {
    let liveChat: AgentRoomsLiveChatModel
    let agentAssignments: (any AgentRoomsAgentAssignmentActing)?
    let participants: AgentRoomsParticipantService?
    let messagePresentationStore = AgentRoomsMessagePresentationStore()

    @Published var selectedRoomID: String?
    @Published var composerText = "" {
        didSet {
            guard !isRestoringDraft, let selectedRoomID else { return }
            draftStore.saveDraft(composerText, roomID: selectedRoomID)
        }
    }
    @Published private(set) var speechPresentation: AgentRoomsSpeechInputPresentation
    private(set) var speechDraft: AgentRoomsSpeechDraft?
    private(set) var preferredCanonicalRoomID: String?
    private let selectionStore: (any AgentRoomsSelectionPersisting)?
    private let draftStore: any AgentRoomsDraftPersisting
    private let transcriptionService: any ConversationTranscriptionServicing
    private var isRestoringDraft = false
    private var activeSpeech: ActiveSpeech?
    private var completedSpeechOriginalDraft: String?

    private struct ActiveSpeech {
        let token: UUID
        let roomID: String
        let originalDraft: String
    }

    init(
        liveChat: AgentRoomsLiveChatModel,
        selectionStore: (any AgentRoomsSelectionPersisting)? = nil,
        draftStore: (any AgentRoomsDraftPersisting)? = nil,
        agentAssignments: (any AgentRoomsAgentAssignmentActing)? = nil,
        participants: AgentRoomsParticipantService? = nil,
        transcriptionService: any ConversationTranscriptionServicing = AppleSpeechTranscriptionService()
    ) {
        self.liveChat = liveChat
        self.agentAssignments = agentAssignments
        self.participants = participants
        self.selectionStore = selectionStore
        self.draftStore = draftStore ?? makeAgentRoomsMemoryDraftStore()
        self.transcriptionService = transcriptionService
        self.speechPresentation = AgentRoomsSpeechInputPresentation.initial(
            authorization: transcriptionService.authorization,
            readiness: transcriptionService.readiness
        )
        let restoredSelection = selectionStore?.loadSelectedRoomID()
        self.selectedRoomID = restoredSelection
        self.preferredCanonicalRoomID = restoredSelection
        self.composerText = restoredSelection.flatMap { self.draftStore.loadDraft(roomID: $0) } ?? ""
    }

    convenience init(transport: any HermesBridgeTransport) {
        let repository = ConversationRepository(database: CiderDatabase.shared)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository)
        let participants = AgentRoomsParticipantService(repository: repository)
        self.init(liveChat: AgentRoomsLiveChatModel(
            transport: transport,
            persistence: AgentRoomsConversationPersistence(
                repository: repository,
                defaultAgentProfile: assignments.defaultProfile
            ),
            agentAssignments: assignments,
            participants: participants,
            attachmentService: AgentRoomsAttachmentService(
                database: CiderDatabase.shared,
                didMaterialize: { VaultFileService.shared.scan() }
            )
        ), selectionStore: AgentRoomsSelectionStore.application,
           draftStore: AgentRoomsDraftStore.application,
           agentAssignments: assignments,
           participants: participants)
    }

    func selectRoom(id: String?, persistIfCanonical: Bool) {
        if selectedRoomID != id {
            cancelTranscriptionForRoomChange()
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

    func startTranscription() async {
        guard let selectedRoomID,
              UUID(uuidString: selectedRoomID) != nil,
              selectedRoomID == liveChat.activeRoom?.id
        else {
            speechPresentation = .init(
                state: .unavailable,
                title: "Transcription unavailable",
                detail: "Select an active Cider room before starting microphone transcription.",
                level: 0
            )
            return
        }
        if activeSpeech != nil { cancelTranscription() }

        let context = ActiveSpeech(token: UUID(), roomID: selectedRoomID, originalDraft: composerText)
        activeSpeech = context
        completedSpeechOriginalDraft = nil
        speechDraft = nil

        var authorization = transcriptionService.authorization
        if authorization == .notDetermined {
            speechPresentation = .init(
                state: .requestingPermission,
                title: "Requesting microphone permission",
                detail: "Cider needs microphone and speech recognition access to dictate into this draft.",
                level: 0
            )
            authorization = await transcriptionService.requestAuthorization()
            guard activeSpeech?.token == context.token,
                  self.selectedRoomID == context.roomID
            else { return }
        }

        guard authorization == .authorized else {
            activeSpeech = nil
            speechPresentation = AgentRoomsSpeechInputPresentation.initial(
                authorization: authorization,
                readiness: transcriptionService.readiness
            )
            return
        }
        let readiness = transcriptionService.readiness
        guard readiness == .ready else {
            activeSpeech = nil
            speechPresentation = AgentRoomsSpeechInputPresentation.readinessPresentation(readiness)
            return
        }

        do {
            try transcriptionService.start { [weak self] event in
                self?.receiveTranscription(event, token: context.token, roomID: context.roomID)
            }
            guard activeSpeech?.token == context.token else {
                transcriptionService.cancel()
                return
            }
            speechPresentation = .init(
                state: .listening,
                title: "Listening",
                detail: "Stop to finish, or cancel to restore the original typed draft.",
                level: 0
            )
        } catch {
            restoreOriginalDraft(context)
            activeSpeech = nil
            speechPresentation = .init(
                state: .failed,
                title: "Transcription failed",
                detail: "Cider could not start microphone transcription. The typed draft is unchanged.",
                level: 0
            )
        }
    }

    func stopTranscription() {
        guard activeSpeech != nil, speechPresentation.state == .listening else { return }
        transcriptionService.stop()
        speechPresentation = .init(
            state: .transcribing,
            title: "Finishing transcription",
            detail: "The editable draft will update when the final bounded transcript is ready.",
            level: 0
        )
    }

    func cancelTranscription() {
        guard let context = activeSpeech else { return }
        transcriptionService.cancel()
        restoreOriginalDraft(context)
        activeSpeech = nil
        speechDraft = nil
        completedSpeechOriginalDraft = nil
        speechPresentation = .init(
            state: .cancelled,
            title: "Transcription cancelled",
            detail: "The original typed draft was preserved.",
            level: 0
        )
    }

    func discardSpeechDraft() {
        guard let speechDraft,
              speechDraft.roomID == selectedRoomID,
              let completedSpeechOriginalDraft
        else { return }
        composerText = completedSpeechOriginalDraft
        self.speechDraft = nil
        self.completedSpeechOriginalDraft = nil
        speechPresentation = .init(
            state: .cancelled,
            title: "Speech draft discarded",
            detail: "The original typed draft was restored.",
            level: 0
        )
    }

    var canDiscardSpeechDraft: Bool {
        speechDraft?.isFinal == true
            && speechDraft?.roomID == selectedRoomID
            && completedSpeechOriginalDraft != nil
    }

    private func receiveTranscription(
        _ event: ConversationTranscriptionEvent,
        token: UUID,
        roomID: String
    ) {
        guard let context = activeSpeech,
              context.token == token,
              context.roomID == roomID,
              selectedRoomID == roomID
        else { return }

        switch event {
        case .level(let level):
            guard speechPresentation.state == .listening else { return }
            speechPresentation = .init(
                state: .listening,
                title: "Listening",
                detail: "Stop to finish, or cancel to restore the original typed draft.",
                level: min(1, max(0, level))
            )
        case .partial(let transcript):
            let remainsTranscribing = speechPresentation.state == .transcribing
            let draft = AgentRoomsSpeechDraft(
                roomID: roomID,
                providerID: transcriptionService.providerID,
                transcript: transcript,
                isFinal: false
            )
            speechDraft = draft
            composerText = AgentRoomsSpeechDraft.merge(
                originalDraft: context.originalDraft,
                transcript: draft.transcript
            )
            speechPresentation = .init(
                state: remainsTranscribing ? .transcribing : .listening,
                title: remainsTranscribing ? "Finishing transcription" : "Listening",
                detail: remainsTranscribing
                    ? "Waiting for the final bounded transcript."
                    : "A bounded partial transcript is in this room's draft only.",
                level: remainsTranscribing ? 0 : speechPresentation.level
            )
        case .final(let transcript):
            let draft = AgentRoomsSpeechDraft(
                roomID: roomID,
                providerID: transcriptionService.providerID,
                transcript: transcript,
                isFinal: true
            )
            speechDraft = draft
            composerText = AgentRoomsSpeechDraft.merge(
                originalDraft: context.originalDraft,
                transcript: draft.transcript
            )
            completedSpeechOriginalDraft = context.originalDraft
            activeSpeech = nil
            speechPresentation = .init(
                state: .completed,
                title: "Transcription added to draft",
                detail: "Edit or discard it. Cider sends only when you explicitly choose Send.",
                level: 0
            )
        case .failure:
            transcriptionService.cancel()
            restoreOriginalDraft(context)
            activeSpeech = nil
            speechDraft = nil
            completedSpeechOriginalDraft = nil
            speechPresentation = .init(
                state: .failed,
                title: "Transcription failed",
                detail: "The original typed draft was preserved. Nothing was sent.",
                level: 0
            )
        }
    }

    private func cancelTranscriptionForRoomChange() {
        guard activeSpeech != nil else {
            speechDraft = nil
            completedSpeechOriginalDraft = nil
            speechPresentation = AgentRoomsSpeechInputPresentation.initial(
                authorization: transcriptionService.authorization,
                readiness: transcriptionService.readiness
            )
            return
        }
        cancelTranscription()
    }

    private func restoreOriginalDraft(_ context: ActiveSpeech) {
        if selectedRoomID == context.roomID {
            composerText = context.originalDraft
        } else {
            draftStore.saveDraft(context.originalDraft, roomID: context.roomID)
        }
    }

    private func restoreStoredDraft(for roomID: String?) {
        isRestoringDraft = true
        composerText = roomID.flatMap { draftStore.loadDraft(roomID: $0) } ?? ""
        isRestoringDraft = false
    }
}
