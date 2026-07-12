import AppKit
import Foundation
import Testing
@testable import Cider

@MainActor
struct AgentRoomsTestChatPersistenceTests {
    @Test("two completed turns survive repository reopen and continue one Hermes session")
    func completedTurnsRestoreAndContinueSameSession() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-test-chat-\(UUID().uuidString).db")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: url)
        let firstTransport = DurableSessionTransport()
        let first = AgentRoomsLiveChatModel(
            transport: firstTransport,
            turnCoordinator: HermesTurnCoordinator(),
            persistence: AgentRoomsTestChatPersistence(
                database: firstDatabase,
                repository: ConversationRepository(database: firstDatabase)
            )
        )
        await first.startTestChat()
        let roomID = try #require(first.testRoom?.id)
        await first.send("turn one", selectedRoomID: roomID)
        await first.send("turn two", selectedRoomID: roomID)
        #expect(first.testRoom?.transcript.messages.map(\.body) == [
            "turn one", "answer one", "turn two", "answer two",
        ])
        firstDatabase.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: url)
        defer { reopenedDatabase.close() }
        let continuationTransport = DurableSessionTransport()
        let restored = AgentRoomsLiveChatModel(
            transport: continuationTransport,
            turnCoordinator: HermesTurnCoordinator(),
            persistence: AgentRoomsTestChatPersistence(
                database: reopenedDatabase,
                repository: ConversationRepository(database: reopenedDatabase)
            )
        )

        #expect(restored.restoreDurableTestChat())
        #expect(restored.testRoom?.id == roomID)
        #expect(restored.testRoom?.transcript.messages.map(\.body) == [
            "turn one", "answer one", "turn two", "answer two",
        ])
        #expect(restored.testRoom?.transcript.receipt?.runIdentity == "run-2")

        await restored.refreshTransportReadiness()
        await restored.send("turn three", selectedRoomID: roomID)
        #expect(await continuationTransport.observedConversationIDs() == [UUID(uuidString: roomID)!])
        #expect(await continuationTransport.observedSessionIDs() == ["durable-session"])
        #expect(restored.testRoom?.id == roomID)
        #expect(restored.testRoom?.transcript.messages.map(\.body) == [
            "turn one", "answer one", "turn two", "answer two", "turn three", "answer three",
        ])

        let repository = ConversationRepository(database: reopenedDatabase)
        #expect(try repository.rooms(lifecycle: .active, limit: 20).filter {
            $0.stableKey == AgentRoomsTestChatPersistence.stableRoomKey
        }.count == 1)
        #expect(try repository.turns(roomID: UUID(uuidString: roomID)!).count == 3)
        #expect(try repository.bindings(roomID: UUID(uuidString: roomID)!).map(\.externalSessionID) == ["durable-session"])
        #expect(try reopenedDatabase.integrityCheck().isHealthy)
    }

    @Test("cancelled failed partial and mismatched completions leave no canonical room")
    func ineligibleCompletionsFailClosedBeforeWrite() throws {
        try withPersistence { database, repository, persistence in
            let roomID = UUID()
            let cases: [HermesRunCompletionEnvelope] = [
                completion(roomID: roomID, status: .cancelled),
                completion(roomID: roomID, status: .failed),
                completion(roomID: roomID, synchronized: false),
                completion(roomID: UUID()),
            ]
            for envelope in cases {
                #expect(throws: AgentRoomsTestChatPersistenceError.self) {
                    try persistence.persist(envelope, expectedText: "hello", expectedConversationID: roomID)
                }
            }
            let room = try repository.room(stableKey: AgentRoomsTestChatPersistence.stableRoomKey)
            let counts = try conversationCounts(database)
            let integrity = try database.integrityCheck()
            #expect(room == nil)
            #expect(counts == [0, 0, 0, 0])
            #expect(integrity.isHealthy)
        }
    }

    @Test("corrupt canonical rows fail closed instead of restoring partial history")
    func corruptHistoryFailsClosed() throws {
        try withPersistence { database, repository, persistence in
            let roomID = UUID()
            try persistence.persist(completion(roomID: roomID), expectedText: "hello", expectedConversationID: roomID)
            try database.runSQL("UPDATE conversation_messages SET status = 'streaming' WHERE role = 'assistant';")

            #expect(throws: AgentRoomsTestChatPersistenceError.self) {
                try persistence.restore()
            }
            let workspace = AgentRoomsReadService(repository: repository).loadWorkspace()
            guard case .empty = workspace else {
                Issue.record("Corrupt reserved Test Chat must not fall through to the generic Rooms reader")
                return
            }
            let integrity = try database.integrityCheck()
            #expect(integrity.isHealthy)
        }
    }

    @Test("legacy-authoritative stable-key collision is never activated or overwritten")
    func legacyAuthorityFailsClosed() throws {
        try withPersistence { database, repository, persistence in
            let legacy = try repository.createRoom(.init(
                stableKey: AgentRoomsTestChatPersistence.stableRoomKey,
                title: "Cider Test Chat",
                kind: "chat",
                metadata: ["authority": "legacy-authoritative"],
                createdAt: Date(timeIntervalSince1970: 100)
            ))
            #expect(throws: AgentRoomsTestChatPersistenceError.self) {
                try persistence.restore()
            }
            #expect(throws: AgentRoomsTestChatPersistenceError.self) {
                try persistence.persist(completion(roomID: legacy.id), expectedText: "hello", expectedConversationID: legacy.id)
            }
            let persistedLegacy = try repository.room(id: legacy.id)
            let turns = try repository.turns(roomID: legacy.id)
            let integrity = try database.integrityCheck()
            #expect(persistedLegacy?.metadata["authority"] == "legacy-authoritative")
            #expect(turns.isEmpty)
            #expect(integrity.isHealthy)
        }
    }

    @Test("source-backed Cider receipt survives canonical reload with its Open route")
    func sourceBackedReceiptSurvivesReload() throws {
        try withPersistence { _, _, persistence in
            let roomID = UUID()
            let reference = HermesCiderReference(
                kind: "task",
                id: "367ec2",
                title: "Persist Cider Test Chat",
                boardID: "2afee0",
                projectID: nil,
                artifactType: nil,
                source: "cider",
                sourceRef: "kanban_card:2afee0/367ec2"
            )
            try persistence.persist(
                completion(roomID: roomID, references: [reference]),
                expectedText: "hello",
                expectedConversationID: roomID
            )
            let model = AgentRoomsLiveChatModel(
                transport: DurableSessionTransport(),
                turnCoordinator: HermesTurnCoordinator(),
                persistence: persistence
            )
            #expect(model.restoreDurableTestChat())
            let receipt = try #require(model.testRoom?.transcript.receipt?.objectReceipt)
            #expect(receipt.title == "Persist Cider Test Chat")
            #expect(receipt.openRoute == .card(boardID: "2afee0", cardID: "367ec2"))
            #expect(model.testRoom?.transcript.receipt?.sourceIdentity == "Hermes Runs API")
            #expect(model.testRoom?.transcript.receipt?.runIdentity == "run-safety")
        }
    }

    @Test("canonical saved-bookmark receipt restores its verified local thumbnail after repository reopen")
    func canonicalSavedBookmarkThumbnailSurvivesRepositoryReopen() async throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-test-chat-bookmark-\(UUID().uuidString).db")
        let cacheRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-test-chat-bookmark-cache-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
            try? FileManager.default.removeItem(at: cacheRoot)
        }

        let bookmarkID = UUID(uuidString: "81000000-0000-4000-8000-000000000001")!
        let bookmarkURL = URL(string: "https://chromeindustries.com/products/cohesive-2-0-38l-pack?variant=43962733953084")!
        let relativePath = ".thumbnails/\(bookmarkID.uuidString).png"
        let thumbnailURL = cacheRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: thumbnailURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try thumbnailPNGData().write(to: thumbnailURL)
        let modifiedAt = Date(timeIntervalSince1970: 1_805_000_000)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: thumbnailURL.path)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Cohesive 2.0 38L Pack",
            urlString: bookmarkURL.absoluteString,
            thumbnailRemoteURLString: "https://cdn.example.com/remote-only-must-not-render.png",
            thumbnailRelativePath: relativePath,
            metadataUpdatedAt: modifiedAt
        )

        let firstDatabase = CiderDatabase()
        try firstDatabase.open(at: databaseURL)
        try AgentRoomsTestChatPersistence(
            database: firstDatabase,
            repository: ConversationRepository(database: firstDatabase)
        ).persist(
            completion(
                roomID: UUID(uuidString: "81000000-0000-4000-8000-000000000002")!,
                assistantText: "Cohesive 2.0 38L Pack:\n\n\(bookmarkURL.absoluteString)"
            ),
            expectedText: "hello",
            expectedConversationID: UUID(uuidString: "81000000-0000-4000-8000-000000000002")!
        )
        firstDatabase.close()

        let reopenedDatabase = CiderDatabase()
        try reopenedDatabase.open(at: databaseURL)
        defer { reopenedDatabase.close() }
        let restored = AgentRoomsLiveChatModel(
            transport: DurableSessionTransport(),
            turnCoordinator: HermesTurnCoordinator(),
            savedBookmarkMatches: { candidate in
                guard VaultDuplicateAuditor.canonicalBookmarkURL(candidate.absoluteString)
                        == VaultDuplicateAuditor.canonicalBookmarkURL(bookmark.urlString),
                      let reference = AgentRoomsBookmarkReceiptThumbnail.reference(
                        for: bookmark,
                        cacheRoot: cacheRoot
                      )
                else { return [] }
                return [.init(id: bookmark.id, title: bookmark.title, url: bookmarkURL, thumbnail: reference)]
            },
            persistence: AgentRoomsTestChatPersistence(
                database: reopenedDatabase,
                repository: ConversationRepository(database: reopenedDatabase)
            )
        )

        #expect(restored.restoreDurableTestChat())
        let receipt = try #require(restored.testRoom?.transcript.receipt?.objectReceipt)
        let reference = try #require(receipt.bookmarkThumbnail)
        #expect(receipt.openRoute == .bookmark(bookmarkID: bookmarkID))
        #expect(reference.bookmarkID == bookmarkID)
        let loader = AgentRoomsBookmarkReceiptThumbnailLoader(cacheRoot: cacheRoot)
        await loader.load(
            reference,
            expectedBookmarkID: bookmarkID
        )
        #expect(loader.image != nil)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: reference.modifiedAt + 60)],
            ofItemAtPath: thumbnailURL.path
        )
        await loader.load(reference, expectedBookmarkID: bookmarkID)
        #expect(loader.image == nil)

        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: reference.modifiedAt)],
            ofItemAtPath: thumbnailURL.path
        )
        await loader.load(reference, expectedBookmarkID: UUID())
        #expect(loader.image == nil)

        try FileManager.default.removeItem(at: thumbnailURL)
        await loader.load(reference, expectedBookmarkID: bookmarkID)
        #expect(loader.image == nil)
    }

    private func withPersistence<T>(
        _ body: (CiderDatabase, ConversationRepository, AgentRoomsTestChatPersistence) throws -> T
    ) throws -> T {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-test-chat-safety-\(UUID().uuidString).db")
        let database = CiderDatabase()
        try database.open(at: url)
        defer {
            database.close()
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(atPath: url.path + "-wal")
            try? FileManager.default.removeItem(atPath: url.path + "-shm")
        }
        let repository = ConversationRepository(database: database)
        return try body(
            database,
            repository,
            AgentRoomsTestChatPersistence(database: database, repository: repository)
        )
    }

    private func conversationCounts(_ database: CiderDatabase) throws -> [Int64] {
        try [
            "conversation_rooms", "conversation_runtime_bindings", "conversation_turns", "conversation_messages",
        ].map { table in
            let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
            _ = try statement.step()
            return statement.int64(at: 0)
        }
    }

    private func completion(
        roomID: UUID,
        status: HermesRunTerminalStatus = .completed,
        synchronized: Bool = true,
        references: [HermesCiderReference] = [],
        assistantText: String = "world"
    ) -> HermesRunCompletionEnvelope {
        let runID = "run-safety"
        let sessionID = "session-safety"
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000)
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        return .init(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: status,
            observedFacts: .none,
            finalSessionSynchronizationComplete: synchronized,
            finalMessages: [
                .init(role: .user, content: "hello", timestamp: timestamp, sourceID: userSourceID, sourceSessionID: sessionID),
                .init(role: .assistant, content: assistantText, timestamp: timestamp, sourceID: assistantSourceID, sourceSessionID: sessionID),
            ],
            finalState: .init(
                conversationID: roomID,
                activeRuntimeSessionID: sessionID,
                runtimeSessionLineage: [sessionID],
                title: "Cider Test Chat",
                source: "cider-rooms-live-continuation",
                lastSyncedAt: timestamp,
                lastSyncedMessageID: assistantSourceID,
                lastSyncedTimestamp: timestamp,
                lastImportedRuntimeSessionID: sessionID
            ),
            modelIdentity: "gpt-test",
            terminalSourceEvidence: .init(
                reportedTerminalRunID: runID,
                userSourceID: userSourceID,
                assistantSourceID: assistantSourceID,
                userSourceSessionID: sessionID,
                assistantSourceSessionID: sessionID
            ),
            ciderReferences: references
        )
    }

    private func thumbnailPNGData() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 12,
            pixelsHigh: 8,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}

