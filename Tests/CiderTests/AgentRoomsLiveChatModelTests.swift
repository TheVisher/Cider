import Foundation
import Testing
@testable import Cider

@MainActor
struct AgentRoomsLiveChatModelTests {
    @Test("test room is created only by explicit action and is a live continuation")
    func explicitCreation() async {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [])
        let model = makeModel(transport)

        #expect(model.testRoom == nil)
        #expect(!model.isComposerEnabled(selectedRoomID: nil))

        await model.startTestChat()

        #expect(model.testRoom?.title == "Cider Test Chat")
        #expect(model.testRoom?.continuity == .liveContinuation)
        #expect(model.testRoom?.transcript.messages.isEmpty == true)
        #expect(model.isComposerEnabled(selectedRoomID: model.testRoom?.id))
        #expect(AgentRoomContinuity.historicalReplay != AgentRoomContinuity.liveContinuation)
    }

    @Test("only a selected test room with Runs transport enables its composer")
    func composerArbitration() async {
        let ready = makeModel(RoomsScriptedTransport(availability: .apiRuns, scripts: []))
        await ready.startTestChat()
        #expect(ready.isComposerEnabled(selectedRoomID: ready.testRoom?.id))
        #expect(!ready.isComposerEnabled(selectedRoomID: "ambiguous-legacy-room"))

        let fallback = makeModel(RoomsScriptedTransport(availability: .cliFallback, scripts: []))
        await fallback.startTestChat()
        #expect(fallback.transportState == .blocked)
        #expect(!fallback.isComposerEnabled(selectedRoomID: fallback.testRoom?.id))
        #expect(fallback.composerMessage == AgentRoomsLiveChatModel.unavailableMessage)
    }

    @Test("happy path keeps optimistic user order and source-backed terminal receipt")
    func happyPath() async throws {
        let transport = RoomsScriptedTransport(
            availability: .apiRuns,
            scripts: [.success(events: [
                .runStarted("run-805"),
                .messageDelta("Hello"),
                .completed(output: "Hello, Visher"),
                .completed(output: "duplicate terminal event"),
            ], envelope: envelope(runID: "run-805", user: "Tonight?", assistant: "Hello, Visher"))]
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Tonight?", selectedRoomID: roomID)

        let room = try #require(model.testRoom)
        #expect(room.transcript.messages.map(\.role) == [.human, .agent])
        #expect(room.transcript.messages.map(\.body) == ["Tonight?", "Hello, Visher"])
        #expect(room.transcript.messages[0].id.hasPrefix("cider-room-client:"))
        #expect(room.transcript.messages[0].deliveryState == .sent)
        #expect(room.transcript.receipt?.status == .completed)
        #expect(room.transcript.receipt?.continuity == .liveContinuation)
        #expect(room.transcript.receipt?.sourceBackedTransport == true)
        #expect(room.transcript.receipt?.detail == "Runs API · Source-backed terminal · Live continuation")
        #expect(await transport.sentTexts() == ["Tonight?"])
    }

    @Test("incremental deltas are sanitized, bounded, and reconciled with the final assistant")
    func incrementalStreamingReconcilesFinal() async throws {
        let transport = RoomsGateTransport(
            envelope: envelope(runID: "run-stream", user: "Stream", assistant: "Hello world")
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Stream", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        await transport.emit(.messageDelta("Hello\u{0000}"))
        await transport.emit(.messageDelta(" world"))
        await transport.emit(.messageDelta(""))

        let streaming = try #require(model.testRoom?.transcript.messages.last)
        #expect(streaming.role == .agent)
        #expect(streaming.body == "Hello world")
        #expect(model.turnState == .streaming)

        await transport.release()
        await send.value
        let completed = try #require(model.testRoom?.transcript.messages)
        #expect(completed.map(\.body) == ["Stream", "Hello world"])
        #expect(model.turnState == .completed)
    }

    @Test("tool and reasoning events preserve ordering without exposing malformed or unbounded text")
    func eventProjectionIsOrderedAndBounded() async throws {
        let transport = RoomsGateTransport(
            envelope: envelope(runID: "run-events", user: "Work", assistant: "Done")
        )
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Work", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        await transport.emit(.reasoningAvailable("  Planning\u{0007}  "))
        await transport.emit(.toolStarted(name: " Search ", preview: String(repeating: "x", count: 2_000)))
        await transport.emit(.toolCompleted(name: "Search", isError: false))

        #expect(model.liveActivity.map(\.kind) == [.reasoning, .toolStarted, .toolCompleted])
        #expect(model.liveActivity.first?.detail == "Planning")
        #expect(model.liveActivity.allSatisfy { $0.detail.count <= AgentRoomsLiveChatModel.maximumEventDetailLength })

        await transport.release()
        await send.value
    }

    @Test("empty and out-of-order events fail closed without leaking a partial assistant")
    func malformedEventsFailClosed() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .success(
                events: [.messageDelta("too early"), .runStarted(""), .messageDelta("")],
                envelope: envelope(runID: "run-malformed", user: "Check", assistant: "Do not show")
            ),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Check", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.map(\.role) == [.human])
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .failed)
        #expect(model.turnState == .failed)
    }

    @Test("pre-accept failure restores a one-shot draft and retry remains idempotent")
    func failedDraftRecovery() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .failure(events: [], error: .disconnected),
            .success(events: [.runStarted("run-restored")], envelope: envelope(runID: "run-restored", user: "Keep this", assistant: "Kept")),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send("Keep this", selectedRoomID: roomID)
        #expect(model.turnState == .failed)
        #expect(model.takeRecoveredDraft() == "Keep this")
        #expect(model.takeRecoveredDraft() == nil)

        let clientID = try #require(model.testRoom?.transcript.messages.first?.id)
        let first = Task { await model.retry(clientMessageID: clientID, selectedRoomID: roomID) }
        await model.retry(clientMessageID: clientID, selectedRoomID: roomID)
        await first.value
        #expect(await transport.sentTexts() == ["Keep this", "Keep this"])
    }

    @Test("follow policy follows only near the bottom and resumes after returning")
    func transcriptFollowPolicy() {
        var policy = AgentRoomsTranscriptFollowPolicy()
        let initiallyFollows = policy.shouldFollow(distanceFromBottom: 12)
        #expect(initiallyFollows)
        let followsAfterScrollingUp = policy.shouldFollow(distanceFromBottom: 240)
        #expect(!followsAfterScrollingUp)
        #expect(!policy.shouldAutoScrollForNewContent)
        let followsAfterReturning = policy.shouldFollow(distanceFromBottom: 20)
        #expect(followsAfterReturning)
        #expect(policy.shouldAutoScrollForNewContent)
    }

    @Test("whitespace and over-limit messages never reach transport")
    func validation() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        await model.send(" \n\t ", selectedRoomID: roomID)
        #expect(model.testRoom?.transcript.messages.isEmpty == true)
        #expect(model.composerMessage == "Type a message before sending.")
        #expect(model.isComposerEnabled(selectedRoomID: roomID))
        await model.send(String(repeating: "x", count: AgentRoomsLiveChatModel.maximumMessageLength + 1), selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.isEmpty == true)
        #expect(await transport.sentTexts().isEmpty)
        #expect(model.composerMessage == "Messages can be up to 4000 characters.")
    }

    @Test("double submit creates one optimistic message and one transport call")
    func doubleSubmit() async throws {
        let transport = RoomsGateTransport(envelope: envelope(runID: "run-gate", user: "Once", assistant: "Once received"))
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)

        let first = Task { await model.send("Once", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()
        await model.send("Once", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.count == 1)
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .pending)
        #expect(await transport.sendCount == 1)
        await transport.release()
        await first.value
        #expect(model.testRoom?.transcript.messages.count == 2)
    }

    @Test("pre-accept failure retries with the stable client id and no duplicate optimistic turn")
    func retryIsIdempotent() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .failure(events: [], error: .disconnected),
            .success(events: [.runStarted("run-retry")], envelope: envelope(runID: "run-retry", user: "Retry me", assistant: "Recovered")),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        await model.send("Retry me", selectedRoomID: roomID)
        let clientID = try #require(model.testRoom?.transcript.messages.first?.id)
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .failed)
        #expect(model.testRoom?.transcript.messages.first?.canRetry == true)
        #expect(model.composerMessage == AgentRoomsLiveChatModel.failedMessage)

        await model.retry(clientMessageID: clientID, selectedRoomID: roomID)

        let messages = try #require(model.testRoom?.transcript.messages)
        #expect(messages.map(\.id).filter { $0 == clientID }.count == 1)
        #expect(messages.map(\.body) == ["Retry me", "Recovered"])
        #expect(await transport.sentTexts() == ["Retry me", "Retry me"])
    }

    @Test("accepted interruption is sanitized and cannot be retried")
    func acceptedFailureDoesNotRetry() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .failure(events: [.runStarted("accepted-run")], error: .privateDetail),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        await model.send("Sensitive", selectedRoomID: roomID)

        let message = try #require(model.testRoom?.transcript.messages.first)
        #expect(message.deliveryState == .failed)
        #expect(!message.canRetry)
        #expect(model.composerMessage == AgentRoomsLiveChatModel.acceptedInterruptionMessage)
        #expect(model.composerMessage?.contains("credential") == false)
        await model.retry(clientMessageID: message.id, selectedRoomID: roomID)
        #expect(await transport.sentTexts() == ["Sensitive"])
    }

    @Test("conflicting run events fail closed without appending an assistant response")
    func outOfOrderResponseFailsClosed() async throws {
        let transport = RoomsScriptedTransport(availability: .apiRuns, scripts: [
            .success(
                events: [.runStarted("run-one"), .runStarted("run-two")],
                envelope: envelope(runID: "run-one", user: "Check", assistant: "Must not render")
            ),
        ])
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        await model.send("Check", selectedRoomID: roomID)

        #expect(model.testRoom?.transcript.messages.map(\.role) == [.human])
        #expect(model.testRoom?.transcript.messages.first?.deliveryState == .failed)
        #expect(model.testRoom?.transcript.receipt?.status == .failed)
    }

    @Test("cancel invalidates a late terminal result and uses stop for the accepted run")
    func cancellationDropsLateResult() async throws {
        let transport = RoomsGateTransport(envelope: envelope(runID: "run-late", user: "Stop", assistant: "Late private response"))
        let model = makeModel(transport)
        await model.startTestChat()
        let roomID = try #require(model.testRoom?.id)
        let send = Task { await model.send("Stop", selectedRoomID: roomID) }
        await transport.waitUntilSendStarted()

        await model.cancelActiveSend()
        await transport.release()
        await send.value

        #expect(model.testRoom?.transcript.messages.map(\.role) == [.human])
        #expect(model.testRoom?.transcript.receipt?.status == .cancelled)
        #expect(await transport.stoppedRunIDs == ["run-late"])
    }

    @Test("production composition injects real transport and does not use fixtures or repository writes")
    func productionCompositionIsRealAndSessionOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let composition = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        let liveModel = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Services/Conversation/AgentRoomsLiveChatModel.swift"), encoding: .utf8)

        #expect(composition.contains("HermesRunTransport()"))
        #expect(!composition.contains("AgentRoomsFixtureProvider"))
        #expect(!liveModel.contains("ConversationRepository"))
        #expect(!liveModel.contains("LegacyConversation"))
        #expect(!liveModel.contains("ConversationShadow"))
        #expect(!liveModel.contains("CiderAgentChatRegistry"))
        #expect(!liveModel.contains("HermesSessionService"))
        #expect(!liveModel.contains("AIConversationStorage"))
        #expect(!liveModel.contains("CiderVault"))

        let view = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"), encoding: .utf8)
        for required in [
            "Start Cider Test Chat",
            "Live continuation",
            "TextField(\"Message Hermes in Cider Test Chat\"",
            "Button(\"Send\")",
            ".onSubmit",
            "Shift-Return adds a line",
            "Retry failed message",
            ".accessibilityElement(children: .contain)",
            "Legacy messaging stays disabled; Cider Test Chat remains separate.",
            "Open Live Chat",
        ] {
            #expect(view.contains(required))
        }
    }

    private func makeModel(_ transport: some HermesBridgeTransport) -> AgentRoomsLiveChatModel {
        AgentRoomsLiveChatModel(transport: transport, turnCoordinator: HermesTurnCoordinator())
    }
}

