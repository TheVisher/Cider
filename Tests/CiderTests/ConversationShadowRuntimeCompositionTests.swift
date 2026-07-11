import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Conversation Shadow Runtime Composition Tests", .serialized)
@MainActor
struct ConversationShadowRuntimeCompositionTests {
    @Test("AppDelegate composes only after an open database and only once")
    func appDelegateComposesAfterDatabaseOpenOnlyOnce() throws {
        let fixture = try Fixture(openDatabase: true)
        defer { fixture.remove() }
        let delegate = AppDelegate()
        var installed: [LegacyConversationPrimarySaveCoordinator?] = []

        delegate.composeDormantConversationShadowRuntime(
            database: fixture.database,
            vaultRootURL: fixture.root,
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            runtimeLogger: fixture.runtimeLogger,
            installCoordinator: { coordinator in
                installed.append(coordinator)
                return true
            }
        )
        let firstComposition = try #require(delegate.conversationShadowRuntimeComposition)
        delegate.composeDormantConversationShadowRuntime(
            database: fixture.database,
            vaultRootURL: fixture.root,
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            runtimeLogger: fixture.runtimeLogger,
            installCoordinator: { coordinator in
                installed.append(coordinator)
                return true
            }
        )

        #expect(firstComposition.database === fixture.database)
        #expect(firstComposition.database.isOpen)
        #expect(delegate.conversationShadowRuntimeComposition === firstComposition)
        #expect(installed.count == 1)
        #expect(installed[0] != nil)
        #expect(fixture.events.isEmpty)
    }

    @Test("Closed database fails closed without a coordinator")
    func closedDatabaseFailsClosed() throws {
        let fixture = try Fixture(openDatabase: false)
        defer { fixture.remove() }
        let delegate = AppDelegate()
        var installed: [LegacyConversationPrimarySaveCoordinator?] = []

        delegate.composeDormantConversationShadowRuntime(
            database: fixture.database,
            vaultRootURL: fixture.root,
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            runtimeLogger: fixture.runtimeLogger,
            installCoordinator: { coordinator in
                installed.append(coordinator)
                return true
            }
        )

        #expect(delegate.conversationShadowRuntimeComposition == nil)
        #expect(installed.count == 1)
        #expect(installed[0] == nil)
        #expect(fixture.events == [.startupFailure(.databaseClosed)])
    }

    @Test(
        "Invalid health fails closed without a coordinator",
        arguments: [InvalidHealthFixture.corrupt, .unsupported, .overBound]
    )
    func invalidHealthFailsClosed(kind: InvalidHealthFixture) throws {
        let fixture = try Fixture(openDatabase: true)
        defer { fixture.remove() }
        let healthURL = try fixture.writeInvalidHealth(kind)
        let healthBefore = try Data(contentsOf: healthURL)
        let legacyBefore = try fixture.legacyManifest()
        let coreBefore = try fixture.coreSnapshot()
        var installed: [LegacyConversationPrimarySaveCoordinator?] = []
        let delegate = AppDelegate()

        delegate.composeDormantConversationShadowRuntime(
            database: fixture.database,
            vaultRootURL: fixture.root,
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            runtimeLogger: fixture.runtimeLogger,
            installCoordinator: { coordinator in
                installed.append(coordinator)
                return true
            }
        )

        #expect(delegate.conversationShadowRuntimeComposition == nil)
        #expect(installed.count == 1)
        #expect(installed[0] == nil)
        #expect(fixture.events == [.startupFailure(.healthInitializationFailed)])
        #expect(try Data(contentsOf: healthURL) == healthBefore)
        #expect(try fixture.legacyManifest() == legacyBefore)
        #expect(try fixture.coreSnapshot() == coreBefore)
    }

