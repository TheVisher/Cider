import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Legacy Conversation Import Preview Tests")
@MainActor
struct LegacyConversationImportPreviewTests {
    private let roomID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let firstMessageID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let secondMessageID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Preview is byte-stable, preserves physical order and repeated content, and never mutates inputs")
    func deterministicReadOnlyPreview() throws {
        try withFixture { fixture in
            try fixture.writeRegistry(record(roomID: roomID, lineage: ["session-parent", "session-active"]))
            try fixture.writeConversation(
                metadata: metadata(roomID: roomID, messageCount: 2),
                messages: [
                    message(id: firstMessageID, role: .user, content: "repeat", sourceID: "hermes-live:session-active:first"),
                    message(id: secondMessageID, role: .assistant, content: "repeat", sourceID: "hermes:session-active:second"),
                ]
            )
            let beforeFiles = try fixture.treeDigest()
            let beforeDatabase = try fixture.databaseSnapshot()

            let first = try fixture.service.preview()
            let second = try fixture.service.preview()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]

            #expect(try encoder.encode(first) == encoder.encode(second))
            #expect(first.readOnly)
            #expect(!first.changed)
            #expect(first.state == .ready)
            #expect(first.safeForBackfill)
            #expect(first.safeForShadowWrites)
            #expect(first.plan.messages.map(\.id) == [firstMessageID, secondMessageID])
            #expect(first.plan.messages.map(\.sequence) == [1, 2])
            #expect(first.plan.messages.map(\.contentText) == ["repeat", "repeat"])
            #expect(first.plan.messages.map(\.source?.namespace) == ["hermes.live.v1", "hermes.export.v1"])
            #expect(first.plan.messages[1].parentMessageID == firstMessageID)
            #expect(first.plan.messages[1].metadata["parentProvenance"] == "legacy-linear")
            #expect(first.plan.bindings.count == 2)
            #expect(first.plan.bindings[1].parentBindingID == first.plan.bindings[0].id)
            #expect(first.counts.inputMessages == 2)
            #expect(first.counts.physicalMessageRows == 2)
            #expect(first.counts.attachmentBearingMessages == 0)
            #expect(first.inputs.count == 2)
            #expect(try fixture.treeDigest() == beforeFiles)
            #expect(try fixture.databaseSnapshot() == beforeDatabase)
        }
    }

    @Test("Hermes run identities alone create deterministic unknown historical turns")
    func provenRunGrouping() throws {
        try withFixture { fixture in
            try fixture.writeRegistry(record(roomID: roomID, lineage: ["session-active"]))
            try fixture.writeConversation(
                metadata: metadata(roomID: roomID, messageCount: 3),
                messages: [
                    message(id: firstMessageID, role: .user, content: "q", sourceID: "hermes-run:run-7:user"),
                    message(id: secondMessageID, role: .assistant, content: "a", sourceID: "hermes-run:run-7:assistant"),
                    message(id: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!, role: .user, content: "local"),
                ]
            )

            let preview = try fixture.service.preview()
            #expect(preview.plan.turns.count == 1)
            #expect(preview.plan.turns[0].status == .unknown)
            #expect(preview.plan.turns[0].source == .init(namespace: "hermes.runs.v1", id: "run-7"))
            #expect(preview.plan.messages[0].turnID == preview.plan.turns[0].id)
            #expect(preview.plan.messages[1].turnID == preview.plan.turns[0].id)
            #expect(preview.plan.messages[2].turnID == nil)
        }
    }

    @Test("Unknown nonempty source styles retain exact provenance in the legacy namespace")
    func unknownSourceStyle() throws {
        try withFixture { fixture in
            try fixture.writeRegistry(record(roomID: roomID))
            try fixture.writeConversation(
                metadata: metadata(roomID: roomID, messageCount: 1),
                messages: [message(id: firstMessageID, role: .user, content: "x", sourceID: "future-source:opaque:value")]
            )

            let source = try #require(try fixture.service.preview().plan.messages.first?.source)
            #expect(source.namespace == "legacy.message-source.v1")
            #expect(source.id == "future-source:opaque:value")
        }
    }

    @Test("Malformed lines, metadata disagreement, duplicate identities, and attachments are blockers")
    func blockingDiagnostics() throws {
        try withFixture { fixture in
            try fixture.writeRegistry(record(roomID: roomID))
            try fixture.writeRawConversation(lines: [
                try fixture.json(metadata(roomID: roomID, messageCount: 4)),
                try fixture.json(message(id: firstMessageID, role: .user, content: "one", sourceID: "hermes:same:id")),
                try fixture.json(message(id: firstMessageID, role: .assistant, content: "duplicate", sourceID: "hermes-live:same:id")),
                "{ malformed",
                try fixture.json(message(
                    id: secondMessageID,
                    role: .assistant,
                    content: "attachment",
                    sourceID: "hermes:same:id",
                    attachments: [.init(id: "image", kind: .image)]
                )),
            ])

            let preview = try fixture.service.preview()
            #expect(preview.state == .blocked)
            #expect(!preview.safeForBackfill)
            #expect(!preview.safeForShadowWrites)
            #expect(preview.counts.blockingDiagnostics >= 4)
            let codes = Set(preview.diagnosticSamples.map(\.code))
            #expect(codes.contains(.malformedMessageLine))
            #expect(codes.contains(.duplicateMessageID))
            #expect(codes.contains(.conflictingSourceIdentity))
            #expect(codes.contains(.attachmentsUnsupported))
            #expect(codes.contains(.messageCountMismatch))
        }
    }

    @Test("Missing registry references and empty storage are never reported safe")
    func missingRegistryAndEmpty() throws {
        try withFixture { fixture in
            let empty = try fixture.service.preview()
            #expect(empty.state == .empty)
            #expect(!empty.safeForBackfill)
            #expect(!empty.safeForShadowWrites)

            try fixture.writeConversation(
                metadata: metadata(roomID: roomID, messageCount: 0),
                messages: []
            )
            let orphaned = try fixture.service.preview()
            #expect(orphaned.state == .blocked)
            #expect(orphaned.diagnosticSamples.contains { $0.code == .missingRegistryRecord })
        }
    }

    @Test("Malformed registry and metadata files plus duplicate room mappings block preview")
    func malformedHeadersAndDuplicateMappings() throws {
        try withFixture { fixture in
            try Data("not-json".utf8).write(to: fixture.registryDirectory.appendingPathComponent("bad.json"))
            try fixture.writeRegistry(record(roomID: roomID), filename: "first.json")
            try fixture.writeRegistry(record(roomID: roomID), filename: "second.json")
            try fixture.writeRawConversation(lines: ["not-json"], filename: "bad.jsonl")

            let preview = try fixture.service.preview()
            let codes = Set(preview.diagnosticSamples.map(\.code))
            #expect(preview.state == .blocked)
            #expect(codes.contains(.malformedRegistryRecord))
            #expect(codes.contains(.malformedMetadataLine))
            #expect(codes.contains(.duplicateRoomID))
            #expect(codes.contains(.duplicateStableID))
        }
    }

    @Test("Malformed Hermes run identity is retained but cannot invent a historical turn")
    func malformedRunIdentity() throws {
        try withFixture { fixture in
            try fixture.writeRegistry(record(roomID: roomID))
            try fixture.writeConversation(
                metadata: metadata(roomID: roomID, messageCount: 1),
                messages: [message(id: firstMessageID, role: .user, content: "x", sourceID: "hermes-run:run-7:assistant")]
            )

            let preview = try fixture.service.preview()
            #expect(preview.plan.turns.isEmpty)
            #expect(preview.plan.messages.first?.source == .init(namespace: "legacy.message-source.v1", id: "hermes-run:run-7:assistant"))
            #expect(preview.diagnosticSamples.contains { $0.code == .invalidSourceIdentity })
            #expect(!preview.safeForBackfill)
        }
    }

    @Test("Repository parity distinguishes planned inserts, equivalents, and conflicts without writes")
    func repositoryParity() throws {
        try withFixture { fixture in
            let record = record(roomID: roomID, lineage: [])
            let meta = metadata(roomID: roomID, messageCount: 1)
            let legacyMessage = message(id: firstMessageID, role: .user, content: "hello", sourceID: "hermes:session:first")
            try fixture.writeRegistry(record)
            try fixture.writeConversation(metadata: meta, messages: [legacyMessage])

            let missing = try fixture.service.preview()
            #expect(missing.plan.rooms.first?.disposition == .plannedInsert)
            #expect(missing.plan.messages.first?.disposition == .plannedInsert)

            let repository = fixture.repository
            _ = try repository.createRoom(.init(
                id: roomID,
                stableKey: record.stableID,
                title: record.title,
                kind: record.kind,
                metadata: missing.plan.rooms[0].metadata,
                createdAt: record.createdAt
            ))
            _ = try repository.upsertMessage(.init(
                id: firstMessageID,
                roomID: roomID,
                role: "user",
                contentText: "hello",
                source: .init(namespace: "hermes.export.v1", id: "session:first"),
                sourceCreatedAt: timestamp,
                metadata: missing.plan.messages[0].metadata,
                createdAt: timestamp
            ), intent: .historicalReplay)
            let before = try fixture.databaseSnapshot()

            let equivalent = try fixture.service.preview()
            #expect(equivalent.plan.rooms.first?.disposition == .equivalent)
            #expect(equivalent.plan.messages.first?.disposition == .equivalent)
            #expect(equivalent.counts.conflicts == 0)
            #expect(try fixture.databaseSnapshot() == before)

            try fixture.writeConversation(
                metadata: meta,
                messages: [message(id: firstMessageID, role: .user, content: "changed", sourceID: "hermes:session:first")]
            )
            let conflict = try fixture.service.preview()
            #expect(conflict.plan.messages.first?.disposition == .conflict)
            #expect(conflict.diagnosticSamples.contains { $0.code == .coreParityConflict })
            #expect(!conflict.safeForBackfill)
            #expect(try fixture.databaseSnapshot() == before)
        }
    }

    @Test("A thrown parity read leaves files and SQLite rows and sequences unchanged")
    func thrownPreviewDoesNotMutate() throws {
        try withFixture { fixture in
            try fixture.writeRegistry(record(roomID: roomID))
            try fixture.writeConversation(metadata: metadata(roomID: roomID, messageCount: 0), messages: [])
            let beforeFiles = try fixture.treeDigest()
            let beforeDatabase = try fixture.databaseSnapshot()
            let service = LegacyConversationImportPreviewService(
                registryDirectory: fixture.registryDirectory,
                conversationDirectory: fixture.conversationDirectory,
                parityReader: ThrowingParityReader()
            )

            #expect(throws: FixtureError.self) { try service.preview() }
            #expect(try fixture.treeDigest() == beforeFiles)
            #expect(try fixture.databaseSnapshot() == beforeDatabase)
        }
    }

    private func record(roomID: UUID, lineage: [String] = []) -> CiderAgentChatRecord {
        CiderAgentChatRecord(
            stableID: "cider.main",
            title: "Cider",
            hermesTitle: "Cider Runtime",
            kind: "main-brain",
            conversationID: roomID,
            runtimeID: "hermes",
            activeRuntimeSessionID: lineage.last ?? "",
            runtimeSessionLineage: lineage,
            lastSyncedMessageID: "cursor-message",
            lastSyncedTimestamp: timestamp,
            lastImportedRuntimeSessionID: lineage.first,
            scope: "main",
            archived: false,
            createdAt: timestamp,
            updatedAt: timestamp,
            defaultInCider: true
        )
    }

    private func metadata(roomID: UUID, messageCount: Int) -> AIConversationMeta {
        var value = AIConversationMeta(id: roomID, title: "Cider", model: "hermes")
        value.updated = timestamp
        value.messageCount = messageCount
        value.runtimeID = "hermes"
        value.activeRuntimeSessionID = "session-active"
        value.runtimeSessionLineage = ["session-parent", "session-active"]
        value.runtimeSource = "legacy-jsonl"
        value.runtimeLastSyncedAt = timestamp
        value.runtimeLastSyncedMessageID = "cursor-message"
        value.runtimeLastSyncedTimestamp = timestamp
        value.runtimeLastImportedSessionID = "session-parent"
        return value
    }

    private func message(
        id: UUID,
        role: AIAssistantMessage.Role,
        content: String,
        sourceID: String? = nil,
        attachments: [AIAssistantAttachment] = []
    ) -> AIAssistantMessage {
        .init(
            id: id,
            role: role,
            content: content,
            timestamp: timestamp,
            sourceID: sourceID,
            sourceSessionID: "session-active",
            sourceName: "Hermes",
            attachments: attachments
        )
    }

    private func withFixture(_ body: (Fixture) throws -> Void) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try body(fixture)
    }
}

