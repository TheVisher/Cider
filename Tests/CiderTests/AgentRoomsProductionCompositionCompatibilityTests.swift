import AppKit
import SwiftUI
import XCTest
@testable import Cider

final class AgentRoomsProductionCompositionCompatibilityTests: XCTestCase {
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
    private(set) var sendCount = 0
    func availability() async -> HermesBridgeAvailability { .apiRuns }
    func attachmentCapability() async -> ConversationAttachmentTransportCapability { .supported }
    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        sendCount += 1
        throw CancellationError()
    }
    func stop(runID: String) async throws {}
    func currentSendCount() -> Int { sendCount }
}
