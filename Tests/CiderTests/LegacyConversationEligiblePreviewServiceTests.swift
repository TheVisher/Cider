import Foundation
import Testing
@testable import Cider

@Suite("Eligible Legacy Conversation Preview Tests")
@MainActor
struct LegacyConversationEligiblePreviewServiceTests {
    @Test("Eligible preview is independently versioned, immutable, and never authorizes writes")
    func eligiblePreviewSafetyContract() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let before = try fixture.inputSnapshot()
            let first = fixture.service.preview()
            let second = fixture.service.preview()

            #expect(first == second)
            #expect(first.formatVersion == "cider.legacy-conversation-eligible-preview.v1")
            #expect(first.state == .ready)
            #expect(first.readOnly)
            #expect(!first.changed)
            #expect(!first.safeForBackfill)
            #expect(!first.safeForShadowWrites)
            #expect(first.counts.registeredActiveTotal == 1)
            #expect(first.counts.eligibleTotal == 1)
            #expect(first.counts.roomLocalOmitted == 0)
            #expect(first.counts.displayedTotal == 1)
            #expect(try fixture.inputSnapshot() == before)
        }
    }

    @Test("Cross-candidate UUID collision blocks every room without exposing private values")
    func crossCandidateCollisionBlocks() throws {
        try withEligibleFixture { fixture in
            let collision = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
            try fixture.writeRoom(index: 1, messageID: collision, privateText: "sentinel-private-one")
            try fixture.writeRoom(index: 2, messageID: collision, privateText: "sentinel-private-two")

            let result = fixture.service.preview()
            #expect(result.state == .blocked)
            #expect(result.rooms.isEmpty)
            #expect(!String(describing: result).contains("sentinel-private"))
        }
    }

    @Test("Orphan collisions omit only the affected whole candidate and orphan-only collisions remain local")
    func orphanCollisionPolicy() throws {
        try withEligibleFixture { fixture in
            let collision = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
            try fixture.writeRoom(index: 1, messageID: collision)
            try fixture.writeRoom(index: 2)
            try fixture.writeOrphan(index: 1, messageID: collision, sourceID: "hermes:orphan:shared")
            try fixture.writeOrphan(index: 2, messageID: collision, sourceID: "hermes:orphan:shared")

            let result = fixture.service.preview()
            #expect(result.state == .ready)
            #expect(result.counts.registeredActiveTotal == 2)
            #expect(result.counts.eligibleTotal == 1)
            #expect(result.counts.roomLocalOmitted == 1)
            #expect(result.counts.unregisteredFileTotal == 2)
        }
    }

    @Test("Malformed orphan and registry inputs globally block with zero rooms")
    func incompleteEnumerationBlocks() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            try Data("not-json\nnot-json\n".utf8).write(
                to: fixture.conversationDirectory.appendingPathComponent("orphan.jsonl")
            )
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
        try withEligibleFixture { fixture in
            try Data("sentinel-private-registry".utf8).write(
                to: fixture.registryDirectory.appendingPathComponent("bad.json")
            )
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
    }

    @Test("Attachment or malformed data anywhere omits the whole room before message caps")
    func wholeRoomValidationBeforeCaps() throws {
        try withEligibleFixture { fixture in
            var messages = fixture.messages(count: 105, roomIndex: 1)
            messages[0].attachments = [.init(id: "sentinel-attachment", kind: .image)]
            try fixture.writeRoom(index: 1, messages: messages)
            let result = fixture.service.preview()
            #expect(result.state == .eligibleEmpty)
            #expect(result.counts.roomLocalOmitted == 1)
            #expect(result.rooms.isEmpty)
        }
    }

    @Test("Room and message caps use exact arithmetic and deterministic chronological output")
    func exactCaps() throws {
        try withEligibleFixture { fixture in
            for index in 1...22 {
                try fixture.writeRoom(index: index, messages: fixture.messages(count: index == 22 ? 105 : 1, roomIndex: index))
            }
            let result = fixture.service.preview()
            #expect(result.counts.registeredActiveTotal == 22)
            #expect(result.counts.eligibleTotal == 22)
            #expect(result.counts.displayedTotal == 20)
            #expect(result.counts.eligibleCapOmitted == 2)
            #expect(result.rooms.count == 20)
            #expect(result.rooms[0].totalMessages == 105)
            #expect(result.rooms[0].messageCapOmitted == 5)
            #expect(result.rooms[0].plan.messages.map(\.sequence) == Array(6...105).map(Int64.init))
        }
    }

    @Test("Concurrent input replacement is discarded as sanitized retryable failure")
    func concurrentChangeIsDiscarded() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            var changed = false
            let service = fixture.makeService {
                guard !changed else { return }
                changed = true
                try? Data("changed".utf8).write(
                    to: fixture.registryDirectory.appendingPathComponent("room-1.json"),
                    options: .atomic
                )
            }
            #expect(service.preview() == .sanitized(.failed))
        }
    }

    @Test("Canonical room and binding timestamp drift omits the whole candidate")
    func canonicalTimestampParityIsExact() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1)
            let baseline = fixture.service.preview()
            let eligible = try #require(baseline.rooms.first)
            let room = try #require(eligible.plan.rooms.first)
            let binding = try #require(eligible.plan.bindings.first)

            let exact = fixture.makeService(
                parityReader: PlannedParityReader(room: room, binding: binding)
            ).preview()
            #expect(exact.state == .ready)

            let roomDrift = fixture.makeService(
                parityReader: PlannedParityReader(
                    room: room,
                    binding: binding,
                    roomUpdatedAt: room.updatedAt.addingTimeInterval(1)
                )
            ).preview()
            #expect(roomDrift.state == .eligibleEmpty)
            #expect(roomDrift.counts.roomLocalOmitted == 1)

            let bindingDrift = fixture.makeService(
                parityReader: PlannedParityReader(
                    room: room,
                    binding: binding,
                    bindingUpdatedAt: binding.updatedAt.addingTimeInterval(1)
                )
            ).preview()
            #expect(bindingDrift.state == .eligibleEmpty)
            #expect(bindingDrift.counts.roomLocalOmitted == 1)
        }
    }

    @Test("Cross-room binding identity collision blocks even with distinct messages")
    func crossBindingCollisionBlocks() throws {
        try withEligibleFixture { fixture in
            try fixture.writeRoom(index: 1, sessionOverride: "shared-session")
            try fixture.writeRoom(index: 2, sessionOverride: "shared-session")
            #expect(fixture.service.preview() == .sanitized(.blocked))
        }
    }
}