private enum FixtureError: Error { case forced }

@MainActor
private struct ThrowingParityReader: ConversationCoreParityReading {
    func room(id: UUID) throws -> ConversationRoom? { throw FixtureError.forced }
    func room(stableKey: String) throws -> ConversationRoom? { throw FixtureError.forced }
    func bindings(roomID: UUID) throws -> [ConversationRuntimeBinding] { throw FixtureError.forced }
    func turn(id: UUID) throws -> ConversationTurn? { throw FixtureError.forced }
    func messages(roomID: UUID) throws -> [ConversationMessage] { throw FixtureError.forced }
}

@MainActor
private final class Fixture {
    let root: URL
    let registryDirectory: URL
    let conversationDirectory: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let service: LegacyConversationImportPreviewService
    private let encoder: JSONEncoder

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-import-preview-tests-\(UUID().uuidString)", isDirectory: true)
        registryDirectory = root.appendingPathComponent(".cider/agent-chats", isDirectory: true)
        conversationDirectory = root.appendingPathComponent(".cider/ai-conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: registryDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
        database = CiderDatabase()
        try database.open(at: root.appendingPathComponent("preview-v30.db"))
        repository = ConversationRepository(database: database)
        service = LegacyConversationImportPreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: ConversationRepositoryParityReader(repository: repository)
        )
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }

    func writeRegistry(_ record: CiderAgentChatRecord, filename: String = "cider.main.json") throws {
        try encoder.encode(record).write(to: registryDirectory.appendingPathComponent(filename))
    }

    func writeConversation(metadata: AIConversationMeta, messages: [AIAssistantMessage]) throws {
        try writeRawConversation(lines: [json(metadata)] + messages.map(json))
    }

    func writeRawConversation(lines: [String], filename: String = "conversation.jsonl") throws {
        try (lines.joined(separator: "\n") + "\n").write(
            to: conversationDirectory.appendingPathComponent(filename),
            atomically: true,
            encoding: .utf8
        )
    }

    func json<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    func treeDigest() throws -> String {
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { !$0.contains("preview-v30.db") }
            .sorted()
        var hasher = SHA256()
        for path in files {
            hasher.update(data: Data(path.utf8))
            let url = root.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let modified = attributes[.modificationDate] as? Date {
                    hasher.update(data: Data(String(format: "%.9f", modified.timeIntervalSince1970).utf8))
                }
                if let inode = attributes[.systemFileNumber] as? NSNumber {
                    hasher.update(data: Data(inode.stringValue.utf8))
                }
                hasher.update(data: try Data(contentsOf: url))
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
}