private enum RoomsTransportError: Error, Sendable {
    case disconnected
    case privateDetail
}

private enum RoomsTransportScript: Sendable {
    case success(events: [HermesRunEvent], envelope: HermesRunCompletionEnvelope)
    case failure(events: [HermesRunEvent], error: RoomsTransportError)
}

private actor RoomsScriptedTransport: HermesBridgeTransport {
    let configuredAvailability: HermesBridgeAvailability
    private var scripts: [RoomsTransportScript]
    private var texts: [String] = []

    init(availability: HermesBridgeAvailability, scripts: [RoomsTransportScript]) {
        self.configuredAvailability = availability
        self.scripts = scripts
    }

    func availability() async -> HermesBridgeAvailability { configuredAvailability }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        texts.append(text)
        guard !scripts.isEmpty else { throw RoomsTransportError.disconnected }
        switch scripts.removeFirst() {
        case .success(let events, let envelope):
            for event in events { await onEvent?(event) }
            return HermesBridgeSendResult(completion: envelope)
        case .failure(let events, let error):
            for event in events { await onEvent?(event) }
            throw error
        }
    }

    func stop(runID: String) async throws {}
    func sentTexts() -> [String] { texts }
}

private actor RoomsGateTransport: HermesBridgeTransport {
    let resultEnvelope: HermesRunCompletionEnvelope
    private(set) var sendCount = 0
    private(set) var stoppedRunIDs: [String] = []
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var eventHandler: (@Sendable (HermesRunEvent) async -> Void)?

    init(envelope: HermesRunCompletionEnvelope) { self.resultEnvelope = envelope }

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sendCount += 1
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await onEvent?(.runStarted(resultEnvelope.runID ?? ""))
        eventHandler = onEvent
        if !released {
            await withCheckedContinuation { releaseWaiters.append($0) }
        }
        return HermesBridgeSendResult(completion: resultEnvelope)
    }

    func stop(runID: String) async throws { stoppedRunIDs.append(runID) }

    func waitUntilSendStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func emit(_ event: HermesRunEvent) async {
        await eventHandler?(event)
    }
}