@MainActor
private struct PlannedParityReader: ConversationCoreParityReading {
    let existingRoom: ConversationRoom
    let existingBinding: ConversationRuntimeBinding

    init(
        room: LegacyConversationRoomPlanRecord,
        binding: LegacyConversationBindingPlanRecord,
        roomUpdatedAt: Date? = nil,
        bindingUpdatedAt: Date? = nil
    ) {
        existingRoom = ConversationRoom(
            id: room.id,
            stableKey: room.stableKey,
            title: room.title,
            kind: room.kind,
            lifecycleState: room.lifecycleState,
            nextTurnSequence: room.nextTurnSequence,
            nextMessageSequence: room.nextMessageSequence,
            metadata: room.metadata,
            createdAt: room.createdAt,
            updatedAt: roomUpdatedAt ?? room.updatedAt,
            archivedAt: room.archivedAt,
            trashedAt: nil
        )
        existingBinding = ConversationRuntimeBinding(
            id: binding.id,
            roomID: binding.roomID,
            parentBindingID: binding.parentBindingID,
            runtimeID: binding.runtimeID,
            transportID: binding.transportID,
            sourceNamespace: binding.sourceNamespace,
            externalSessionID: binding.externalSessionID,
            state: binding.state,
            cursorMessageID: binding.cursorMessageID,
            cursorTimestamp: binding.cursorTimestamp,
            metadata: binding.metadata,
            createdAt: binding.createdAt,
            updatedAt: bindingUpdatedAt ?? binding.updatedAt
        )
    }

    func room(id: UUID) throws -> ConversationRoom? { id == existingRoom.id ? existingRoom : nil }
    func room(stableKey: String) throws -> ConversationRoom? {
        stableKey == existingRoom.stableKey ? existingRoom : nil
    }
    func bindings(roomID: UUID) throws -> [ConversationRuntimeBinding] {
        roomID == existingRoom.id ? [existingBinding] : []
    }
    func turn(id: UUID) throws -> ConversationTurn? { nil }
    func messages(roomID: UUID) throws -> [ConversationMessage] { [] }
}

@MainActor
private func withEligibleFixture(_ body: (EligibleFixture) throws -> Void) throws {
    let fixture = try EligibleFixture()
    defer { fixture.remove() }
    try body(fixture)
}

