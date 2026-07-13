import AppKit
import SwiftUI
import XCTest
@testable import Cider

final class AgentRoomsProductionCompositionSubmissionTests: XCTestCase {
    @MainActor
    func testProductionRunsTerminalOutputReconcilesFirstCharacterAndChunkedPartialsAcrossReopen() async throws {
        for host in ["first-character.invalid", "chunked-prefix.invalid"] {
            try await withProductionComposition { database, repository, databaseURL in
                let fixture = try seedProductionShapedCompletedTestChat(in: repository)
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = [ProductionTerminalReconciliationURLProtocol.self]
                let transport = HermesRunTransport(
                    apiClient: HermesAPIClient(
                        baseURL: try XCTUnwrap(URL(string: "https://\(host)")),
                        apiKey: nil,
                        session: URLSession(configuration: configuration)
                    ),
                    fallbackService: HermesSessionService()
                )
                let model = AgentRoomsLiveChatModel(
                    transport: transport,
                    turnCoordinator: HermesTurnCoordinator(),
                    persistence: AgentRoomsConversationPersistence(
                        database: database,
                        repository: repository
                    )
                )
                let (defaults, suiteName) = try disposableDefaults()
                defer { defaults.removePersistentDomain(forName: suiteName) }
                let session = productionSession(liveChat: model, defaults: defaults)

                XCTAssertTrue(session.restoreDurableTestChat())
                XCTAssertEqual(model.testRoom?.id, fixture.roomID.uuidString)
                await model.refreshTransportReadiness()
                session.createTestChat()
                let window = try hostedProductionWindow(repository: repository, session: session)
                defer { window.orderOut(nil) }
                await settleUI()

                let prompt = "CID-826 live golden-loop QA: reply with exactly CIDER CHAT OK."
                let terminal = "CIDER CHAT OK."
                let field = try XCTUnwrap(findComposerField(in: window.contentView))
                try enter(prompt, in: field, window: window)
                window.sendEvent(try returnEvent(in: window))
                await waitForTerminal(model)

                XCTAssertEqual(field.stringValue, "")
                XCTAssertEqual(model.turnState, .completed)
                XCTAssertEqual(model.activeRoom?.transcript.messages.last?.body, terminal)
                XCTAssertEqual(model.activeRoom?.transcript.receipt?.status, .completed)
                XCTAssertEqual(model.activeRoom?.transcript.receipt?.sourceBackedTransport, true)
                XCTAssertEqual(try repository.turns(roomID: fixture.roomID).last?.status, .completed)
                XCTAssertEqual(try repository.messages(roomID: fixture.roomID).suffix(2).map(\.contentText), [prompt, terminal])

                window.orderOut(nil)
                database.close()

                let reopenedDatabase = CiderDatabase()
                try reopenedDatabase.open(at: databaseURL)
                defer { reopenedDatabase.close() }
                let reopenedRepository = ConversationRepository(database: reopenedDatabase)
                let reconstructed = AgentRoomsLiveChatModel(
                    transport: ProductionCompositionTransport(availability: .apiRuns),
                    turnCoordinator: HermesTurnCoordinator(),
                    persistence: AgentRoomsConversationPersistence(
                        database: reopenedDatabase,
                        repository: reopenedRepository
                    )
                )

                XCTAssertTrue(reconstructed.restoreDurableTestChat())
                XCTAssertEqual(reconstructed.testRoom?.id, fixture.roomID.uuidString)
                XCTAssertEqual(reconstructed.testRoom?.transcript.messages.last?.body, terminal)
                XCTAssertEqual(
                    try reopenedRepository.messages(roomID: fixture.roomID).suffix(2).map(\.contentText),
                    [prompt, terminal]
                )
                XCTAssertTrue(try reopenedDatabase.integrityCheck().isHealthy)
            }
        }
    }

    @MainActor
    func testProductionShapedCompletedTestChatRestoresCanonicalIdentityAndContinues() async throws {
        try await withProductionComposition { database, repository, databaseURL in
            let fixture = try seedProductionShapedCompletedTestChat(in: repository)
            let historyBeforeRestore = try productionHistory(in: repository, roomID: fixture.roomID)
            let transport = ProductionCompositionTransport(availability: .apiRuns, suspendsSend: true)
            let model = AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    database: database,
                    repository: repository
                )
            )
            let (defaults, suiteName) = try disposableDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            defaults.set("AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", forKey: "selected-room")
            let session = productionSession(liveChat: model, defaults: defaults)

