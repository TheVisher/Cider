import AppKit
import SwiftUI
import XCTest
@testable import Cider

final class AgentRoomsProductionCompositionCompatibilityTests: XCTestCase {
    @MainActor
    func testCurrentAssignedHermesCompositionAcceptsCombinedInputsAndContinuesAfterPhysicalReopen() async throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.cleanup() }
        let first = try fixture.makeProductionComposition()
        let room = try AgentRoomsActionService(
            repository: first.repository,
            agentAssignments: first.assignments
        ).createConversation(title: "Disposable production composition")
        first.session.selectRoom(id: room.id.uuidString, persistIfCanonical: true)
        await first.session.liveChat.refreshTransportReadiness()

        XCTAssertEqual(try first.assignments.assignment(roomID: room.id)?.profile.id, "hermes")
        let hermesParticipantID = try XCTUnwrap(
            try first.participants.roster(roomID: room.id)?.actingAgent?.id
        )

        first.session.composerText = "Typed seed  with spacing"
        await first.session.startTranscription()
        first.session.cancelTranscription()
        XCTAssertEqual(first.session.composerText, "Typed seed  with spacing")
        XCTAssertEqual(first.session.speechPresentation.state, .cancelled)

        await first.session.startTranscription()
        first.transcription.emitFinal("dictated words")
        first.session.composerText += " edited"
        XCTAssertEqual(first.session.composerText, "Typed seed  with spacing dictated words edited")
        let sendCountBeforeSubmission = await first.transport.currentSendCount()
        XCTAssertEqual(sendCountBeforeSubmission, 0)

        first.session.liveChat.stageAttachments(
            from: [try fixture.writeTextAttachment()],
            source: .filePicker
        )
        XCTAssertEqual(first.session.liveChat.stagedAttachments.count, 1)
        XCTAssertEqual(try first.repository.turns(roomID: room.id), [])

        XCTAssertEqual(
            first.session.liveChat.startSubmission(
                first.session.composerText,
                selectedRoomID: room.id.uuidString,
                invokedParticipantIDs: [hermesParticipantID]
            ),
            .accepted
        )
        await waitForTerminal(first.session.liveChat)

        XCTAssertEqual(first.session.liveChat.turnState, .completed)
        XCTAssertEqual(first.session.liveChat.activeRoom?.transcript.messages.map(\.body), [
            "Typed seed  with spacing dictated words edited",
            "Production composition reply 1",
        ])
        XCTAssertEqual(
            first.session.liveChat.activeRoom?.transcript.receipt?.activity.map(\.kind),
            [.reasoning, .toolStarted, .toolCompleted]
        )
        XCTAssertEqual(first.session.liveChat.activeRoom?.transcript.receipt?.status, .completed)
        XCTAssertTrue(
            first.session.liveChat.activeRoom?.transcript.receipt?.runIdentity?
                .hasPrefix("compatibility-") == true
        )
        let sendCountAfterSubmission = await first.transport.currentSendCount()
        let attachmentCountAfterSubmission = await first.transport.lastAttachmentCount()
        XCTAssertEqual(sendCountAfterSubmission, 1)
        XCTAssertEqual(attachmentCountAfterSubmission, 1)
        let firstTurn = try XCTUnwrap(try first.repository.turns(roomID: room.id).first)
        XCTAssertEqual(
            try first.participants.turnAttribution(firstTurn)?.participantID,
            hermesParticipantID
        )
        XCTAssertEqual(firstTurn.status, .completed)

        try fixture.reopen()
        let reopened = try fixture.makeProductionComposition()
        reopened.session.selectRoom(id: room.id.uuidString, persistIfCanonical: true)
        await reopened.session.liveChat.refreshTransportReadiness()

        XCTAssertEqual(reopened.session.liveChat.activeRoom?.id, room.id.uuidString)
        XCTAssertEqual(reopened.session.liveChat.activeRoom?.transcript.messages.map(\.body), [
            "Typed seed  with spacing dictated words edited",
            "Production composition reply 1",
        ])
        XCTAssertEqual(reopened.session.liveChat.activeRoom?.transcript.receipt?.status, .completed)
        XCTAssertEqual(reopened.session.liveChat.activeRoom?.transcript.receipt?.activity.count, 3)
        let restored = try XCTUnwrap(
            try AgentRoomsConversationPersistence(
                database: fixture.database,
                repository: reopened.repository
            ).restoreCanonicalRoom(id: room.id)
        )
        XCTAssertEqual(restored.latestAttachments.count, 1)
        XCTAssertEqual(restored.latestAttachments.first?.lifecycle, "accepted")
        XCTAssertEqual(restored.latestAttachments.first?.sha256?.count, 64)
        XCTAssertFalse(String(describing: restored.latestAttachments).contains(fixture.root.path))

        let reopenedHermesID = try XCTUnwrap(
            try reopened.participants.roster(roomID: room.id)?.actingAgent?.id
        )
        XCTAssertEqual(
            reopened.session.liveChat.startSubmission(
                "Continue after physical reopen",
                selectedRoomID: room.id.uuidString,
                invokedParticipantIDs: [reopenedHermesID]
            ),
            .accepted
        )
        await waitForTerminal(reopened.session.liveChat)

        XCTAssertEqual(reopened.session.liveChat.turnState, .completed)
        XCTAssertEqual(try reopened.repository.turns(roomID: room.id).map(\.status), [
            .completed, .completed,
        ])
        XCTAssertEqual(try reopened.repository.messages(roomID: room.id).map(\.contentText), [
            "Typed seed  with spacing dictated words edited",
            "Production composition reply 1",
            "Continue after physical reopen",
            "Production composition reply 1",
        ])
        let runtimeSessions = try reopened.repository.bindings(roomID: room.id)
            .compactMap(\.externalSessionID)
        XCTAssertEqual(runtimeSessions.count, 2)
        XCTAssertEqual(Set(runtimeSessions).count, 2)
        XCTAssertTrue(try fixture.database.integrityCheck().isHealthy)
    }

    @MainActor
    func testPreCheckpointTestChatReopensWithoutImplicitMetadataAndKeepsDistinctInputGates() async throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.seedPreCheckpointTestChat()
        try fixture.reopen()

        let composition = try fixture.makeProductionComposition()
        XCTAssertTrue(composition.session.restoreDurableTestChat())
        let roomID = try XCTUnwrap(composition.session.liveChat.testRoom?.id)
        composition.session.selectRoom(id: roomID, persistIfCanonical: true)
        composition.session.composerText = "Keep  this draft\nexactly"
        await composition.session.liveChat.refreshTransportReadiness()

        let roomUUID = try XCTUnwrap(UUID(uuidString: roomID))
        XCTAssertNil(try composition.assignments.assignment(roomID: roomUUID))
        XCTAssertNil(try composition.participants.roster(roomID: roomUUID))
        let metadata = try XCTUnwrap(composition.repository.room(id: roomUUID)?.metadata)
        XCTAssertNil(metadata[ConversationRepository.agentAssignmentMetadataKey])
        XCTAssertNil(metadata[ConversationRepository.participantRosterMetadataKey])
        XCTAssertEqual(composition.session.liveChat.activeRoom?.transcript.messages.map(\.body), [
            "Canonical history before CID-827.",
        ])

        XCTAssertTrue(composition.session.liveChat.isDraftEditingEnabled(selectedRoomID: roomID))
        XCTAssertTrue(composition.session.liveChat.isAttachmentStagingEnabled(selectedRoomID: roomID))
        XCTAssertFalse(composition.session.liveChat.isComposerEnabled(selectedRoomID: roomID))
        XCTAssertFalse(composition.session.liveChat.isParticipantInvocationEnabled(selectedRoomID: roomID))
        XCTAssertTrue(composition.session.canStartTranscription(roomID: roomID))

        XCTAssertEqual(
            composition.session.liveChat.startSubmission(
                composition.session.composerText,
                selectedRoomID: roomID
            ),
            .rejected
        )
        XCTAssertEqual(composition.session.composerText, "Keep  this draft\nexactly")
        let sendCountAfterBlockedSend = await composition.transport.currentSendCount()
        XCTAssertEqual(sendCountAfterBlockedSend, 0)
        XCTAssertTrue(try composition.repository.turns(roomID: roomUUID).isEmpty)
        XCTAssertEqual(try composition.repository.messages(roomID: roomUUID).map(\.contentText), [
            "Canonical history before CID-827.",
        ])

        let attachment = try fixture.writeTextAttachment()
        composition.session.liveChat.stageAttachments(from: [attachment], source: .filePicker)
        XCTAssertEqual(composition.session.liveChat.stagedAttachments.count, 1)
        XCTAssertTrue(try composition.repository.turns(roomID: roomUUID).isEmpty)
        let sendCountAfterStaging = await composition.transport.currentSendCount()
        XCTAssertEqual(sendCountAfterStaging, 0)

        await composition.session.startTranscription()
        composition.transcription.emitFinal("speech stays editable")
        XCTAssertEqual(composition.session.composerText, "Keep  this draft\nexactly speech stays editable")
        let sendCountAfterSpeech = await composition.transport.currentSendCount()
        XCTAssertEqual(sendCountAfterSpeech, 0)
        XCTAssertTrue(try composition.repository.turns(roomID: roomUUID).isEmpty)

        let finalMetadata = try XCTUnwrap(composition.repository.room(id: roomUUID)?.metadata)
        XCTAssertNil(finalMetadata[ConversationRepository.agentAssignmentMetadataKey])
        XCTAssertNil(finalMetadata[ConversationRepository.participantRosterMetadataKey])
    }

    @MainActor
    func testHostedFallbackAuthorityKeepsNativeControlsDistinctTruthfulAndResponsive() async throws {
        let fixture = try CompatibilityFixture()
        defer { fixture.cleanup() }
        try fixture.seedPreCheckpointTestChat()
        try fixture.reopen()
        let composition = try fixture.makeProductionComposition()
        XCTAssertTrue(composition.session.restoreDurableTestChat())
        let roomID = try XCTUnwrap(composition.session.liveChat.testRoom?.id)
        composition.session.selectRoom(id: roomID, persistIfCanonical: true)
        composition.session.composerText = "Preserved hosted draft"
        await composition.session.liveChat.refreshTransportReadiness()

        for width in [1_000.0, 520.0] {
            let window = try await hostCompatibilityView(
                width: width,
                composition: composition,
                fixture: fixture
            )

            let elements = accessibilityElements(in: window.contentView)
            assertNativeElement(
                label: "Acting agent: Not assigned",
                role: NSAccessibility.Role.menuButton.rawValue,
                elements: elements
            )
            assertNativeElement(
                label: "File attachment drop target",
                role: NSAccessibility.Role.group.rawValue,
                elements: elements
            )
            assertNativeElement(
                label: "Message Unassigned in Cider Test Chat",
                role: NSAccessibility.Role.textField.rawValue,
                elements: elements
            )
            window.orderOut(nil)
        }

        try assertProductionAccessibilitySourceContract()

        XCTAssertEqual(composition.session.composerText, "Preserved hosted draft")
        let finalSendCount = await composition.transport.currentSendCount()
        XCTAssertEqual(finalSendCount, 0)
    }

    func testWideNarrowAndReduceMotionPoliciesRemainDeterministic() {
        XCTAssertEqual(AgentRoomsWorkspaceLayoutPolicy.mode(width: 1_000, usesAccessibilityText: false), .sideBySide)
        XCTAssertEqual(AgentRoomsWorkspaceLayoutPolicy.mode(width: 520, usesAccessibilityText: false), .stacked)
        XCTAssertTrue(AgentRoomsTranscriptMotionPolicy.disablesScrollAnimations(reduceMotion: true))
        XCTAssertFalse(AgentRoomsTranscriptMotionPolicy.disablesScrollAnimations(reduceMotion: false))
    }

    @MainActor
    private func waitForTerminal(_ model: AgentRoomsLiveChatModel) async {
        for _ in 0..<200 where model.turnState != .completed && model.turnState != .failed {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @MainActor
    private func hostCompatibilityView(
        width: CGFloat,
        composition: CompatibilityComposition,
        fixture: CompatibilityFixture
    ) async throws -> NSWindow {
        let canonical = AgentRoomsReadService(
            repository: composition.repository,
            agentAssignments: composition.assignments,
            participants: composition.participants
        )
        let fallback = AgentRoomsWorkspaceState.eligibleEmpty(
            authority: .legacyAuthoritativePreview,
            notice: .init(kind: .empty, displayed: 0, omitted: 0, capOmitted: 0, unregistered: 0)
        )
        let loader = AgentRoomsWorkspaceLoader(
            loadCanonical: canonical.loadWorkspace,
            loadLegacy: { fallback }
        )
        let view = AgentRoomsWorkspaceView(
            loadWorkspace: { _ in loader.loadWorkspace() },
            roomActions: AgentRoomsActionService(
                repository: composition.repository,
                agentAssignments: composition.assignments
            ),
            session: composition.session,
            onOpenLiveChat: {}
        )
        .frame(width: width, height: 760)
        let window = CiderMainWindow()
        window.setFrame(NSRect(x: 80, y: 80, width: width, height: 760), display: false)
        window.contentView = CiderMainWindowHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        await Task.yield()
        try await Task.sleep(for: .milliseconds(150))
        window.contentView?.layoutSubtreeIfNeeded()
        return window
    }

    @MainActor
    private func accessibilityElements(in view: NSView?) -> [CompatibilityAXElement] {
        guard let view else { return [] }
        var result: [CompatibilityAXElement] = []
        var visited = Set<ObjectIdentifier>()
        if let role = view.accessibilityRole()?.rawValue {
            result.append(.init(role: role, label: view.accessibilityLabel(), enabled: true))
        }
        if let field = view as? NSTextField,
           let object = field.accessibilityChildren()?.first as? NSObject,
           let role = object.perform(NSSelectorFromString("accessibilityRole"))?
            .takeUnretainedValue() as? String {
            result.append(.init(
                role: role,
                label: field.accessibilityLabel() ?? field.placeholderString,
                enabled: field.isEnabled
            ))
        }
        for child in view.accessibilityChildren() ?? [] {
            if let child = child as? NSObject {
                collectAccessibilityObject(child, into: &result, visited: &visited)
            }
        }
        for subview in view.subviews {
            result.append(contentsOf: accessibilityElements(in: subview))
        }
        return result
    }

    private func assertProductionAccessibilitySourceContract(
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"
            ),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("Acting agent: "), file: file, line: line)
        XCTAssertTrue(source.contains("Participants unavailable. This older room has no participant roster."), file: file, line: line)
        XCTAssertTrue(source.contains("Button(participant.available ? \"Invoke next\" : \"Unavailable\")"), file: file, line: line)
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Attach text or image files\")"), file: file, line: line)
        XCTAssertTrue(source.contains("TextField(composerPlaceholder(roomID: roomID)"), file: file, line: line)
        XCTAssertTrue(source.contains(".accessibilityLabel(\"Start microphone transcription\")"), file: file, line: line)
        XCTAssertTrue(source.contains(".accessibilityLabel(composerActionAccessibilityLabel(roomID: roomID))"), file: file, line: line)
        XCTAssertFalse(source.contains(".accessibilityLabel(\"Message composer controls\")"), file: file, line: line)
    }

    @MainActor
    private func collectAccessibilityObject(
        _ object: NSObject,
        into result: inout [CompatibilityAXElement],
        visited: inout Set<ObjectIdentifier>
    ) {
        guard visited.insert(ObjectIdentifier(object)).inserted else { return }
        let role = object.perform(NSSelectorFromString("accessibilityRole"))?
            .takeUnretainedValue() as? String
        let label = object.perform(NSSelectorFromString("accessibilityLabel"))?
            .takeUnretainedValue() as? String
        if let role {
            result.append(.init(role: role, label: label, enabled: true))
        }
        guard let children = object.perform(NSSelectorFromString("accessibilityChildren"))?
            .takeUnretainedValue() as? NSArray
        else { return }
        for child in children {
            if let child = child as? NSObject {
                collectAccessibilityObject(child, into: &result, visited: &visited)
            }
        }
    }

    private func assertNativeElement(
        label: String,
        role: String,
        enabled: Bool? = nil,
        elements: [CompatibilityAXElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let matches = elements.filter { $0.label == label }
        XCTAssertFalse(
            matches.isEmpty,
            "Missing AX element: \(label). Available: \(elements)",
            file: file,
            line: line
        )
        XCTAssertTrue(matches.contains { $0.role == role }, "Wrong AX role for \(label): \(matches)", file: file, line: line)
        if let enabled {
            XCTAssertTrue(matches.contains { $0.role == role && $0.enabled == enabled }, "Wrong enabled state for \(label): \(matches)", file: file, line: line)
        }
    }
}