@MainActor
private final class EligibleFixture {
    let root: URL
    let registryDirectory: URL
    let conversationDirectory: URL
    let database: CiderDatabase
    let repository: ConversationRepository
    let service: LegacyConversationEligiblePreviewService
    private let encoder: JSONEncoder
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cid-796-\(UUID().uuidString)", isDirectory: true)
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
        service = LegacyConversationEligiblePreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: ConversationRepositoryParityReader(repository: repository),
            canonicalIsHonestlyEmpty: { true }
        )
    }

    func remove() {
        database.close()
        try? FileManager.default.removeItem(at: root)
    }

    func writeRoom(
        index: Int,
        messageID: UUID = UUID(),
        privateText: String = "temporary message",
        messages suppliedMessages: [AIAssistantMessage]? = nil,
        sessionOverride: String? = nil
    ) throws {
        let roomID = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
        let title = "Temporary \(index)"
        let session = sessionOverride ?? "session-\(index)"
        let record = CiderAgentChatRecord(
            stableID: "temporary.\(index)", title: title, kind: "chat", conversationID: roomID,
            runtimeID: "hermes", activeRuntimeSessionID: session, runtimeSessionLineage: [session],
            lastSyncedMessageID: nil, lastSyncedTimestamp: nil, lastImportedRuntimeSessionID: session,
            scope: "temporary-test", archived: false, createdAt: timestamp,
            updatedAt: timestamp.addingTimeInterval(Double(index)), defaultInCider: false
        )
        try encoder.encode(record).write(to: registryDirectory.appendingPathComponent("room-\(index).json"))

        var metadata = AIConversationMeta(id: roomID, title: title, model: "hermes")
        metadata.updated = record.updatedAt
        let roomMessages = suppliedMessages ?? [AIAssistantMessage(
            id: messageID, role: .user, content: privateText, timestamp: timestamp,
            sourceID: "hermes:room-\(index):message", sourceSessionID: session, sourceName: "Hermes"
        )]
        metadata.messageCount = roomMessages.count
        metadata.runtimeID = "hermes"
        metadata.activeRuntimeSessionID = session
        metadata.runtimeSessionLineage = [session]
        metadata.runtimeLastImportedSessionID = session
        let rows = try [encoder.encode(metadata)] + roomMessages.map(encoder.encode)
        try rows.reduce(into: Data()) { data, row in data.append(row); data.append(0x0a) }
            .write(to: conversationDirectory.appendingPathComponent("not-authority-\(index).jsonl"))
    }

    func writeOrphan(index: Int, messageID: UUID, sourceID: String) throws {
        let orphanID = UUID(uuidString: String(format: "99999999-9999-4999-8999-%012d", index))!
        var metadata = AIConversationMeta(id: orphanID, title: "orphan", model: "hermes")
        metadata.messageCount = 1
        let message = AIAssistantMessage(
            id: messageID, role: .user, content: "sentinel-orphan", timestamp: timestamp,
            sourceID: sourceID, sourceSessionID: nil, sourceName: nil
        )
        let rows = try [encoder.encode(metadata), encoder.encode(message)]
        try rows.reduce(into: Data()) { data, row in data.append(row); data.append(0x0a) }
            .write(to: conversationDirectory.appendingPathComponent("orphan-\(index).jsonl"))
    }

    func messages(count: Int, roomIndex: Int) -> [AIAssistantMessage] {
        (1...count).map { sequence in
            AIAssistantMessage(
                id: UUID(uuidString: String(format: "%08d-0000-4000-8000-%012d", roomIndex, sequence))!,
                role: sequence.isMultiple(of: 2) ? .assistant : .user,
                content: "temporary-\(sequence)",
                timestamp: timestamp.addingTimeInterval(Double(sequence)),
                sourceID: "hermes:room-\(roomIndex):\(sequence)",
                sourceSessionID: "session-\(roomIndex)",
                sourceName: "Hermes"
            )
        }
    }

    func makeService(
        parityReader: (any ConversationCoreParityReading)? = nil,
        beforeRevalidation: @escaping () -> Void = {}
    ) -> LegacyConversationEligiblePreviewService {
        LegacyConversationEligiblePreviewService(
            registryDirectory: registryDirectory,
            conversationDirectory: conversationDirectory,
            parityReader: parityReader ?? ConversationRepositoryParityReader(repository: repository),
            canonicalIsHonestlyEmpty: { true },
            beforeRevalidation: beforeRevalidation
        )
    }

    func inputSnapshot() throws -> [String: Data] {
        var snapshot: [String: Data] = [:]
        for directory in [registryDirectory, conversationDirectory] {
            for name in try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() {
                snapshot["\(directory.lastPathComponent)/\(name)"] = try Data(contentsOf: directory.appendingPathComponent(name))
            }
        }
        return snapshot
    }
}