            XCTAssertTrue(session.restoreDurableTestChat())
            XCTAssertEqual(model.testRoom?.id, fixture.roomID.uuidString)
            XCTAssertEqual(model.testRoom?.transcript.messages.map(\.body), fixture.messageBodies)
            XCTAssertEqual(try productionHistory(in: repository, roomID: fixture.roomID), historyBeforeRestore)

            await model.refreshTransportReadiness()
            let window = try hostedProductionWindow(repository: repository, session: session)
            defer {
                Task { await transport.finishWithFailure() }
                window.orderOut(nil)
            }
            await settleUI()
            session.createTestChat()
            await model.refreshTransportReadiness()
            await settleUI()

            XCTAssertEqual(model.testRoom?.id, fixture.roomID.uuidString)
            XCTAssertEqual(model.testRoom?.transcript.messages.map(\.body), fixture.messageBodies)
            XCTAssertEqual(try productionHistory(in: repository, roomID: fixture.roomID), historyBeforeRestore)
            guard model.testRoom?.id == fixture.roomID.uuidString else { return }

            let prompt = "Continue the restored production-shaped Test Chat."
            let field = try XCTUnwrap(findComposerField(in: window.contentView))
            try enter(prompt, in: field, window: window)
            window.sendEvent(try returnEvent(in: window))
            await transport.waitUntilSendStarts()
            await settleUI()

            XCTAssertEqual(session.composerText, "")
            XCTAssertEqual(model.testRoom?.id, fixture.roomID.uuidString)
            XCTAssertEqual(model.activeRoom?.transcript.messages.map(\.body), fixture.messageBodies + [prompt])
            XCTAssertEqual(model.activeRoom?.transcript.messages.last?.deliveryState, .pending)
            XCTAssertEqual(try repository.turns(roomID: fixture.roomID).map(\.status), [.completed, .completed, .pending])
            XCTAssertEqual(try repository.messages(roomID: fixture.roomID).map(\.contentText), fixture.messageBodies + [prompt])
            let sentTexts = await transport.sentTexts()
            XCTAssertEqual(sentTexts, [prompt])

            let historyAfterSubmission = try productionHistory(in: repository, roomID: fixture.roomID)
            XCTAssertEqual(Array(historyAfterSubmission.turns.prefix(2)), historyBeforeRestore.turns)
            XCTAssertEqual(Array(historyAfterSubmission.messages.prefix(4)), historyBeforeRestore.messages)
            XCTAssertEqual(historyAfterSubmission.bindings, historyBeforeRestore.bindings)

            await transport.finishWithFailure()
            await settleUI()
            XCTAssertEqual(model.turnState, .failed)
            XCTAssertEqual(model.activeRoom?.transcript.messages.last?.deliveryState, .failed)
            window.orderOut(nil)
            database.close()