    @Test(
        "Existing unresolved health loads without mutation or reconciliation",
        arguments: ["cider.conversation-shadow-health.v1", "cider.conversation-shadow-health.v2"]
    )
    func existingHealthLoadsWithoutMutation(formatVersion: String) throws {
        let fixture = try Fixture(openDatabase: true)
        defer { fixture.remove() }
        let healthURL = try fixture.writeUnresolvedHealth(formatVersion: formatVersion)
        let healthBytesBefore = try Data(contentsOf: healthURL)
        let legacyBefore = try fixture.legacyManifest()
        let coreBefore = try fixture.coreSnapshot()
        let delegate = AppDelegate()

        delegate.composeDormantConversationShadowRuntime(
            database: fixture.database,
            vaultRootURL: fixture.root,
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            runtimeLogger: fixture.runtimeLogger,
            installCoordinator: { $0 != nil }
        )

        let composition = try #require(delegate.conversationShadowRuntimeComposition)
        let snapshot = composition.healthStore.snapshot()
        #expect(snapshot.unresolved.count == 1)
        #expect(snapshot.unresolved[0].status == .repairNeeded)
        #expect(snapshot.unresolved[0].occurrenceCount == 3)
        #expect(snapshot.resolvedHistory.isEmpty)
        #expect(try Data(contentsOf: healthURL) == healthBytesBefore)
        #expect(try fixture.legacyManifest() == legacyBefore)
        #expect(try fixture.coreSnapshot() == coreBefore)
        #expect(composition.receiptReporter.receipts.isEmpty)
        #expect(fixture.events.isEmpty)
        #expect(fixture.writerCheckpoints.isEmpty)
    }

    @Test("Composition is dormant and preserves legacy and conversation-core state")
    func constructionHasNoPersistenceOperations() throws {
        let fixture = try Fixture(openDatabase: true, seedCore: true)
        defer { fixture.remove() }
        let legacyBefore = try fixture.legacyManifest()
        let coreBefore = try fixture.coreSnapshot()
        let delegate = AppDelegate()

        delegate.composeDormantConversationShadowRuntime(
            database: fixture.database,
            vaultRootURL: fixture.root,
            registry: fixture.registry,
            conversationStorage: fixture.storage,
            runtimeLogger: fixture.runtimeLogger,
            writerCheckpoint: { fixture.writerCheckpoints.append($0) },
            installCoordinator: { $0 != nil }
        )

        let composition = try #require(delegate.conversationShadowRuntimeComposition)
        #expect(try fixture.legacyManifest() == legacyBefore)
        #expect(try fixture.coreSnapshot() == coreBefore)
        #expect(fixture.writerCheckpoints.isEmpty)
        #expect(composition.healthStore.snapshot().unresolved.isEmpty)
        #expect(composition.healthStore.snapshot().resolvedHistory.isEmpty)
        #expect(composition.receiptReporter.receipts.isEmpty)
        #expect(fixture.events.isEmpty)
    }

    @Test("Shared bootstrap installs dependency before first initialization and never mutates late")
    func sharedBootstrapIsDeterministic() throws {
        final class Box {
            let dependency: String?
            init(dependency: String?) { self.dependency = dependency }
        }
        var factoryInputs: [String?] = []
        let bootstrap = SharedInstanceBootstrap<String, Box> { dependency in
            factoryInputs.append(dependency)
            return Box(dependency: dependency)
        }

        #expect(bootstrap.install("coordinator"))
        let first = bootstrap.shared
        let second = bootstrap.shared
        #expect(first === second)
        #expect(first.dependency == "coordinator")
        #expect(factoryInputs.count == 1)
        #expect(!bootstrap.install("late mutation"))
        #expect(bootstrap.shared.dependency == "coordinator")

        let failClosed = SharedInstanceBootstrap<String, Box> { Box(dependency: $0) }
        #expect(failClosed.install(nil))
        #expect(failClosed.shared.dependency == nil)
    }

