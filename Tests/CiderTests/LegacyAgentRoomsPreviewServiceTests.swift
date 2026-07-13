import CryptoKit
import XCTest
@testable import Cider

@MainActor
final class LegacyAgentRoomsPreviewServiceTests: XCTestCase {
    private let roomID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    func testStrictReadyPlanMapsLegacyAuthorityPhysicalOrderRepeatedContentAndNoClaims() throws {
        let firstID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let secondID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        var preview = readyPreview()
        preview.plan.messages = [
            message(id: firstID, sequence: 1, role: "user", content: "repeat"),
            message(id: secondID, sequence: 2, role: "assistant", content: "repeat"),
        ]
        preview.counts.plannedMessages = 2

        let state = LegacyAgentRoomsPreviewService(loadPreview: { preview }, now: { self.timestamp }).loadWorkspace()
        guard case .loaded(let authority, let rooms, let selectedRoomID) = state else {
            return XCTFail("Expected loaded legacy preview")
        }

        XCTAssertEqual(authority, .legacyAuthoritativePreview)
        XCTAssertEqual(selectedRoomID, roomID.uuidString)
        let room = try XCTUnwrap(rooms.first)
        XCTAssertEqual(room.transcript.messages.map(\.id), [firstID.uuidString, secondID.uuidString])
        XCTAssertEqual(room.transcript.messages.map(\.body), ["repeat", "repeat"])
        XCTAssertEqual(room.transcript.messages.map(\.role), [.human, .agent])
        XCTAssertEqual(room.transcript.runtimeLabel, "Hermes")
        XCTAssertNil(room.transcript.receipt)
        XCTAssertNil(room.transcript.link)
        XCTAssertNil(room.transcript.futureArtifact)
    }

    func testMalformedOrInconsistentReadyPlanFailsClosedWithoutPartialRooms() {
        var preview = readyPreview()
        preview.plan.messages = [
            message(id: UUID(), sequence: 1, role: "user", content: "must not leak", attachmentCount: "1")
        ]
        preview.counts.plannedMessages = 1
        preview.counts.attachmentBearingMessages = 1

        XCTAssertEqual(
            LegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace(),
            .blocked(
                authority: .legacyAuthoritativePreview,
                message: LegacyAgentRoomsPreviewService.blockedMessage
            )
        )
    }

    func testThrownReadIsSanitizedRetryableFailureAndStrictEmptyIsOrdinaryEmpty() {
        let privateEvidence = "SQL /private/live-vault.db bearer secret"
        let failed = LegacyAgentRoomsPreviewService(loadPreview: {
            throw NSError(domain: privateEvidence, code: 1)
        }).loadWorkspace()
        XCTAssertEqual(
            failed,
            .failed(
                authority: .legacyAuthoritativePreview,
                message: LegacyAgentRoomsPreviewService.unavailableMessage
            )
        )
        XCTAssertFalse(String(describing: failed).contains(privateEvidence))

        var empty = readyPreview()
        empty.state = .empty
        empty.plan = .init()
        empty.counts = .init()
        XCTAssertEqual(
            LegacyAgentRoomsPreviewService(loadPreview: { empty }).loadWorkspace(),
            .empty(authority: .legacyAuthoritativePreview)
        )
    }

    func testArbiterNeverCallsLegacyForCanonicalLoadedFailureOrLoading() {
        let canonicalStates: [AgentRoomsWorkspaceState] = [
            .loaded(
                authority: .canonicalIncomplete,
                rooms: [mappedRoom()],
                selectedRoomID: roomID.uuidString
            ),
            .failed(authority: .canonicalIncomplete, message: "sanitized"),
            .loading(authority: .canonicalIncomplete),
        ]

        for canonical in canonicalStates {
            var legacyCalls = 0
            let loaded = AgentRoomsWorkspaceLoader(
                loadCanonical: { canonical },
                loadLegacy: {
                    legacyCalls += 1
                    return .empty(authority: .legacyAuthoritativePreview)
                }
            ).loadWorkspace()
            XCTAssertEqual(loaded, canonical)
            XCTAssertEqual(legacyCalls, 0)
        }
    }