            let reopenedDatabase = CiderDatabase()
            try reopenedDatabase.open(at: databaseURL)
            defer { reopenedDatabase.close() }
            let reopenedRepository = ConversationRepository(database: reopenedDatabase)
            let reconstructed = AgentRoomsLiveChatModel(
                transport: ProductionCompositionTransport(availability: .apiRuns),
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    database: reopenedDatabase,
                    repository: reopenedRepository
                )
            )

            XCTAssertTrue(reconstructed.restoreDurableTestChat())
            XCTAssertEqual(reconstructed.testRoom?.id, fixture.roomID.uuidString)
            XCTAssertEqual(
                reconstructed.testRoom?.transcript.messages.map(\.body),
                fixture.messageBodies + [prompt]
            )
            let historyAfterReconstruction = try productionHistory(
                in: reopenedRepository,
                roomID: fixture.roomID
            )
            XCTAssertEqual(Array(historyAfterReconstruction.turns.prefix(2)), historyBeforeRestore.turns)
            XCTAssertEqual(Array(historyAfterReconstruction.messages.prefix(4)), historyBeforeRestore.messages)
            XCTAssertEqual(historyAfterReconstruction.bindings, historyBeforeRestore.bindings)
            XCTAssertEqual(historyAfterReconstruction.turns.last?.status, .failed)
            XCTAssertEqual(historyAfterReconstruction.messages.last?.contentText, prompt)
            XCTAssertTrue(try reopenedDatabase.integrityCheck().isHealthy)
        }
    }

    func testProductionSwiftUISubmissionUsesModelAcceptanceInsteadOfInlineClearAndTask() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf:
            repositoryRoot.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"),
            encoding: .utf8
        )
        let submission = try XCTUnwrap(source.range(of: "private func submitComposer(roomID: String)"))
        let suffix = source[submission.lowerBound...]
        let functionBody = String(suffix.prefix(500))

        XCTAssertTrue(functionBody.contains("liveChat.startSubmission("))
        XCTAssertTrue(functionBody.contains("invokedParticipantIDs: participantIDs"))
        XCTAssertFalse(functionBody.contains("liveChat.isComposerEnabled"))
        XCTAssertFalse(functionBody.contains("Task { await liveChat.send"))
        XCTAssertLessThan(
            try XCTUnwrap(functionBody.range(of: "startSubmission")?.lowerBound),
            try XCTUnwrap(functionBody.range(of: "composerText = \"\"")?.lowerBound)
        )
    }

    @MainActor
    func testMixedBlockedLegacyCompositionPreservesDraftAndSurfacesPreAcceptFailure() async throws {
        try await withProductionComposition { database, repository, _ in
            let existingRoom = try repository.createRoom(.init(
                stableKey: AgentRoomsTestChatPersistence.stableRoomKey,
                title: AgentRoomsLiveChatModel.roomTitle,
                kind: "chat",
                metadata: ["authority": "legacy-authoritative"],
                createdAt: Date(timeIntervalSince1970: 1_805_300_000)
            ))
            let transport = ProductionCompositionTransport(availability: .apiRuns)
            let model = AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    database: database,
                    repository: repository
                )
            )
            let (defaults, suiteName) = try disposableDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let session = productionSession(liveChat: model, defaults: defaults)
            await session.startTestChat()
            let activeRoomID = try XCTUnwrap(model.testRoom?.id)
            XCTAssertNotEqual(activeRoomID, existingRoom.id.uuidString)

            let window = try hostedProductionWindow(
                repository: repository,
                session: session
            )
            defer { window.orderOut(nil) }
            await settleUI()

            let prompt = String(repeating: "a", count: 210)
            let field = try XCTUnwrap(findComposerField(in: window.contentView))
            try enter(prompt, in: field, window: window)
            window.sendEvent(try returnEvent(in: window))
            await settleUI()

            XCTAssertEqual(
                field.stringValue,
                prompt,
                "A submission that Cider could not durably accept must remain in the composer"
            )
            XCTAssertEqual(model.activeRoom?.transcript.messages, [])
            XCTAssertEqual(model.statusPresentation.state, .failed)
            XCTAssertEqual(
                model.statusPresentation.detail,
                "Cider could not safely save this message. Nothing was sent."
            )
            let sentTexts = await transport.sentTexts()
            XCTAssertEqual(sentTexts, [])
            XCTAssertEqual(try repository.turns(roomID: existingRoom.id), [])
            XCTAssertEqual(try repository.messages(roomID: existingRoom.id), [])
            XCTAssertEqual(try repository.room(id: existingRoom.id)?.metadata["authority"], "legacy-authoritative")
        }
    }

    @MainActor
    func testMixedBlockedLegacyCompositionShowsDurablePendingRowBeforeTransportCompletes() async throws {
        try await withProductionComposition { database, repository, _ in
            let transport = ProductionCompositionTransport(availability: .apiRuns, suspendsSend: true)
            let model = AgentRoomsLiveChatModel(
                transport: transport,
                turnCoordinator: HermesTurnCoordinator(),
                persistence: AgentRoomsConversationPersistence(
                    database: database,
                    repository: repository
                )
            )
            let (defaults, suiteName) = try disposableDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let session = productionSession(liveChat: model, defaults: defaults)
            await session.startTestChat()
            let roomID = try XCTUnwrap(UUID(uuidString: try XCTUnwrap(model.testRoom?.id)))

            let window = try hostedProductionWindow(
                repository: repository,
                session: session
            )
            defer {
                Task { await transport.finishWithFailure() }
                window.orderOut(nil)
            }
            await settleUI()

            let prompt = "Prove durable acceptance before transport completion."
            let field = try XCTUnwrap(findComposerField(in: window.contentView))
            try enter(prompt, in: field, window: window)
            window.sendEvent(try returnEvent(in: window))
            await transport.waitUntilSendStarts()
            await settleUI()

            XCTAssertEqual(field.stringValue, "")
            XCTAssertEqual(model.turnState, .sending)
            XCTAssertEqual(model.statusPresentation.state, .sending)
            XCTAssertEqual(model.activeRoom?.transcript.messages.map(\.body), [prompt])
            XCTAssertEqual(model.activeRoom?.transcript.messages.first?.deliveryState, .pending)
            XCTAssertEqual(try repository.turns(roomID: roomID).map(\.status), [.pending])
            XCTAssertEqual(try repository.messages(roomID: roomID).map(\.contentText), [prompt])
            let sentTexts = await transport.sentTexts()
            XCTAssertEqual(sentTexts, [prompt])

            await transport.finishWithFailure()
            await settleUI()
            XCTAssertEqual(model.turnState, .failed)
            XCTAssertEqual(model.activeRoom?.transcript.messages.first?.deliveryState, .failed)
        }
    }

    @MainActor
    private func hostedProductionWindow(
        repository: ConversationRepository,
        session: AgentRoomsSessionModel
    ) throws -> CiderMainWindow {
        let blocked = AgentRoomsWorkspaceState.blocked(
            authority: .legacyAuthoritativePreview,
            message: LegacyAgentRoomsPreviewService.blockedMessage
        )
        let view = AgentRoomsWorkspaceView(
            loadWorkspace: { _ in blocked },
            roomActions: AgentRoomsActionService(repository: repository),
            session: session,
            onOpenLiveChat: {}
        )
        .frame(width: 1_000, height: 700)
        let window = CiderMainWindow()
        window.setFrame(NSRect(x: 100, y: 100, width: 1_000, height: 700), display: false)
        window.contentView = CiderMainWindowHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    @MainActor
    private func productionSession(
        liveChat: AgentRoomsLiveChatModel,
        defaults: UserDefaults
    ) -> AgentRoomsSessionModel {
        AgentRoomsSessionModel(
            liveChat: liveChat,
            selectionStore: AgentRoomsSelectionStore(
                defaults: defaults,
                key: "selected-room"
            ),
            draftStore: AgentRoomsDraftStore(
                defaults: defaults,
                key: "drafts"
            )
        )
    }

    private func disposableDefaults() throws -> (UserDefaults, String) {
        let suiteName = "AgentRoomsProductionCompositionSubmissionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    @MainActor
    private func seedProductionShapedCompletedTestChat(
        in repository: ConversationRepository
    ) throws -> ProductionTestChatFixture {
        let roomID = try XCTUnwrap(UUID(uuidString: "34E94CC6-744B-49FA-B5E2-D1C76B6FE664"))
        let bindingID = try XCTUnwrap(UUID(uuidString: "C954CA46-FBDC-402C-BD41-1797BDC18338"))
        let turnIDs = try [
            "49AEFD9E-4097-4730-B941-7031E2DC38BF",
            "345C9760-B903-48AF-A147-D62E863C716B",
        ].map { try XCTUnwrap(UUID(uuidString: $0)) }
        let messageIDs = try [
            "0E5FB776-14BD-4B61-B7E8-01583EF6C62E",
            "3BC07703-FDDF-4E85-84FB-D05BA11A7A01",
            "73464724-0597-4DAC-852C-0714DCE81BEF",
            "DB1DA587-1CD5-4B14-8F23-E658E33E3972",
        ].map { try XCTUnwrap(UUID(uuidString: $0)) }
        let runIDs = ["run-production-history-1", "run-production-history-2"]
        let sessionID = "run-production-session"
        let dates = [
            Date(timeIntervalSince1970: 1_783_877_691.2977281),
            Date(timeIntervalSince1970: 1_783_879_114.09725),
        ]
        let messageBodies = [
            "Historical user one",
            "Historical assistant one",
            "Historical user two",
            "Historical assistant two",
        ]
        let authority = "cider-test-chat.hermes-runs.v1"
        _ = try repository.createRoom(.init(
            id: roomID,
            stableKey: AgentRoomsTestChatPersistence.stableRoomKey,
            title: AgentRoomsLiveChatModel.roomTitle,
            kind: "cider-test-chat",
            metadata: [
                "authority": authority,
                "schema_version": "1",
                "source": "cider-rooms-live-continuation",
            ],
            createdAt: dates[0],
            updatedAt: Date(timeIntervalSince1970: 1_783_879_114.112711)
        ))
        _ = try repository.upsertRuntimeBinding(.init(
            id: bindingID,
            roomID: roomID,
            runtimeID: "hermes",
            transportID: "runs-api",
            sourceNamespace: "hermes.runs.v1",
            externalSessionID: sessionID,
            state: .active,
            cursorMessageID: "hermes-run:\(runIDs[1]):assistant",
            cursorTimestamp: dates[1],
            metadata: [
                "authority": authority,
                "lineage_index": "0",
                "schema_version": "1",
            ],
            createdAt: dates[0],
            updatedAt: dates[1]
        ))

        var parentMessageID: UUID?
        for turnIndex in 0..<2 {
            let runID = runIDs[turnIndex]
            let turn = try repository.beginTurn(.init(
                id: turnIDs[turnIndex],
                roomID: roomID,
                runtimeBindingID: bindingID,
                source: .init(namespace: "hermes.runs.v1", id: runID),
                status: .completed,
                metadata: [
                    "authority": authority,
                    "cider_references_json": "[]",
                    "model_identity": "cider",
                    "schema_version": "1",
                ],
                createdAt: dates[turnIndex]
            ))
            for roleIndex in 0..<2 {
                let messageIndex = turnIndex * 2 + roleIndex
                let role = roleIndex == 0 ? "user" : "assistant"
                let message = try repository.upsertMessage(.init(
                    id: messageIDs[messageIndex],
                    roomID: roomID,
                    turnID: turn.id,
                    runtimeBindingID: bindingID,
                    parentMessageID: parentMessageID,
                    role: role,
                    contentText: messageBodies[messageIndex],
                    status: .complete,
                    finishReason: .stop,
                    source: .init(namespace: "hermes.runs.v1", id: "hermes-run:\(runID):\(role)"),
                    sourceCreatedAt: dates[turnIndex],
                    metadata: [
                        "authority": authority,
                        "model_identity": "cider",
                        "run_id": runID,
                        "schema_version": "1",
                        "session_id": sessionID,
                    ],
                    createdAt: dates[turnIndex]
                ), intent: .historicalReplay).message
                parentMessageID = message.id
            }
        }
        return .init(roomID: roomID, messageBodies: messageBodies)
    }

    @MainActor
    private func productionHistory(
        in repository: ConversationRepository,
        roomID: UUID
    ) throws -> ProductionHistorySnapshot {
        .init(
            room: try XCTUnwrap(repository.room(id: roomID)),
            turns: try repository.turns(roomID: roomID),
            messages: try repository.messages(roomID: roomID),
            bindings: try repository.bindings(roomID: roomID)
        )
    }

    @MainActor
    private func enter(_ text: String, in field: NSTextField, window: NSWindow) throws {
        let center = field.convert(NSPoint(x: field.bounds.midX, y: field.bounds.midY), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(
                with: type,
                location: center,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 1,
                clickCount: 1,
                pressure: type == .leftMouseDown ? 1 : 0
            ))
            window.sendEvent(event)
        }
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    @MainActor
    private func findComposerField(in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let field = view as? NSTextField,
           field.placeholderString == "Message Hermes in Cider Test Chat" {
            return field
        }
        for subview in view.subviews {
            if let match = findComposerField(in: subview) { return match }
        }
        return nil
    }

    @MainActor
    private func returnEvent(in window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
    }

    @MainActor
    private func settleUI() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(100))
    }

    @MainActor
    private func waitForTerminal(_ model: AgentRoomsLiveChatModel) async {
        for _ in 0..<100 where model.turnState != .completed && model.turnState != .failed {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        await settleUI()
    }

    @MainActor
    private func withProductionComposition(
        _ body: @MainActor (CiderDatabase, ConversationRepository, URL) async throws -> Void
    ) async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-production-submit-\(UUID().uuidString).db")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        let database = CiderDatabase()
        try database.open(at: url)
        defer { database.close() }
        try await body(database, ConversationRepository(database: database), url)
    }
}