    @Test("ViewModel only stores the dormant coordinator and has no activation call")
    func viewModelHasStorageOnlySeam() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewModelSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/ViewModels/AIAssistantViewModel.swift"),
            encoding: .utf8
        )
        let compositionSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/App/ConversationShadowRuntimeComposition.swift"),
            encoding: .utf8
        )
        let appDelegateSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Sources/Cider/App/AppDelegate.swift"),
            encoding: .utf8
        )
        let dormantSources = [viewModelSource, compositionSource, appDelegateSource]

        #expect(viewModelSource.contains("dormantConversationShadowCoordinator"))
        #expect(!dormantSources.contains { $0.contains("dormantConversationShadowCoordinator.save") })
        #expect(!dormantSources.contains { $0.contains("ConversationShadowSafetyGate(") })
        #expect(!dormantSources.contains { $0.contains("writeVerifiedSequentialCompletedSnapshot(") })
        #expect(!dormantSources.contains { $0.contains("reconcileAfterExactRetry(") })
        #expect(!compositionSource.contains("coordinator.save("))
    }

    @Test("Receipt logging is bounded, content-free, and severity-mapped")
    func receiptLoggingContract() {
        let cases: [(ConversationShadowActivationReceipt, ConversationShadowLogSeverity)] = [
            (Self.receipt(shadowStatus: .synchronized), .info),
            (Self.receipt(shadowStatus: .resolved), .info),
            (Self.receipt(registryCommitted: false), .error),
            (Self.receipt(jsonlStatus: .failed), .error),
            (Self.receipt(shadowCode: .gateBlocked), .error),
            (Self.receipt(shadowCode: .registryMismatch), .error),
            (Self.receipt(shadowCode: .primaryWriteFailed), .error),
            (Self.receipt(shadowCode: .shadowRepositoryFailed), .error),
            (Self.receipt(shadowCode: .shadowParityFailed), .error),
            (Self.receipt(shadowCode: .diagnosticStoreSaturated), .fault),
            (Self.receipt(shadowStatus: .outcomeUnknown), .fault),
            (Self.receipt(shadowStatus: .reserved), .fault),
        ]

        for (receipt, expectedSeverity) in cases {
            var events: [ConversationShadowLogEvent] = []
            let runtimeLogger = ConversationShadowRuntimeLogger { events.append($0) }
            let reporter = ConversationShadowActivationReceiptReporter(runtimeLogger: runtimeLogger)
            reporter.report(receipt)
            #expect(events.count == 1)
            #expect(events[0].severity == expectedSeverity)
        }

        let secret = "private-message-body"
        var events: [ConversationShadowLogEvent] = []
        let runtimeLogger = ConversationShadowRuntimeLogger { events.append($0) }
        let reporter = ConversationShadowActivationReceiptReporter(runtimeLogger: runtimeLogger)
        reporter.report(Self.receipt(
            planFingerprint: String(repeating: "f", count: 400) + secret,
            terminalSourceNamespace: String(repeating: "n", count: 400) + secret,
            terminalSourceID: String(repeating: "i", count: 400) + secret,
            shadowStatus: .synchronized
        ))
        let event = events[0]
        #expect(event.planFingerprint?.count == ConversationShadowActivationReceiptReporter.maximumIdentityCharacters)
        #expect(event.terminalSourceNamespace?.count == ConversationShadowActivationReceiptReporter.maximumIdentityCharacters)
        #expect(event.terminalSourceID?.count == ConversationShadowActivationReceiptReporter.maximumIdentityCharacters)
        #expect(!event.boundedFields.joined(separator: " ").contains(secret))
        #expect(!event.logLine.contains(secret))

        events.removeAll()
        runtimeLogger.logStartupFailure(.healthInitializationFailed)
        #expect(events == [.startupFailure(.healthInitializationFailed)])
        #expect(events[0].severity == .fault)
    }

    private static func receipt(
        registryCommitted: Bool = true,
        jsonlStatus: LegacyConversationWriteStatus = .committed,
        planFingerprint: String? = "fingerprint",
        terminalSourceNamespace: String? = "hermes.runs.v1",
        terminalSourceID: String? = "run-1:assistant",
        shadowStatus: ConversationShadowHealthStatus? = nil,
        shadowCode: ConversationShadowDiagnosticCode? = nil
    ) -> ConversationShadowActivationReceipt {
        ConversationShadowActivationReceipt(
            generationID: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            conversationID: UUID(uuidString: "20000000-0000-4000-8000-000000000002")!,
            registryCommitted: registryCommitted,
            jsonlStatus: jsonlStatus,
            shadowCorrelationID: UUID(uuidString: "30000000-0000-4000-8000-000000000003"),
            shadowStatus: shadowStatus,
            shadowCode: shadowCode,
            planFingerprint: planFingerprint,
            messageCount: 2,
            terminalSourceNamespace: terminalSourceNamespace,
            terminalSourceID: terminalSourceID
        )
    }
}

