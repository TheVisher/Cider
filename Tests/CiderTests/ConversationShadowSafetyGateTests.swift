import Foundation
import Testing
@testable import Cider

@Suite("Conversation Shadow Safety Gate Tests")
@MainActor
struct ConversationShadowSafetyGateTests {
    private struct ShadowFailure: Error {}

    private struct Fixture {
        let root: URL
        let registryDirectory: URL
        let conversationDirectory: URL
        let diagnosticsDirectory: URL
        let now: Date
        let generation: LegacyConversationWriteGeneration
        let registryReceipt: LegacyRegistryWriteReceipt
        let conversationReceipt: LegacyConversationWriteReceipt
    }

    @Test("matching exact-generation receipts expose immutable payload once")
    func matchingAndOneShot() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        let gate = makeGate(fixture, store: store)
        var calls = 0

        let first = gate.perform { payload in
            calls += 1
            #expect(payload.generation == fixture.generation)
            #expect(payload.conversation.messages.map(\.content) == ["repeat", "repeat"])
            return .synchronized
        }
        let second = gate.perform { _ in
            calls += 1
            return .synchronized
        }

        #expect(first.primaryReceipt == fixture.conversationReceipt)
        #expect(first.status == .synchronized)
        #expect(first.invokedShadowClosure)
        #expect(second.code == .gateBlocked)
        #expect(!second.invokedShadowClosure)
        #expect(calls == 1)
    }

    @Test("nonmatching generations are blocked")
    func mismatchedGeneration() throws {
        let fixture = try makeFixture(registryGeneration: .init(), conversationGeneration: .init())
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        var called = false

        let result = makeGate(fixture, store: store).perform { _ in called = true; return .synchronized }

        #expect(result.code == .gateBlocked)
        #expect(!called)
    }

    @Test("stale receipts are blocked")
    func staleReceipt() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        let gate = ConversationShadowSafetyGate(
            conversationReceipt: fixture.conversationReceipt,
            registryReceipt: fixture.registryReceipt,
            healthStore: store,
            maximumReceiptAge: 30,
            now: { fixture.now.addingTimeInterval(31) }
        )

        let result = gate.perform { _ in .synchronized }

        #expect(result.code == .gateStale)
        #expect(!result.invokedShadowClosure)
    }

    @Test("registry and JSONL metadata mismatch is blocked")
    func registryMismatch() throws {
        let fixture = try makeFixture(conversationTitle: "Not Cider")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)

        let result = makeGate(fixture, store: store).perform { _ in .synchronized }

        #expect(result.code == .registryMismatch)
        #expect(!result.invokedShadowClosure)
    }

    @Test("duplicate UUID and source identities are blocked without collapsing repeated content")
    func duplicateIdentityBlocked() throws {
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_799_999_900)
        let messages = [
            AIAssistantMessage(id: id, role: .user, content: "repeat", timestamp: date, sourceID: "hermes:session-a:one", sourceSessionID: "session-a"),
            AIAssistantMessage(id: id, role: .assistant, content: "repeat", timestamp: date, sourceID: "hermes:session-a:two", sourceSessionID: "session-a"),
        ]
        let fixture = try makeFixture(messages: messages)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)

        let result = makeGate(fixture, store: store).perform { _ in .synchronized }

        #expect(result.code == .gateBlocked)
        #expect(!result.invokedShadowClosure)
    }

    @Test("duplicate source identity is blocked even with distinct UUIDs")
    func duplicateSourceIdentityBlocked() throws {
        let date = Date(timeIntervalSince1970: 1_799_999_900)
        let messages = [
            AIAssistantMessage(id: UUID(), role: .user, content: "first", timestamp: date, sourceID: "hermes:session-a:same", sourceSessionID: "session-a"),
            AIAssistantMessage(id: UUID(), role: .user, content: "second", timestamp: date, sourceID: "hermes:session-a:same", sourceSessionID: "session-a"),
        ]
        let fixture = try makeFixture(messages: messages)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)

        let result = makeGate(fixture, store: store).perform { _ in .synchronized }

        #expect(result.code == .gateBlocked)
        #expect(!result.invokedShadowClosure)
    }

    @Test("attachment-bearing messages are blocked")
    func attachmentBlocked() throws {
        var messages = validMessages()
        messages[0].attachments = [.init(id: "image-1", kind: .image, mimeType: "image/png")]
        let fixture = try makeFixture(messages: messages)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)

        let result = makeGate(fixture, store: store).perform { _ in .synchronized }

        #expect(result.code == .gateBlocked)
        #expect(!result.invokedShadowClosure)
    }

    @Test("unsupported recognized source shape is blocked")
    func sourceShapeBlocked() throws {
        var messages = validMessages()
        messages[0].sourceID = "hermes-run:run-1:assistant"
        let fixture = try makeFixture(messages: messages)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)

        let result = makeGate(fixture, store: store).perform { _ in .synchronized }

        #expect(result.code == .gateBlocked)
        #expect(!result.invokedShadowClosure)
    }

    @Test("durable reservation exists before injected shadow closure")
    func reservationPrecedesClosure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)

        let result = makeGate(fixture, store: store).perform { _ in
            let restarted = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
            #expect(restarted.snapshot().unresolved.first?.status == .reserved)
            return .synchronized
        }

        #expect(result.status == .synchronized)
    }

    @Test("shadow failure preserves primary success and records durable repair state")
    func shadowFailureIsolationAndNoCoreMutation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let store = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        let registryBytes = try Data(contentsOf: fixture.registryDirectory.appendingPathComponent(fixture.registryReceipt.filename))
        let conversationBytes = try Data(contentsOf: fixture.conversationDirectory.appendingPathComponent(try #require(fixture.conversationReceipt.filename)))
        let dbURL = fixture.root.appendingPathComponent("isolated-v30.db")
        let database = CiderDatabase()
        try database.open(at: dbURL)
        defer { database.close() }
        let before = try conversationCounts(database)

        let result = makeGate(fixture, store: store).perform { _ in throw ShadowFailure() }

        #expect(result.primaryReceipt == fixture.conversationReceipt)
        #expect(result.primaryReceipt.isCommitted)
        #expect(result.status == .repairNeeded)
        #expect(result.code == .shadowRepositoryFailed)
        #expect(try conversationCounts(database) == before)
        #expect(try Data(contentsOf: fixture.registryDirectory.appendingPathComponent(fixture.registryReceipt.filename)) == registryBytes)
        #expect(try Data(contentsOf: fixture.conversationDirectory.appendingPathComponent(try #require(fixture.conversationReceipt.filename))) == conversationBytes)
        let restarted = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(restarted.snapshot().unresolved.first?.status == .repairNeeded)
        #expect(restarted.snapshot().unresolved.first?.code == .shadowRepositoryFailed)
    }

    @Test("reservation persistence failure prevents shadow closure")
    func reservationFailurePreventsClosure() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let persistence = ConversationShadowHealthStore.Persistence(
            writeAtomically: { _, _ in throw ShadowFailure() },
            read: { try Data(contentsOf: $0) }
        )
        let store = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.diagnosticsDirectory,
            persistence: persistence
        )
        var called = false

        let result = makeGate(fixture, store: store).perform { _ in called = true; return .synchronized }

        #expect(result.code == .gateBlocked)
        #expect(!called)
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("finalization failure persists outcome unknown and reconciliation resolves it")
    func outcomeUnknownReconciliation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var writeCount = 0
        let persistence = ConversationShadowHealthStore.Persistence(
            writeAtomically: { data, url in
                writeCount += 1
                if writeCount == 2 { throw ShadowFailure() }
                try data.write(to: url, options: .atomic)
            },
            read: { try Data(contentsOf: $0) }
        )
        let store = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.diagnosticsDirectory,
            persistence: persistence
        )

        let result = makeGate(fixture, store: store).perform { _ in .synchronized }

        #expect(result.status == .outcomeUnknown)
        let correlationID = try #require(result.correlationID)
        let restarted = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(restarted.snapshot().unresolved.first?.status == .outcomeUnknown)
        try restarted.resolve(correlationID: correlationID, detail: "Parity reconciled", at: fixture.now.addingTimeInterval(1))
        let reconciled = try ConversationShadowHealthStore(diagnosticsDirectoryURL: fixture.diagnosticsDirectory)
        #expect(reconciled.snapshot().unresolved.isEmpty)
        #expect(reconciled.snapshot().resolvedHistory.first?.status == .resolved)
    }

    @Test("health store bounds reads detail history saturation and survives restart")
    func boundedHealthStoreAndSaturation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let payload = try payload(fixture)
        let store = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.diagnosticsDirectory,
            maximumUnresolvedRecords: 2,
            maximumResolvedRecords: 2
        )
        let first = try store.reserve(payload: payload, at: fixture.now)
        let second = try store.reserve(payload: payload, at: fixture.now)
        try store.markRepairNeeded(
            correlationID: first.correlationID,
            code: .shadowRepositoryFailed,
            detail: String(repeating: "x", count: 2_000),
            at: fixture.now
        )
        #expect(store.snapshot().unresolved.first(where: { $0.correlationID == first.correlationID })?.errorDetail?.count == ConversationShadowHealthStore.maximumDetailCharacters)
        #expect(throws: ConversationShadowHealthStoreError.saturated) {
            try store.reserve(payload: payload, at: fixture.now)
        }
        #expect(store.snapshot().aggregateEvidence[ConversationShadowDiagnosticCode.diagnosticStoreSaturated.rawValue] == 1)
        #expect(store.snapshot(limit: 1_000).unresolved.count == 2)
        #expect(ConversationShadowHealthStore.maximumUnresolved == 1_000)
        #expect(ConversationShadowHealthStore.maximumResolvedHistory == 100)
        #expect(ConversationShadowHealthStore.maximumReadCount == 100)

        try store.resolve(correlationID: first.correlationID, at: fixture.now)
        try store.resolve(correlationID: second.correlationID, at: fixture.now)
        let third = try store.reserve(payload: payload, at: fixture.now)
        try store.resolve(correlationID: third.correlationID, at: fixture.now)
        #expect(store.snapshot().resolvedHistory.count == 2)
        let restarted = try ConversationShadowHealthStore(
            diagnosticsDirectoryURL: fixture.diagnosticsDirectory,
            maximumUnresolvedRecords: 2,
            maximumResolvedRecords: 2
        )
        #expect(restarted.snapshot().resolvedHistory.count == 2)
        #expect(restarted.snapshot().aggregateEvidence[ConversationShadowDiagnosticCode.diagnosticStoreSaturated.rawValue] == 1)
    }

    private func makeFixture(
        messages: [AIAssistantMessage]? = nil,
        conversationTitle: String = "Cider",
        registryGeneration: LegacyConversationWriteGeneration? = nil,
        conversationGeneration: LegacyConversationWriteGeneration? = nil
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid774-gate-\(UUID().uuidString)", isDirectory: true)
        let registryDirectory = root.appendingPathComponent("agent-chats", isDirectory: true)
        let conversationDirectory = root.appendingPathComponent("ai-conversations", isDirectory: true)
        let diagnosticsDirectory = root.appendingPathComponent("diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let sharedGeneration = LegacyConversationWriteGeneration()
        let registryGeneration = registryGeneration ?? sharedGeneration
        let conversationGeneration = conversationGeneration ?? sharedGeneration
        let registry = CiderAgentChatRegistry(storageDirectoryURL: registryDirectory, now: { date })
        let initialState = HermesConversationState(
            activeRuntimeSessionID: "session-a",
            runtimeSessionLineage: ["session-a"],
            title: "Cider",
            source: "telegram"
        )
        let record = try registry.createMainBrain(from: initialState)
        let registryReceipt = try registry.saveMainBrain(record, generation: registryGeneration)
        let state = HermesConversationState(
            conversationID: record.conversationID,
            activeRuntimeSessionID: record.activeRuntimeSessionID,
            runtimeSessionLineage: record.runtimeSessionLineage,
            title: record.title,
            source: "telegram",
            lastSyncedAt: nil,
            lastSyncedMessageID: record.lastSyncedMessageID,
            lastSyncedTimestamp: record.lastSyncedTimestamp,
            lastImportedRuntimeSessionID: record.lastImportedRuntimeSessionID
        )
        let storage = AIConversationStorage(conversationsDirectoryURL: conversationDirectory, now: { date })
        let conversationReceipt = storage.save(
            id: record.conversationID,
            title: conversationTitle,
            messages: messages ?? validMessages(),
            model: "hermes",
            hermesState: state,
            generation: conversationGeneration
        )
        return Fixture(
            root: root,
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            diagnosticsDirectory: diagnosticsDirectory,
            now: date,
            generation: sharedGeneration,
            registryReceipt: registryReceipt,
            conversationReceipt: conversationReceipt
        )
    }

    private func makeGate(
        _ fixture: Fixture,
        store: ConversationShadowHealthStore
    ) -> ConversationShadowSafetyGate {
        ConversationShadowSafetyGate(
            conversationReceipt: fixture.conversationReceipt,
            registryReceipt: fixture.registryReceipt,
            healthStore: store,
            now: { fixture.now }
        )
    }

    private func validMessages() -> [AIAssistantMessage] {
        let date = Date(timeIntervalSince1970: 1_799_999_900)
        return [
            AIAssistantMessage(
                id: UUID(),
                role: .user,
                content: "repeat",
                timestamp: date,
                sourceID: "hermes-run:run-1:user",
                sourceSessionID: "session-a"
            ),
            AIAssistantMessage(
                id: UUID(),
                role: .assistant,
                content: "repeat",
                timestamp: date,
                sourceID: "hermes-run:run-1:assistant",
                sourceSessionID: "session-a"
            ),
        ]
    }

    private func payload(_ fixture: Fixture) throws -> ConversationShadowPayload {
        ConversationShadowPayload(
            generation: fixture.registryReceipt.generation,
            registry: fixture.registryReceipt.snapshot,
            conversation: try #require(fixture.conversationReceipt.snapshot)
        )
    }

    private func conversationCounts(_ database: CiderDatabase) throws -> [Int] {
        try ["conversation_rooms", "conversation_runtime_bindings", "conversation_turns", "conversation_messages"].map { table in
            let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
            try statement.step()
            return statement.int(at: 0)
        }
    }
}