private struct ProductionTestChatFixture {
    let roomID: UUID
    let messageBodies: [String]
}

private struct ProductionHistorySnapshot: Equatable {
    let room: ConversationRoom
    let turns: [ConversationTurn]
    let messages: [ConversationMessage]
    let bindings: [ConversationRuntimeBinding]
}

private actor ProductionCompositionTransport: HermesBridgeTransport {
    private let available: HermesBridgeAvailability
    private let suspendsSend: Bool
    private var texts: [String] = []
    private var continuation: CheckedContinuation<Void, Error>?

    init(availability: HermesBridgeAvailability, suspendsSend: Bool = false) {
        self.available = availability
        self.suspendsSend = suspendsSend
    }

    func availability() async -> HermesBridgeAvailability { available }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        texts.append(text)
        if suspendsSend {
            try await withCheckedThrowingContinuation { continuation = $0 }
        }
        throw ProductionCompositionTransportError.preAcceptFailure
    }

    func stop(runID: String) async throws {}

    func waitUntilSendStarts() async {
        while texts.isEmpty { await Task.yield() }
    }

    func finishWithFailure() {
        continuation?.resume(throwing: ProductionCompositionTransportError.preAcceptFailure)
        continuation = nil
    }

    func sentTexts() -> [String] { texts }
}

