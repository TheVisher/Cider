import Foundation

enum AgentRoomsLiveTransportState: Equatable, Sendable {
    case unchecked
    case checking
    case ready
    case blocked
}

enum AgentRoomsLiveTurnState: String, Equatable, Sendable {
    case idle, sending, streaming, cancelling, failed, completed
}

struct AgentRoomsLiveActivity: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable { case reasoning, toolStarted, toolCompleted }
    let id: UUID
    let kind: Kind
    let detail: String
}

struct AgentRoomsTranscriptFollowPolicy: Equatable, Sendable {
    static let nearBottomDistance: CGFloat = 72
    private(set) var shouldAutoScrollForNewContent = true

    @discardableResult
    mutating func shouldFollow(distanceFromBottom: CGFloat) -> Bool {
        shouldAutoScrollForNewContent = distanceFromBottom <= Self.nearBottomDistance
        return shouldAutoScrollForNewContent
    }
}

@MainActor
final class AgentRoomsLiveChatModel: ObservableObject {
    static let roomTitle = "Cider Test Chat"
    static let maximumMessageLength = 4_000
    static let maximumStreamingMessageLength = 32_000
    static let maximumEventDetailLength = 240
    static let maximumLiveActivityCount = 24
    static let unavailableMessage = "Hermes live transport is not ready. Open Live Chat to check the connection."
    static let failedMessage = "Hermes could not complete this message."
    static let acceptedInterruptionMessage = "Hermes accepted the message, but the response was interrupted. It cannot be retried safely."

    @Published private(set) var testRoom: AgentRoom?
    @Published private(set) var transportState: AgentRoomsLiveTransportState = .unchecked
    @Published private(set) var composerMessage: String?
    @Published private(set) var activeRunCanBeCancelled = false
    @Published private(set) var turnState: AgentRoomsLiveTurnState = .idle
    @Published private(set) var liveActivity: [AgentRoomsLiveActivity] = []

    private let transport: any HermesBridgeTransport
    private let turnCoordinator: HermesTurnCoordinator
    private let makeID: @MainActor () -> UUID
    private let now: @MainActor () -> Date

    private var roomID: UUID?
    private var conversationState: HermesConversationState?
    private var transportMessages: [AIAssistantMessage] = []
    private var roomMessages: [AgentRoomMessage] = []
    private var receipt: AgentRoomReceipt?
    private var activeAttemptID: UUID?
    private var activeClientMessageID: String?
    private var activeRunID: String?
    private var eventIntegrityFailed = false
    private var completedAssistantSourceIDs = Set<String>()
    private var streamingAssistantID: String?
    private var recoveredDraft: String?

    init(
        transport: any HermesBridgeTransport,
        turnCoordinator: HermesTurnCoordinator = .shared,
        makeID: @escaping @MainActor () -> UUID = UUID.init,
        now: @escaping @MainActor () -> Date = Date.init
    ) {
        self.transport = transport
        self.turnCoordinator = turnCoordinator
        self.makeID = makeID
        self.now = now
    }

    func startTestChat() async {
        createTestChat()
        await refreshTransportReadiness()
    }

    func createTestChat() {
        if roomID == nil {
            let id = makeID()
            roomID = id
            conversationState = HermesConversationState(
                conversationID: id,
                activeRuntimeSessionID: "",
                runtimeSessionLineage: [],
                title: Self.roomTitle,
                source: "cider-rooms-live-continuation"
            )
            rebuildRoom()
        }
    }

    func refreshTransportReadiness() async {
        guard roomID != nil, activeAttemptID == nil else { return }
        transportState = .checking
        switch await transport.availability() {
        case .apiRuns:
            transportState = .ready
            composerMessage = nil
        case .cliFallback, .unavailable:
            transportState = .blocked
            composerMessage = Self.unavailableMessage
        }
    }

    func isComposerEnabled(selectedRoomID: String?) -> Bool {
        guard let roomID else { return false }
        return selectedRoomID == roomID.uuidString && transportState == .ready && activeAttemptID == nil
    }

    func send(_ text: String, selectedRoomID: String?) async {
        guard isComposerEnabled(selectedRoomID: selectedRoomID) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            composerMessage = "Type a message before sending."
            return
        }
        guard trimmed.count <= Self.maximumMessageLength else {
            composerMessage = "Messages can be up to \(Self.maximumMessageLength) characters."
            return
        }