    func testArbiterCallsLegacyExactlyOnceOnlyForCanonicalEmptyAndNeverMixesRooms() {
        var legacyCalls = 0
        let legacy = AgentRoomsWorkspaceState.loaded(
            authority: .legacyAuthoritativePreview,
            rooms: [mappedRoom(title: "Legacy")],
            selectedRoomID: roomID.uuidString
        )
        let result = AgentRoomsWorkspaceLoader(
            loadCanonical: { .empty(authority: .canonicalIncomplete) },
            loadLegacy: {
                legacyCalls += 1
                return legacy
            }
        ).loadWorkspace()

        XCTAssertEqual(result, legacy)
        XCTAssertEqual(legacyCalls, 1)
        guard case .loaded(let authority, let rooms, _) = result else {
            return XCTFail("Expected legacy result")
        }
        XCTAssertEqual(authority, .legacyAuthoritativePreview)
        XCTAssertEqual(rooms.map(\.title), ["Legacy"])
    }

    func testAdapterSourceHasStrictReadOnlyBoundaryAndProductionCompositionUsesStrictArbiter() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let adapter = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Services/Conversation/LegacyAgentRoomsPreviewService.swift"),
            encoding: .utf8
        )
        for prohibited in [
            "AIConversationStorage", "CiderAgentChatRegistry", "createRoom(", "upsert", "transition",
            "PrimarySaveCoordinator", "ShadowWriter", "Reconciler", "HealthStore", "backfill(",
            "deleteRoom", "archiveRoom", "BridgeTransport",
        ] {
            XCTAssertFalse(adapter.localizedCaseInsensitiveContains(prohibited), "Adapter must exclude \(prohibited)")
        }

        let composition = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"),
            encoding: .utf8
        )
        let roomsBlock = try XCTUnwrap(composition.range(of: "case .agentRooms:").flatMap { start in
            composition.range(of: "case .aiAssistant:", range: start.upperBound..<composition.endIndex)
                .map { composition[start.lowerBound..<$0.lowerBound] }
        })
        for required in [
            "AgentRoomsReadService", "LegacyConversationEligiblePreviewService",
            "EligibleLegacyAgentRoomsPreviewService",
            "AgentRoomsWorkspaceLoader", "StoragePaths.legacyConversationPreviewDirectories",
            "ConversationRepositoryParityReader",
        ] {
            XCTAssertTrue(roomsBlock.contains(required), "Missing production composition: \(required)")
        }
        XCTAssertNil(roomsBlock.range(of: #"\bLegacyAgentRoomsPreviewService\("#, options: .regularExpression))
        for prohibited in ["AIConversationStorage", "CiderAgentChatRegistry", "Fixture", "tolerant", "createDirectory"] {
            XCTAssertFalse(roomsBlock.contains(prohibited))
        }
    }

    func testTemporaryProductionArbitrationMatrixIsStrictLabeledAndImmutableAcrossRetry() throws {
        let readyFixture = try StrictRoomsFixture()
        defer { readyFixture.remove() }
        try readyFixture.writeRoom(
            id: roomID,
            stableKey: "legacy.integration",
            title: "Legacy Integration",
            updatedAt: timestamp,
            messages: [
                .init(
                    id: UUID(),
                    role: .user,
                    content: "temporary fixture only",
                    timestamp: timestamp,
                    sourceID: "hermes:integration:user",
                    sourceSessionID: "session-active",
                    sourceName: "Hermes"
                )
            ]
        )
        let inputsBefore = try readyFixture.inputSnapshot()
        let databaseBefore = try readyFixture.databaseSnapshot()
        var legacyCalls = 0
        let loadLegacy = {
            legacyCalls += 1
            return readyFixture.adapter(now: self.timestamp).loadWorkspace()
        }
        let canonicalRoom = mappedRoom(title: "Canonical")

        for canonical in [
            AgentRoomsWorkspaceState.loaded(
                authority: .canonicalIncomplete,
                rooms: [canonicalRoom],
                selectedRoomID: canonicalRoom.id
            ),
            .failed(authority: .canonicalIncomplete, message: AgentRoomsReadService.unavailableMessage),
            .loading(authority: .canonicalIncomplete),
            .blocked(authority: .canonicalIncomplete, message: "canonical blocker"),
        ] {
            XCTAssertEqual(
                AgentRoomsWorkspaceLoader(loadCanonical: { canonical }, loadLegacy: loadLegacy).loadWorkspace(),
                canonical
            )
        }
        XCTAssertEqual(legacyCalls, 0, "Canonical non-empty terminal states must not touch legacy paths")

        for expectedCallCount in 1...2 {
            let result = AgentRoomsWorkspaceLoader(
                loadCanonical: { .empty(authority: .canonicalIncomplete) },
                loadLegacy: loadLegacy
            ).loadWorkspace()
            guard case .loaded(let authority, let rooms, let selection) = result else {
                return XCTFail("Expected strict legacy workspace")
            }
            XCTAssertEqual(authority, .legacyAuthoritativePreview)
            XCTAssertEqual(rooms.map(\.title), ["Legacy Integration"])
            XCTAssertEqual(selection, roomID.uuidString)
            XCTAssertEqual(legacyCalls, expectedCallCount)
            XCTAssertEqual(try readyFixture.inputSnapshot(), inputsBefore)
            XCTAssertEqual(try readyFixture.databaseSnapshot(), databaseBefore)
        }

        let blockedFixture = try StrictRoomsFixture()
        defer { blockedFixture.remove() }
        try blockedFixture.writeRoom(
            id: roomID,
            stableKey: "legacy.blocked",
            title: "Registry Title",
            updatedAt: timestamp,
            metadataTitle: "Mismatched Title",
            messages: [
                .init(id: UUID(), role: .user, content: "must not leak", timestamp: timestamp, sourceID: "hermes:blocked:user", sourceSessionID: "session-active", sourceName: "Hermes")
            ]
        )
        let blockedInputsBefore = try blockedFixture.inputSnapshot()
        let blockedDatabaseBefore = try blockedFixture.databaseSnapshot()
        for _ in 0..<2 {
            let result = AgentRoomsWorkspaceLoader(
                loadCanonical: { .empty(authority: .canonicalIncomplete) },
                loadLegacy: { blockedFixture.adapter(now: self.timestamp).loadWorkspace() }
            ).loadWorkspace()
            XCTAssertEqual(
                result,
                .blocked(authority: .legacyAuthoritativePreview, message: LegacyAgentRoomsPreviewService.blockedMessage)
            )
            XCTAssertFalse(String(describing: result).contains("must not leak"))
            XCTAssertEqual(try blockedFixture.inputSnapshot(), blockedInputsBefore)
            XCTAssertEqual(try blockedFixture.databaseSnapshot(), blockedDatabaseBefore)
        }

        let emptyFixture = try StrictRoomsFixture()
        defer { emptyFixture.remove() }
        let emptyInputsBefore = try emptyFixture.inputSnapshot()
        let emptyDatabaseBefore = try emptyFixture.databaseSnapshot()
        for _ in 0..<2 {
            XCTAssertEqual(
                AgentRoomsWorkspaceLoader(
                    loadCanonical: { .empty(authority: .canonicalIncomplete) },
                    loadLegacy: { emptyFixture.adapter(now: self.timestamp).loadWorkspace() }
                ).loadWorkspace(),
                .empty(authority: .legacyAuthoritativePreview)
            )
            XCTAssertEqual(try emptyFixture.inputSnapshot(), emptyInputsBefore)
            XCTAssertEqual(try emptyFixture.databaseSnapshot(), emptyDatabaseBefore)
        }
    }

    func testViewCarriesPersistentCanonicalAndLegacyVisibleAndAccessibilityProvenance() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/AgentRooms/AgentRoomsWorkspaceView.swift"),
            encoding: .utf8
        )
        for required in [
            "Cider-owned",
            "Durable local conversations with calm room controls.",
            "Cider-owned canonical transcript",
            "Read-only · Legacy authoritative",
            "Noncanonical preview of current legacy conversation history",
            "Legacy-authoritative preview · Not imported",
            "legacy-authoritative noncanonical preview, not imported",
            "Legacy preview blocked",
            "Messaging disabled. Live messaging remains in the Hermes panel.",
            "Button(action: onOpenLiveChat)",
            ".onMoveCommand",
        ] {
            XCTAssertTrue(source.contains(required), "Missing source-aware view contract: \(required)")
        }
    }

    func testSafetyFactsDoNotAuthorizeOrBlockAnOtherwiseStrictReadyPreview() {
        var preview = readyPreview()
        preview.safeForBackfill = false
        preview.safeForShadowWrites = false
        guard case .loaded(let authority, _, _) = LegacyAgentRoomsPreviewService(
            loadPreview: { preview }
        ).loadWorkspace() else { return XCTFail("Safety facts must not become authorization") }
        XCTAssertEqual(authority, .legacyAuthoritativePreview)
    }

    func testReadOnlyAndChangedAreMandatoryFactsEvenForReadyPlans() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for override in [("readOnly", false), ("changed", true)] {
            var object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: encoder.encode(readyPreview())) as? [String: Any]
            )
            object[override.0] = override.1
            let decoded = try decoder.decode(
                LegacyConversationImportPreview.self,
                from: JSONSerialization.data(withJSONObject: object)
            )
            XCTAssertEqual(
                LegacyAgentRoomsPreviewService(loadPreview: { decoded }).loadWorkspace(),
                .blocked(authority: .legacyAuthoritativePreview, message: LegacyAgentRoomsPreviewService.blockedMessage)
            )
        }
    }

    func testInconsistentPlansBlockMissingBindingsDuplicatesGraphErrorsCountsAndConflicts() {
        var cases: [LegacyConversationImportPreview] = []

        var missingBinding = readyPreview()
        missingBinding.plan.bindings = []
        missingBinding.counts.plannedBindings = 0
        cases.append(missingBinding)

        var duplicateRoom = readyPreview()
        duplicateRoom.plan.rooms.append(duplicateRoom.plan.rooms[0])
        duplicateRoom.counts.plannedRooms = 2
        cases.append(duplicateRoom)

        var duplicateSource = readyPreview()
        var first = message(id: UUID(), sequence: 1, role: "user", content: "first")
        var second = message(id: UUID(), sequence: 2, role: "assistant", content: "second")
        second.source = first.source
        duplicateSource.plan.messages = [first, second]
        duplicateSource.counts.plannedMessages = 2
        cases.append(duplicateSource)

        var missingParent = readyPreview()
        first.parentMessageID = UUID()
        missingParent.plan.messages = [first]
        missingParent.counts.plannedMessages = 1
        cases.append(missingParent)

        var cycle = readyPreview()
        let cycleFirstID = UUID()
        let cycleSecondID = UUID()
        var cycleFirst = message(id: cycleFirstID, sequence: 1, role: "user", content: "first")
        var cycleSecond = message(id: cycleSecondID, sequence: 2, role: "assistant", content: "second")
        cycleFirst.parentMessageID = cycleSecondID
        cycleSecond.parentMessageID = cycleFirstID
        cycle.plan.messages = [cycleFirst, cycleSecond]
        cycle.counts.plannedMessages = 2
        cases.append(cycle)

        var mismatchedCount = readyPreview()
        mismatchedCount.counts.plannedMessages = 1
        cases.append(mismatchedCount)

        var conflict = readyPreview()
        conflict.plan.rooms[0].disposition = .conflict
        cases.append(conflict)

        for preview in cases {
            XCTAssertEqual(
                LegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace(),
                .blocked(authority: .legacyAuthoritativePreview, message: LegacyAgentRoomsPreviewService.blockedMessage)
            )
        }
    }

    func testActiveBindingWinsThenNewestMappedBindingAndUnknownHistoricalTurnsNeverCreateReceipt() throws {
        var preview = readyPreview()
        var olderActive = preview.plan.bindings[0]
        olderActive.runtimeID = "codex"
        olderActive.updatedAt = timestamp
        var newerInactive = olderActive
        newerInactive.id = UUID()
        newerInactive.runtimeID = "hermes"
        newerInactive.state = .inactive
        newerInactive.updatedAt = timestamp.addingTimeInterval(10)
        preview.plan.bindings = [olderActive, newerInactive]
        preview.counts.plannedBindings = 2
        let unknownTurn = LegacyConversationTurnPlanRecord(
            id: UUID(),
            roomID: roomID,
            sequence: 1,
            runtimeBindingID: olderActive.id,
            source: .init(namespace: "hermes.runs.v1", id: "private-run"),
            status: .unknown,
            metadata: [:],
            createdAt: timestamp,
            startedAt: nil,
            completedAt: timestamp,
            updatedAt: timestamp,
            disposition: .plannedInsert
        )
        preview.plan.turns = [unknownTurn]
        preview.counts.plannedTurns = 1

        guard case .loaded(_, let activeRooms, _) = LegacyAgentRoomsPreviewService(
            loadPreview: { preview }
        ).loadWorkspace() else { return XCTFail("Expected active binding preview") }
        XCTAssertEqual(activeRooms[0].transcript.runtimeLabel, "Codex")
        XCTAssertNil(activeRooms[0].transcript.receipt)

        preview.plan.bindings[0].state = .inactive
        guard case .loaded(_, let newestRooms, _) = LegacyAgentRoomsPreviewService(
            loadPreview: { preview }
        ).loadWorkspace() else { return XCTFail("Expected newest binding preview") }
        XCTAssertEqual(newestRooms[0].transcript.runtimeLabel, "Hermes")
        XCTAssertNil(newestRooms[0].transcript.receipt)
        XCTAssertFalse(String(describing: newestRooms[0]).contains("private-run"))
    }

    func testTemporaryTwoRoomStrictFixtureMapsAndRemainsByteAndDatabaseImmutableAcrossRetry() throws {
        let fixture = try StrictRoomsFixture()
        defer { fixture.remove() }
        let olderID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let newerID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
        let repeatedIDs = [
            UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
            UUID(uuidString: "dddddddd-dddd-4ddd-8ddd-dddddddddddd")!,
        ]
        try fixture.writeRoom(
            id: olderID,
            stableKey: "legacy.older",
            title: "Older",
            updatedAt: timestamp,
            messages: [
                .init(id: repeatedIDs[0], role: .user, content: "repeat", timestamp: timestamp, sourceID: "hermes:older:user", sourceSessionID: "session-active", sourceName: "Hermes"),
                .init(id: repeatedIDs[1], role: .assistant, content: "repeat", timestamp: timestamp, sourceID: "hermes:older:assistant", sourceSessionID: "session-active", sourceName: "Hermes"),
            ]
        )
        try fixture.writeRoom(
            id: newerID,
            stableKey: "legacy.newer",
            title: "Newer",
            updatedAt: timestamp.addingTimeInterval(60),
            messages: [
                .init(id: UUID(), role: .user, content: "newest room", timestamp: timestamp, sourceID: "hermes:newer:user", sourceSessionID: "session-active", sourceName: "Hermes")
            ]
        )
        let inputsBefore = try fixture.inputSnapshot()
        let databaseBefore = try fixture.databaseSnapshot()

        for _ in 0..<2 {
            let state = fixture.adapter(now: timestamp.addingTimeInterval(120)).loadWorkspace()
            guard case .loaded(let authority, let rooms, let selectedRoomID) = state else {
                return XCTFail("Expected strict temporary fixture to load")
            }
            XCTAssertEqual(authority, .legacyAuthoritativePreview)
            XCTAssertEqual(rooms.map(\.id), [newerID.uuidString, olderID.uuidString])
            XCTAssertEqual(selectedRoomID, newerID.uuidString)
            XCTAssertEqual(rooms[1].transcript.messages.map(\.id), repeatedIDs.map(\.uuidString))
            XCTAssertEqual(rooms[1].transcript.messages.map(\.body), ["repeat", "repeat"])
            XCTAssertEqual(try fixture.inputSnapshot(), inputsBefore)
            XCTAssertEqual(try fixture.databaseSnapshot(), databaseBefore)
        }
    }

    func testTemporaryRegistryMetadataMismatchReplacesWholeWorkspaceWithSanitizedBlockedState() throws {
        let fixture = try StrictRoomsFixture()
        defer { fixture.remove() }
        try fixture.writeRoom(
            id: roomID,
            stableKey: "legacy.mismatch",
            title: "Registry Title",
            updatedAt: timestamp,
            metadataTitle: "Different JSONL Title",
            messages: [
                .init(id: UUID(), role: .user, content: "private partial content", timestamp: timestamp, sourceID: "hermes:mismatch:user", sourceSessionID: "session-active", sourceName: "Hermes")
            ]
        )
        let inputsBefore = try fixture.inputSnapshot()
        let databaseBefore = try fixture.databaseSnapshot()

        let state = fixture.adapter(now: timestamp).loadWorkspace()
        XCTAssertEqual(
            state,
            .blocked(authority: .legacyAuthoritativePreview, message: LegacyAgentRoomsPreviewService.blockedMessage)
        )
        XCTAssertFalse(String(describing: state).contains("private partial content"))
        XCTAssertFalse(String(describing: state).contains("Different JSONL Title"))
        XCTAssertEqual(try fixture.inputSnapshot(), inputsBefore)
        XCTAssertEqual(try fixture.databaseSnapshot(), databaseBefore)
    }

    func testAllStrictBlockerClassesReturnOneSanitizedWorkspaceWithoutPartialData() {
        let codes: [ConversationParityDiagnosticCode] = [
            .inputLimitExceeded, .unreadableInput, .malformedRegistryRecord, .malformedMetadataLine,
            .malformedMessageLine, .invalidMetadataType, .missingRegistryRecord, .missingConversationFile,
            .duplicateRoomID, .duplicateStableID, .duplicateConversationFile, .duplicateRuntimeSessionID,
            .duplicateMessageID, .invalidSourceIdentity, .conflictingSourceIdentity, .registryMetadataMismatch,
            .messageCountMismatch, .missingGraphReference, .graphCycle, .attachmentsUnsupported,
            .coreParityConflict,
        ]

        for code in codes {
            var preview = readyPreview()
            preview.state = .blocked
            preview.counts.blockingDiagnostics = 1
            preview.diagnosticSamples = [
                .init(code: code, severity: .blocker, location: "/private/secret", detail: "raw private detail")
            ]
            let result = LegacyAgentRoomsPreviewService(loadPreview: { preview }).loadWorkspace()
            XCTAssertEqual(
                result,
                .blocked(
                    authority: .legacyAuthoritativePreview,
                    message: LegacyAgentRoomsPreviewService.blockedMessage
                ),
                "Expected fail-closed result for \(code)"
            )
            XCTAssertFalse(String(describing: result).contains("/private/secret"))
            XCTAssertFalse(String(describing: result).contains("raw private detail"))
        }
    }

    func testDeterministicRoomAndMessageCapsActiveFilteringStableTiesAndNeutralUnsupportedCopy() throws {
        var preview = readyPreview()
        let roomIDs = (0..<22).map { index in
            UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
        }
        preview.plan.rooms = roomIDs.enumerated().map { index, id in
            var room = preview.plan.rooms[0]
            room.id = id
            room.stableKey = "room-\(index)"
            room.title = "Room \(index)"
            room.lifecycleState = index == 21 ? .archived : .active
            return room
        }
        preview.plan.bindings = preview.plan.rooms.map { room in
            var binding = preview.plan.bindings[0]
            binding.id = UUID()
            binding.roomID = room.id
            return binding
        }
        let firstRoomID = roomIDs[0]
        let firstBindingID = preview.plan.bindings[0].id
        preview.plan.messages = (1...105).map { sequence in
            var value = message(
                id: UUID(),
                sequence: Int64(sequence),
                role: sequence == 105 ? "tool" : (sequence.isMultiple(of: 2) ? "assistant" : "user"),
                content: "message-\(sequence)"
            )
            value.roomID = firstRoomID
            value.runtimeBindingID = firstBindingID
            value.source = .init(namespace: "legacy.message-source.v1", id: "source-\(sequence)")
            return value
        }
        preview.counts.plannedRooms = preview.plan.rooms.count
        preview.counts.plannedBindings = preview.plan.bindings.count
        preview.counts.plannedMessages = preview.plan.messages.count

        let state = LegacyAgentRoomsPreviewService(loadPreview: { preview }, now: { self.timestamp }).loadWorkspace()
        guard case .loaded(_, let rooms, _) = state else { return XCTFail("Expected capped rooms") }
        XCTAssertEqual(rooms.count, 20)
        XCTAssertEqual(rooms.map(\.id), roomIDs.prefix(20).map(\.uuidString))
        let first = try XCTUnwrap(rooms.first)
        XCTAssertEqual(first.transcript.messages.count, 99)
        XCTAssertEqual(first.transcript.messages.first?.body, "message-6")
        XCTAssertEqual(first.transcript.messages.last?.body, "message-104")
        XCTAssertFalse(first.transcript.messages.contains { $0.body == "message-105" })

        var unsupported = readyPreview()
        unsupported.plan.messages = [message(id: UUID(), sequence: 1, role: "system", content: "hidden")]
        unsupported.counts.plannedMessages = 1
        guard case .loaded(_, let unsupportedRooms, _) = LegacyAgentRoomsPreviewService(
            loadPreview: { unsupported }
        ).loadWorkspace() else { return XCTFail("Expected room with neutral transcript") }
        XCTAssertEqual(unsupportedRooms[0].preview, LegacyAgentRoomsPreviewService.fallbackPreview)
        XCTAssertTrue(unsupportedRooms[0].transcript.messages.isEmpty)
    }

    private func readyPreview() -> LegacyConversationImportPreview {
        let room = LegacyConversationRoomPlanRecord(
            id: roomID,
            stableKey: "legacy.room",
            title: "Legacy Room",
            kind: "chat",
            lifecycleState: .active,
            nextTurnSequence: 1,
            nextMessageSequence: 1,
            metadata: [:],
            createdAt: timestamp,
            updatedAt: timestamp,
            archivedAt: nil,
            disposition: .plannedInsert
        )
        let binding = LegacyConversationBindingPlanRecord(
            id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!,
            roomID: roomID,
            parentBindingID: nil,
            runtimeID: "hermes",
            transportID: "legacy",
            sourceNamespace: "legacy.runtime-binding.v1.hermes",
            externalSessionID: "private-session",
            state: .active,
            cursorMessageID: nil,
            cursorTimestamp: nil,
            metadata: [:],
            createdAt: timestamp,
            updatedAt: timestamp,
            disposition: .plannedInsert
        )
        var counts = LegacyConversationImportCounts()
        counts.registryFiles = 1
        counts.conversationFiles = 1
        counts.inputRooms = 1
        counts.plannedRooms = 1
        counts.plannedBindings = 1
        return LegacyConversationImportPreview(
            state: .ready,
            safeForBackfill: true,
            safeForShadowWrites: true,
            inputs: [],
            counts: counts,
            diagnosticCounts: [:],
            diagnosticSamples: [],
            plan: .init(rooms: [room], bindings: [binding], turns: [], messages: [])
        )
    }

    private func message(
        id: UUID,
        sequence: Int64,
        role: String,
        content: String,
        attachmentCount: String = "0"
    ) -> LegacyConversationMessagePlanRecord {
        LegacyConversationMessagePlanRecord(
            id: id,
            roomID: roomID,
            turnID: nil,
            runtimeBindingID: UUID(uuidString: "44444444-4444-4444-8444-444444444444"),
            parentMessageID: nil,
            sequence: sequence,
            role: role,
            contentText: content,
            status: .complete,
            finishReason: nil,
            source: .init(namespace: "legacy.message-source.v1", id: "source-\(sequence)"),
            sourceCreatedAt: timestamp,
            metadata: ["attachmentCount": attachmentCount],
            createdAt: timestamp,
            updatedAt: timestamp,
            disposition: .plannedInsert
        )
    }

    private func mappedRoom(title: String = "Canonical") -> AgentRoom {
        AgentRoom(
            id: roomID.uuidString,
            title: title,
            preview: "Preview",
            updatedAt: timestamp,
            relativeTime: "Now",
            transcript: .init(runtimeLabel: "Hermes", messages: [], link: nil, receipt: nil, futureArtifact: nil)
        )
    }
}