private enum ProductionCompositionTransportError: Error {
    case preAcceptFailure
}

private final class ProductionTerminalReconciliationURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: ProductionCompositionTransportError.preAcceptFailure)
            return
        }
        let runID = url.host == "first-character.invalid"
            ? "run-cid826-first-character"
            : "run-cid826-chunked-prefix"
        let (status, contentType, body): (Int, String, String)
        switch (request.httpMethod, url.path) {
        case ("GET", "/v1/capabilities"):
            status = 200
            contentType = "application/json"
            body = """
            {
              "object":"hermes.api_server.capabilities",
              "platform":"hermes-agent",
              "model":"cider",
              "features":{
                "chat_completions":true,
                "chat_completions_streaming":true,
                "responses_api":true,
                "responses_streaming":true,
                "run_submission":true,
                "run_status":true,
                "run_events_sse":true,
                "run_stop":true,
                "tool_progress_events":true,
                "session_continuity_header":"X-Hermes-Session-Id"
              }
            }
            """
        case ("POST", "/v1/runs"):
            status = 202
            contentType = "application/json"
            body = #"{"run_id":"\#(runID)","status":"started"}"#
        case ("GET", "/v1/runs/\(runID)/events"):
            status = 200
            contentType = "text/event-stream"
            if url.host == "first-character.invalid" {
                body = """
                data: {"event":"message.delta","run_id":"\(runID)","delta":"C"}

                data: {"event":"run.completed","run_id":"\(runID)","output":"CIDER CHAT OK."}

                """
            } else {
                body = """
                data: {"event":"message.delta","run_id":"\(runID)","delta":"C"}

                data: {"event":"message.delta","run_id":"\(runID)","delta":"ID"}

                data: {"event":"message.delta","run_id":"\(runID)","delta":"ER "}

                data: {"event":"run.completed","run_id":"\(runID)","output":"CIDER CHAT OK."}

                """
            }
        case ("GET", "/v1/runs/\(runID)"):
            status = 200
            contentType = "application/json"
            body = #"{"object":"hermes.run","run_id":"\#(runID)","status":"completed","session_id":"run-production-session","output":"CIDER CHAT OK.","last_event":"run.completed"}"#
        default:
            status = 404
            contentType = "application/json"
            body = #"{"error":"unexpected request"}"#
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