        let clientID = "cider-room-client:\(makeID().uuidString)"
        roomMessages.append(.init(
            id: clientID,
            role: .human,
            author: "You",
            body: trimmed,
            deliveryState: .pending
        ))
        rebuildRoom()
        await performSend(text: trimmed, clientID: clientID)
    }

    func takeRecoveredDraft() -> String? {
        defer { recoveredDraft = nil }
        return recoveredDraft
    }

    func retry(clientMessageID: String, selectedRoomID: String?) async {
        guard isComposerEnabled(selectedRoomID: selectedRoomID),
              let index = roomMessages.firstIndex(where: {
                  $0.id == clientMessageID && $0.role == .human && $0.deliveryState == .failed && $0.canRetry
              })
        else { return }
        let text = roomMessages[index].body
        recoveredDraft = nil
        roomMessages[index].deliveryState = .pending
        roomMessages[index].canRetry = false
        composerMessage = nil
        rebuildRoom()
        await performSend(text: text, clientID: clientMessageID)
    }

    func cancelActiveSend() async {
        guard let attemptID = activeAttemptID else { return }
        turnState = .cancelling
        if let runID = activeRunID {
            try? await transport.stop(runID: runID)
        }
        guard activeAttemptID == attemptID else { return }
        if activeRunID == nil,
           let activeClientMessageID,
           let message = roomMessages.first(where: { $0.id == activeClientMessageID }) {
            recoveredDraft = message.body
        }
        failActiveMessage(message: "Hermes response cancelled.", canRetry: activeRunID == nil)
        turnState = .failed
        receipt = .init(
            id: "cider-room-receipt:\(makeID().uuidString)",
            title: "Hermes turn cancelled",
            detail: "Runs API · Live continuation",
            status: .cancelled,
            continuity: .liveContinuation,
            sourceBackedTransport: activeRunID != nil
        )
        clearActiveAttempt()
        rebuildRoom()
    }

    private func performSend(text: String, clientID: String) async {
        guard let state = conversationState, activeAttemptID == nil else { return }
        let attemptID = makeID()
        activeAttemptID = attemptID
        activeClientMessageID = clientID
        activeRunID = nil
        eventIntegrityFailed = false
        composerMessage = nil
        receipt = nil
        turnState = .sending
        liveActivity = []
        streamingAssistantID = nil

        do {
            let result = try await coordinatedSend(text: text, state: state, attemptID: attemptID)
            guard activeAttemptID == attemptID else { return }
            try applyCompletion(result.completion, expectedText: text, clientID: clientID)
            turnState = .completed
            clearActiveAttempt()
            rebuildRoom()
        } catch is CancellationError {
            guard activeAttemptID == attemptID else { return }
            failActiveMessage(message: "Hermes response was interrupted.", canRetry: activeRunID == nil)
            recoveredDraft = activeRunID == nil ? text : nil
            turnState = .failed
            receipt = .init(
                id: "cider-room-receipt:\(makeID().uuidString)",
                title: "Hermes turn interrupted",
                detail: "Runs API · Live continuation",
                status: .cancelled,
                continuity: .liveContinuation,
                sourceBackedTransport: activeRunID != nil
            )
            clearActiveAttempt()
            rebuildRoom()
        } catch {
            guard activeAttemptID == attemptID else { return }
            let accepted = activeRunID != nil
            failActiveMessage(
                message: accepted ? Self.acceptedInterruptionMessage : Self.failedMessage,
                canRetry: !accepted
            )
            recoveredDraft = accepted ? nil : text
            turnState = .failed
            receipt = .init(
                id: "cider-room-receipt:\(makeID().uuidString)",
                title: accepted ? "Hermes response interrupted" : "Hermes send failed",
                detail: "Runs API · Live continuation",
                status: .failed,
                continuity: .liveContinuation,
                sourceBackedTransport: accepted
            )
            clearActiveAttempt()
            rebuildRoom()
        }
    }

    private func coordinatedSend(
        text: String,
        state: HermesConversationState,
        attemptID: UUID
    ) async throws -> HermesBridgeSendResult {
        let turnID = try await turnCoordinator.beginTurn()
        do {
            let result = try await transport.send(
                text: text,
                state: state,
                existingMessages: transportMessages,
                onEvent: { [weak self] event in
                    await self?.receive(event, attemptID: attemptID)
                }
            )
            await turnCoordinator.endTurn(turnID)
            return result
        } catch {
            await turnCoordinator.endTurn(turnID)
            throw error
        }
    }

    private func receive(_ event: HermesRunEvent, attemptID: UUID) {
        guard activeAttemptID == attemptID else { return }
        switch event {
        case .runStarted(let runID):
            guard nonempty(runID) != nil else {
                eventIntegrityFailed = true
                return
            }
            if let activeRunID, activeRunID != runID {
                eventIntegrityFailed = true
            } else {
                activeRunID = runID
                activeRunCanBeCancelled = true
            }
        case .messageDelta(let delta):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendStreamingDelta(delta)
        case .toolStarted(let name, let preview):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendActivity(.toolStarted, detail: preview ?? name)
        case .toolCompleted(let name, let isError):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendActivity(.toolCompleted, detail: "\(name ?? "Tool") \(isError ? "failed" : "completed")")
        case .reasoningAvailable(let detail):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            appendActivity(.reasoning, detail: detail)
        case .failed, .cancelled:
            eventIntegrityFailed = true
        case .completed(let output):
            guard activeRunID != nil else { eventIntegrityFailed = true; return }
            reconcileStreamingOutput(output)
        case .approvalRequested:
            break
        }
    }

    private func appendStreamingDelta(_ raw: String) {
        let delta = sanitized(raw, limit: Self.maximumStreamingMessageLength, trimmingWhitespace: false)
        guard !delta.isEmpty else { return }
        turnState = .streaming
        let id = streamingAssistantID ?? "cider-room-stream:\(activeAttemptID?.uuidString ?? makeID().uuidString)"
        streamingAssistantID = id
        if let index = roomMessages.firstIndex(where: { $0.id == id }) {
            let remaining = max(0, Self.maximumStreamingMessageLength - roomMessages[index].body.count)
            guard remaining > 0 else { return }
            roomMessages[index].body += String(delta.prefix(remaining))
        } else {
            roomMessages.append(.init(id: id, role: .agent, author: "Hermes", body: String(delta.prefix(Self.maximumStreamingMessageLength))))
        }
        rebuildRoom()
    }

    private func reconcileStreamingOutput(_ raw: String) {
        let output = sanitized(raw, limit: Self.maximumStreamingMessageLength)
        guard !output.isEmpty else { return }
        turnState = .streaming
        let id = streamingAssistantID ?? "cider-room-stream:\(activeAttemptID?.uuidString ?? makeID().uuidString)"
        streamingAssistantID = id
        if let index = roomMessages.firstIndex(where: { $0.id == id }) {
            if output.hasPrefix(roomMessages[index].body) { roomMessages[index].body = output }
        } else {
            roomMessages.append(.init(id: id, role: .agent, author: "Hermes", body: output))
        }
        rebuildRoom()
    }

    private func appendActivity(_ kind: AgentRoomsLiveActivity.Kind, detail raw: String?) {
        let detail = sanitized(raw ?? "", limit: Self.maximumEventDetailLength)
        guard !detail.isEmpty else { return }
        turnState = .streaming
        liveActivity.append(.init(id: makeID(), kind: kind, detail: detail))
        if liveActivity.count > Self.maximumLiveActivityCount {
            liveActivity.removeFirst(liveActivity.count - Self.maximumLiveActivityCount)
        }
        rebuildRoom()
    }

    private func sanitized(_ raw: String, limit: Int, trimmingWhitespace: Bool = true) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        let clean = String(String.UnicodeScalarView(scalars))
        let normalized = trimmingWhitespace ? clean.trimmingCharacters(in: .whitespacesAndNewlines) : clean
        return normalized.prefix(limit).description
    }

    private func applyCompletion(
        _ completion: HermesRunCompletionEnvelope,
        expectedText: String,
        clientID: String
    ) throws {
        guard !eventIntegrityFailed,
              completion.provenance == .hermesRunsAPI,
              completion.terminalStatus == .completed,
              completion.finalSessionSynchronizationComplete,
              completion.observedFacts.runIdentityConsistent,
              nonempty(completion.modelIdentity) != nil,
              let runID = nonempty(completion.runID),
              activeRunID == nil || activeRunID == runID,
              completion.terminalSourceEvidence.reportedTerminalRunID == runID,
              completion.finalMessages.count >= 2
        else { throw AgentRoomsLiveChatError.invalidTerminalReceipt }

        let user = completion.finalMessages[completion.finalMessages.count - 2]
        let assistant = completion.finalMessages[completion.finalMessages.count - 1]
        let expectedUserSourceID = "hermes-run:\(runID):user"
        let expectedAssistantSourceID = "hermes-run:\(runID):assistant"
        guard user.role == .user,
              assistant.role == .assistant,
              user.content == expectedText,
              nonempty(assistant.content) != nil,
              user.sourceID == expectedUserSourceID,
              assistant.sourceID == expectedAssistantSourceID,
              completion.terminalSourceEvidence.userSourceID == expectedUserSourceID,
              completion.terminalSourceEvidence.assistantSourceID == expectedAssistantSourceID,
              let userSession = nonempty(user.sourceSessionID),
              userSession == nonempty(assistant.sourceSessionID),
              completion.terminalSourceEvidence.userSourceSessionID == userSession,
              completion.terminalSourceEvidence.assistantSourceSessionID == userSession,
              user.attachments.isEmpty,
              assistant.attachments.isEmpty,
              completion.finalState.runtimeID == "hermes",
              completion.finalState.activeRuntimeSessionID == userSession,
              completion.finalState.runtimeSessionLineage.last == userSession,
              completion.finalState.lastSyncedMessageID == expectedAssistantSourceID,
              completion.finalState.lastSyncedTimestamp == assistant.timestamp,
              completion.finalState.lastImportedRuntimeSessionID == userSession
        else { throw AgentRoomsLiveChatError.invalidTerminalReceipt }

        if let index = roomMessages.firstIndex(where: { $0.id == clientID }) {
            roomMessages[index].deliveryState = .sent
            roomMessages[index].canRetry = false
        }
        if completedAssistantSourceIDs.insert(expectedAssistantSourceID).inserted {
            if let streamingAssistantID,
               let index = roomMessages.firstIndex(where: { $0.id == streamingAssistantID }) {
                roomMessages[index] = .init(id: expectedAssistantSourceID, role: .agent, author: "Hermes", body: assistant.content)
            } else {
                roomMessages.append(.init(id: expectedAssistantSourceID, role: .agent, author: "Hermes", body: assistant.content))
            }
        }
        transportMessages = completion.finalMessages
        conversationState = completion.finalState
        receipt = .init(
            id: "cider-room-receipt:\(runID)",
            title: "Hermes completed a live turn",
            detail: "Runs API · Source-backed terminal · Live continuation",
            status: .completed,
            continuity: .liveContinuation,
            sourceBackedTransport: true
        )
    }

    private func failActiveMessage(message: String, canRetry: Bool) {
        if let activeClientMessageID,
           let index = roomMessages.firstIndex(where: { $0.id == activeClientMessageID }) {
            roomMessages[index].deliveryState = .failed
            roomMessages[index].canRetry = canRetry
        }
        composerMessage = message
        if let streamingAssistantID {
            roomMessages.removeAll { $0.id == streamingAssistantID }
        }
    }

    private func clearActiveAttempt() {
        activeAttemptID = nil
        activeClientMessageID = nil
        activeRunID = nil
        activeRunCanBeCancelled = false
        eventIntegrityFailed = false
        streamingAssistantID = nil
    }

    private func rebuildRoom() {
        guard let roomID else {
            testRoom = nil
            return
        }
        let preview = roomMessages.last?.body ?? "New live conversation with Hermes"
        testRoom = AgentRoom(
            id: roomID.uuidString,
            title: Self.roomTitle,
            preview: preview,
            updatedAt: now(),
            relativeTime: "Now",
            transcript: .init(
                runtimeLabel: "Hermes",
                messages: roomMessages,
                link: nil,
                receipt: receipt,
                futureArtifact: nil
            ),
            continuity: .liveContinuation
        )
    }

    private func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

private enum AgentRoomsLiveChatError: Error {
    case invalidTerminalReceipt
}