enum InvalidHealthFixture: CaseIterable, CustomTestStringConvertible {
    case corrupt
    case unsupported
    case overBound

    var testDescription: String { String(describing: self) }
}

@MainActor
private final class Fixture {
    private final class EventRecorder {
        var events: [ConversationShadowLogEvent] = []
    }

    struct LegacyManifest: Equatable {
        let registry: [String: Data]
        let conversations: [String: Data]
        let registryHashes: [String: String]
        let conversationHashes: [String: String]
    }

    struct CoreSnapshot: Equatable {
        let room: ConversationRoom?
        let bindings: [ConversationRuntimeBinding]
        let turns: [ConversationTurn]
        let messages: [ConversationMessage]
    }

    let root: URL
    let registryDirectory: URL
    let conversationDirectory: URL
    let database: CiderDatabase
    let registry: CiderAgentChatRegistry
    let storage: AIConversationStorage
    let runtimeLogger: ConversationShadowRuntimeLogger
    private let eventRecorder: EventRecorder
    var events: [ConversationShadowLogEvent] { eventRecorder.events }
    var writerCheckpoints: [ConversationShadowWriterCheckpoint] = []
    private let seededRoomID = UUID(uuidString: "40000000-0000-4000-8000-000000000004")!

    init(openDatabase: Bool, seedCore: Bool = false) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-shadow-composition-\(UUID().uuidString)", isDirectory: true)
        registryDirectory = root.appendingPathComponent("registry", isDirectory: true)
        conversationDirectory = root.appendingPathComponent("conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
        try Data("registry-sentinel".utf8).write(to: registryDirectory.appendingPathComponent("sentinel.bin"))
        try Data("conversation-sentinel".utf8).write(to: conversationDirectory.appendingPathComponent("sentinel.bin"))
        database = CiderDatabase()
        if openDatabase {
            let databaseURL = root.appendingPathComponent(".cider/cider.db")
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try database.open(at: databaseURL)
        }
        registry = CiderAgentChatRegistry(storageDirectoryURL: registryDirectory)
        storage = AIConversationStorage(conversationsDirectoryURL: conversationDirectory)
        let eventRecorder = EventRecorder()
        self.eventRecorder = eventRecorder
        runtimeLogger = ConversationShadowRuntimeLogger { eventRecorder.events.append($0) }

        if seedCore {
            let repository = ConversationRepository(database: database)
            let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
            let room = try repository.createRoom(.init(
                id: seededRoomID,
                stableKey: "seeded.room",
                title: "Seeded Room",
                metadata: ["fixture": "true"],
                createdAt: createdAt,
                updatedAt: createdAt
            ))
            let binding = try repository.upsertRuntimeBinding(.init(
                roomID: room.id,
                runtimeID: "hermes",
                transportID: "fixture",
                sourceNamespace: "fixture.binding.v1",
                externalSessionID: "session-1",
                createdAt: createdAt,
                updatedAt: createdAt
            ))
            let turn = try repository.beginTurn(.init(
                roomID: room.id,
                runtimeBindingID: binding.id,
                source: .init(namespace: "hermes.runs.v1", id: "run-1"),
                status: .unknown,
                createdAt: createdAt
            ))
            _ = try repository.upsertMessage(.init(
                roomID: room.id,
                turnID: turn.id,
                runtimeBindingID: binding.id,
                role: "assistant",
                contentText: "seeded content",
                source: .init(namespace: "hermes.runs.v1", id: "run-1:assistant"),
                createdAt: createdAt
            ), intent: .historicalReplay)
        }
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }

    func legacyManifest() throws -> LegacyManifest {
        let registry = try manifest(registryDirectory)
        let conversations = try manifest(conversationDirectory)
        return LegacyManifest(
            registry: registry,
            conversations: conversations,
            registryHashes: hashes(registry),
            conversationHashes: hashes(conversations)
        )
    }

    func coreSnapshot() throws -> CoreSnapshot {
        guard database.isOpen else {
            return CoreSnapshot(room: nil, bindings: [], turns: [], messages: [])
        }
        let repository = ConversationRepository(database: database)
        return CoreSnapshot(
            room: try repository.room(id: seededRoomID),
            bindings: try repository.bindings(roomID: seededRoomID),
            turns: try repository.turns(roomID: seededRoomID),
            messages: try repository.messages(roomID: seededRoomID)
        )
    }

    func writeInvalidHealth(_ kind: InvalidHealthFixture) throws -> URL {
        let healthURL = try healthFileURL()
        switch kind {
        case .corrupt:
            try Data("not-json".utf8).write(to: healthURL)
        case .unsupported:
            let object = healthObject(formatVersion: "cider.conversation-shadow-health.v999", unresolved: [])
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: healthURL)
        case .overBound:
            let records = (0...ConversationShadowHealthStore.maximumUnresolved).map { index in
                healthRecord(correlationID: deterministicUUID(index))
            }
            let object = healthObject(formatVersion: "cider.conversation-shadow-health.v2", unresolved: records)
            try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: healthURL)
        }
        return healthURL
    }

    func writeUnresolvedHealth(formatVersion: String) throws -> URL {
        let healthURL = try healthFileURL()
        let object = healthObject(
            formatVersion: formatVersion,
            unresolved: [healthRecord(correlationID: "50000000-0000-4000-8000-000000000005")]
        )
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: healthURL)
        return healthURL
    }

    private func healthFileURL() throws -> URL {
        let directory = root.appendingPathComponent(".cider/diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("conversation-shadow-health.json")
    }

    private func healthObject(formatVersion: String, unresolved: [[String: Any]]) -> [String: Any] {
        [
            "formatVersion": formatVersion,
            "unresolved": unresolved,
            "resolvedHistory": [],
            "aggregateEvidence": [:],
        ]
    }

    private func healthRecord(correlationID: String) -> [String: Any] {
        [
            "correlationID": correlationID,
            "conversationID": "60000000-0000-4000-8000-000000000006",
            "generationID": "70000000-0000-4000-8000-000000000007",
            "status": "repair_needed",
            "code": "shadow_repository_failed",
            "jsonlHash": "jsonl-hash",
            "registryHash": "registry-hash",
            "semanticFingerprint": NSNull(),
            "firstSeenAt": "2026-07-11T18:00:00Z",
            "lastSeenAt": "2026-07-11T18:01:00Z",
            "occurrenceCount": 3,
            "errorDetail": "bounded diagnostic",
        ]
    }

    private func deterministicUUID(_ value: Int) -> String {
        String(format: "80000000-0000-4000-8000-%012d", value)
    }

    private func manifest(_ directory: URL) throws -> [String: Data] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try Dictionary(uniqueKeysWithValues: urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            return (url.lastPathComponent, try Data(contentsOf: url))
        })
    }

    private func hashes(_ manifest: [String: Data]) -> [String: String] {
        manifest.mapValues { data in
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }
}