private actor DurableSessionTransport: HermesBridgeTransport {
    private var conversationIDs: [UUID] = []
    private var sessionIDs: [String] = []
    private var turnNumber = 0

    func availability() async -> HermesBridgeAvailability { .apiRuns }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage],
        onEvent: (@Sendable (HermesRunEvent) async -> Void)?
    ) async throws -> HermesBridgeSendResult {
        conversationIDs.append(state.conversationID)
        sessionIDs.append(state.activeRuntimeSessionID)
        turnNumber += 1
        let number = existingMessages.count / 2 + 1
        let runID = "run-\(number)"
        let sessionID = "durable-session"
        let timestamp = Date(timeIntervalSince1970: 1_750_000_000 + Double(number))
        let userSourceID = "hermes-run:\(runID):user"
        let assistantSourceID = "hermes-run:\(runID):assistant"
        let user = AIAssistantMessage(
            role: .user,
            content: text,
            timestamp: timestamp,
            sourceID: userSourceID,
            sourceSessionID: sessionID
        )
        let assistant = AIAssistantMessage(
            role: .assistant,
            content: "answer \(["zero", "one", "two", "three"][number])",
            timestamp: timestamp,
            sourceID: assistantSourceID,
            sourceSessionID: sessionID
        )
        await onEvent?(.runStarted(runID))
        await onEvent?(.messageDelta(assistant.content))
        return HermesBridgeSendResult(completion: .init(
            provenance: .hermesRunsAPI,
            runID: runID,
            terminalStatus: .completed,
            observedFacts: .none,
            finalSessionSynchronizationComplete: true,
            finalMessages: existingMessages + [user, assistant],
            finalState: .init(
                conversationID: state.conversationID,
                activeRuntimeSessionID: sessionID,
                runtimeSessionLineage: [sessionID],
                title: "Cider Test Chat",
                source: "cider-rooms-live-continuation",
                lastSyncedAt: timestamp,
                lastSyncedMessageID: assistantSourceID,
                lastSyncedTimestamp: timestamp,
                lastImportedRuntimeSessionID: sessionID
            ),
            modelIdentity: "gpt-test",
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
    func observedConversationIDs() -> [UUID] { conversationIDs }
    func observedSessionIDs() -> [String] { sessionIDs }
}