@MainActor
private final class StrictRoomsFixture {
    let root: URL
    let registryDirectory: URL
    let conversationDirectory: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    private let encoder: JSONEncoder

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-legacy-rooms-preview-\(UUID().uuidString)", isDirectory: true)
        registryDirectory = root.appendingPathComponent("registry", isDirectory: true)
        conversationDirectory = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
        database = CiderDatabase()
        try database.open(at: root.appendingPathComponent("canonical.db"))
        repository = ConversationRepository(database: database)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func adapter(now: Date) -> LegacyAgentRoomsPreviewService {
        LegacyAgentRoomsPreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: ConversationRepositoryParityReader(repository: repository),
            now: { now }
        )
    }

    func writeRoom(
        id: UUID,
        stableKey: String,
        title: String,
        updatedAt: Date,
        metadataTitle: String? = nil,
        messages: [AIAssistantMessage]
    ) throws {
        let record = CiderAgentChatRecord(
            stableID: stableKey,
            title: title,
            hermesTitle: title,
            kind: "chat",
            conversationID: id,
            runtimeID: "hermes",
            activeRuntimeSessionID: "session-active",
            runtimeSessionLineage: ["session-active"],
            lastSyncedMessageID: "cursor",
            lastSyncedTimestamp: updatedAt,
            lastImportedRuntimeSessionID: "session-active",
            scope: "temporary-test",
            archived: false,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            defaultInCider: false
        )
        try encoder.encode(record).write(
            to: registryDirectory.appendingPathComponent("\(stableKey).json"),
            options: .atomic
        )

        var metadata = AIConversationMeta(id: id, title: metadataTitle ?? title, model: "hermes")
        metadata.updated = updatedAt
        metadata.messageCount = messages.count
        metadata.runtimeID = "hermes"
        metadata.activeRuntimeSessionID = "session-active"
        metadata.runtimeSessionLineage = ["session-active"]
        metadata.runtimeSource = "temporary-test"
        metadata.runtimeLastSyncedAt = updatedAt
        metadata.runtimeLastSyncedMessageID = "cursor"
        metadata.runtimeLastSyncedTimestamp = updatedAt
        metadata.runtimeLastImportedSessionID = "session-active"
        let lines = try ([metadata] as [AIConversationMeta]).map(json) + messages.map(json)
        try (lines.joined(separator: "\n") + "\n").write(
            to: conversationDirectory.appendingPathComponent("\(id.uuidString).jsonl"),
            atomically: true,
            encoding: .utf8
        )
    }

    func inputSnapshot() throws -> String {
        var hasher = SHA256()
        for directory in [registryDirectory, conversationDirectory] {
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            for name in names {
                let url = directory.appendingPathComponent(name)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                hasher.update(data: Data(name.utf8))
                hasher.update(data: try Data(contentsOf: url))
                if let size = attributes[.size] as? NSNumber {
                    hasher.update(data: Data(size.stringValue.utf8))
                }
                if let modified = attributes[.modificationDate] as? Date {
                    hasher.update(data: Data(String(format: "%.9f", modified.timeIntervalSince1970).utf8))
                }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    func databaseSnapshot() throws -> [Int64] {
        let statement = try database.prepare("""
            SELECT
              (SELECT COUNT(*) FROM conversation_rooms),
              (SELECT COUNT(*) FROM conversation_runtime_bindings),
              (SELECT COUNT(*) FROM conversation_turns),
              (SELECT COUNT(*) FROM conversation_messages),
              COALESCE((SELECT SUM(next_turn_sequence) FROM conversation_rooms), 0),
              COALESCE((SELECT SUM(next_message_sequence) FROM conversation_rooms), 0);
            """)
        guard try statement.step() else { return [] }
        return (0..<6).map { statement.int64(at: Int32($0)) }
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