private func envelope(runID: String, user: String, assistant: String) -> HermesRunCompletionEnvelope {
    let timestamp = Date(timeIntervalSince1970: 1_805_000_000)
    let sessionID = "session-805"
    let userSource = "hermes-run:\(runID):user"
    let assistantSource = "hermes-run:\(runID):assistant"
    let messages: [AIAssistantMessage] = [
        .init(role: .user, content: user, timestamp: timestamp, sourceID: userSource, sourceSessionID: sessionID, sourceName: "Hermes"),
        .init(role: .assistant, content: assistant, timestamp: timestamp, sourceID: assistantSource, sourceSessionID: sessionID, sourceName: "Hermes"),
    ]
    return HermesRunCompletionEnvelope(
        provenance: .hermesRunsAPI,
        runID: runID,
        terminalStatus: .completed,
        observedFacts: .none,
        finalSessionSynchronizationComplete: true,
        finalMessages: messages,
        finalState: HermesConversationState(
            conversationID: UUID(),
            activeRuntimeSessionID: sessionID,
            runtimeSessionLineage: [sessionID],
            title: "Cider Test Chat",
            source: "cider-rooms-live-continuation",
            lastSyncedAt: timestamp,
            lastSyncedMessageID: assistantSource,
            lastSyncedTimestamp: timestamp,
            lastImportedRuntimeSessionID: sessionID
        ),
        modelIdentity: "hermes-live",
        terminalSourceEvidence: .init(
            reportedTerminalRunID: runID,
            userSourceID: userSource,
            assistantSourceID: assistantSource,
            userSourceSessionID: sessionID,
            assistantSourceSessionID: sessionID
        )
    )
}