private struct CompatibilityAXElement: CustomStringConvertible {
    let role: String
    let label: String?
    let enabled: Bool
    var description: String { "\(role):\(label ?? "nil"):\(enabled)" }
}

@MainActor
private struct CompatibilityComposition {
    let repository: ConversationRepository
    let assignments: AgentRoomsAgentAssignmentService
    let participants: AgentRoomsParticipantService
    let session: AgentRoomsSessionModel
    let transport: CompatibilityTransport
    let transcription: CompatibilityTranscriptionService
}

@MainActor
private final class CompatibilityFixture {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("cider-room-production-compatibility-\(UUID().uuidString)", isDirectory: true)
    lazy var databaseURL = root.appendingPathComponent("conversation.sqlite")
    private(set) var database = CiderDatabase()
    private let defaults: UserDefaults
    private let suiteName: String
    private let roomID = UUID()

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "AgentRoomsProductionCompositionCompatibilityTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        try database.open(at: databaseURL)
    }

    func seedPreCheckpointTestChat() throws {
        let repository = ConversationRepository(database: database)
        _ = try repository.createRoom(.init(
            id: roomID,
            stableKey: AgentRoomsTestChatPersistence.stableRoomKey,
            title: AgentRoomsLiveChatModel.roomTitle,
            kind: "cider-test-chat",
            metadata: [
                "authority": AgentRoomsConversationPersistence.testRoomAuthority,
                "schema_version": "1",
                "source": "cider-rooms-live-continuation",
            ],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        _ = try repository.upsertMessage(.init(
            roomID: roomID,
            role: "assistant",
            contentText: "Canonical history before CID-827.",
            status: .complete,
            finishReason: .stop,
            source: .init(namespace: "hermes.runs.v1", id: "pre-checkpoint:assistant"),
            sourceCreatedAt: Date(timeIntervalSince1970: 1_800_000_001),
            metadata: [
                "authority": AgentRoomsConversationPersistence.testRoomAuthority,
                "schema_version": "1",
            ],
            createdAt: Date(timeIntervalSince1970: 1_800_000_001)
        ), intent: .historicalReplay)
        AgentRoomsSelectionStore(defaults: defaults, key: "selection").saveSelectedRoomID(roomID.uuidString)
        AgentRoomsDraftStore(defaults: defaults, key: "drafts").saveDraft(
            "Recovered before hosted view",
            roomID: roomID.uuidString
        )
    }

    func reopen() throws {
        database.close()
        database = CiderDatabase()
        try database.open(at: databaseURL)
    }

    func makeProductionComposition() throws -> CompatibilityComposition {
        let repository = ConversationRepository(database: database)
        let assignments = AgentRoomsAgentAssignmentService(repository: repository)
        let participants = AgentRoomsParticipantService(repository: repository)
        let transport = CompatibilityTransport()
        let transcription = CompatibilityTranscriptionService()
        let session = AgentRoomsSessionModel.production(
            transport: transport,
            database: database,
            vaultRoot: root.appendingPathComponent("vault", isDirectory: true),
            selectionStore: AgentRoomsSelectionStore(defaults: defaults, key: "selection"),
            draftStore: AgentRoomsDraftStore(defaults: defaults, key: "drafts"),
            transcriptionService: transcription,
            didMaterializeAttachments: {}
        )
        return .init(
            repository: repository,
            assignments: assignments,
            participants: participants,
            session: session,
            transport: transport,
            transcription: transcription
        )
    }

    func writeTextAttachment() throws -> URL {
        let url = root.appendingPathComponent("compatibility.txt")
        try Data("local attachment draft".utf8).write(to: url)
        return url
    }

    func cleanup() {
        database.close()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }
}

@MainActor
private final class CompatibilityTranscriptionService: CiderTranscriptionServicing {
    let provider = TranscriptionProviderMetadata(
        id: "compatibility-transcription",
        adapterVersion: "1",
        execution: .onDevice,
        supportedInputs: [.liveMicrophone],
        allowsNetworkFallback: false
    )
    let authorization: ConversationTranscriptionAuthorization = .authorized
    let readiness: ConversationTranscriptionReadiness = .ready
    private var handler: (@MainActor @Sendable (ConversationTranscriptionEvent) -> Void)?
    private var request: LiveTranscriptionRequest?

    func authorization(for input: TranscriptionInputKind) -> TranscriptionAuthorization { authorization }
    func readiness(for input: TranscriptionInputKind) -> TranscriptionReadiness { readiness }
    func requestAuthorization(for input: TranscriptionInputKind) async -> TranscriptionAuthorization { authorization }
    func startLive(
        _ request: LiveTranscriptionRequest,
        onEvent: @escaping @MainActor @Sendable (ConversationTranscriptionEvent) -> Void
    ) throws {
        self.request = request
        handler = onEvent
    }
    func stopLive() {}
    func cancelLive() { handler = nil }
    func transcribeStoredAudio(_ request: StoredAudioTranscriptionRequest) async -> TranscriptionResult {
        .failure(.init(code: .unsupportedInput, message: "Not used by this compatibility fixture."))
    }
    func cancelStoredAudio() {}
    func emit(_ event: ConversationTranscriptionEvent) { handler?(event) }
    func emitFinal(_ text: String) {
        guard let request else { return }
        emit(.final(.init(
            text: text,
            isFinal: true,
            provenance: .init(
                provider: provider,
                source: request.source,
                locale: .init(identifier: "en_US"),
                timing: .init(
                    startedAt: Date(timeIntervalSince1970: 1),
                    completedAt: Date(timeIntervalSince1970: 2),
                    audioDuration: 1
                )
            )
        )))
    }
}

private actor CompatibilityTransport: HermesBridgeTransport {
    private let instanceID = UUID().uuidString.lowercased()
    private(set) var sendCount = 0
    private(set) var attachmentCount = 0

    func availability() async -> HermesBridgeAvailability { .apiRuns }
    func attachmentCapability() async -> ConversationAttachmentTransportCapability { .supported }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        try await send(
            text: text,
            state: state,
            existingMessages: existingMessages,
            attachments: [],
            onEvent: onEvent
        )
    }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        attachments: [ConversationAttachmentTransportPayload],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sendCount += 1
        attachmentCount = attachments.count
        let runID = "compatibility-\(instanceID)-run-\(sendCount)"
        let sessionID = "compatibility-\(instanceID)-session-\(sendCount)"
        let timestamp = Date(timeIntervalSince1970: 1_830_000_000 + Double(sendCount))
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        let reply = "Production composition reply \(sendCount)"
        await onEvent?(.runStarted(runID))
        await onEvent?(.messageDelta("Production composition "))
        await onEvent?(.reasoningAvailable("Checking shared composition"))
        await onEvent?(.toolStarted(name: "Safe intake", preview: "Reading accepted attachment"))
        await onEvent?(.toolCompleted(name: "Safe intake", isError: false))

        var finalState = state
        finalState.activeRuntimeSessionID = sessionID
        finalState.runtimeSessionLineage.append(sessionID)
        finalState.lastSyncedAt = timestamp
        finalState.lastSyncedMessageID = assistantSourceID
        finalState.lastSyncedTimestamp = timestamp
        finalState.lastImportedRuntimeSessionID = sessionID
        return HermesBridgeSendResult(completion: .init(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: existingMessages + [
                AIAssistantMessage(
                    role: .user,
                    content: text,
                    timestamp: timestamp,
                    sourceID: userSourceID,
                    sourceSessionID: sessionID,
                    sourceName: "Hermes"
                ),
                AIAssistantMessage(
                    role: .assistant,
                    content: reply,
                    timestamp: timestamp,
                    sourceID: assistantSourceID,
                    sourceSessionID: sessionID,
                    sourceName: "Hermes"
                ),
            ],
            finalState: finalState,
            modelIdentity: "compatibility-production-composition",
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: userSourceID,
                assistantSourceID: assistantSourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            )
        ))
    }

    func stop(runID: String) async throws {}
    func currentSendCount() -> Int { sendCount }
    func lastAttachmentCount() -> Int { attachmentCount }
}
