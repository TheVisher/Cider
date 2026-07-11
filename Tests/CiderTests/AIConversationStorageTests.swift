import Foundation
import Testing
@testable import Cider

struct AIConversationStorageTests {
    private struct TestFailure: Error {}

    @Test("Hermes duplicate runtime rows collapse to the newest summary")
    @MainActor
    func hermesDuplicateRuntimeRowsCollapseToNewestSummary() {
        let older = makeSummary(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Main Brain older mirror",
            updated: Date(timeIntervalSince1970: 100),
            activeRuntimeSessionID: "session-a"
        )
        let newer = makeSummary(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Main Brain latest mirror",
            updated: Date(timeIntervalSince1970: 200),
            activeRuntimeSessionID: "session-a"
        )
        let fresh = makeSummary(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "Fresh Hermes chat",
            updated: Date(timeIntervalSince1970: 150),
            activeRuntimeSessionID: "session-b"
        )

        let collapsed = AIConversationStorage.collapsingDuplicateHermesRuntimeSummaries([
            older,
            fresh,
            newer
        ])

        #expect(collapsed.map(\.id).contains(newer.id))
        #expect(collapsed.map(\.id).contains(fresh.id))
        #expect(!collapsed.map(\.id).contains(older.id))
        #expect(collapsed.count == 2)
    }

    @Test("verified JSONL save returns exact receipt and read-back payload")
    @MainActor
    func verifiedSaveReceipt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let storage = AIConversationStorage(conversationsDirectoryURL: directory, now: { date })
        let id = UUID()
        let messages = makeMessages()

        let receipt = storage.save(id: id, title: "Verified", messages: messages, model: "hermes")

        #expect(receipt.isCommitted)
        #expect(receipt.conversationID == id)
        #expect(receipt.messageCount == messages.count)
        #expect(receipt.snapshot?.messages.map(\.id) == messages.map(\.id))
        #expect(receipt.snapshot?.messages.map(\.content) == messages.map(\.content))
        let fileURL = directory.appendingPathComponent(try #require(receipt.filename))
        let bytes = try Data(contentsOf: fileURL)
        #expect(receipt.sha256 == AIConversationStorage.sha256(bytes))
        #expect(receipt.snapshot?.bytes == bytes)
    }

    @Test("encoding every row fails before mutation and preserves prior bytes")
    @MainActor
    func encodingFailurePreservesPriorFile() throws {
        let fixture = try seededStorage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var persistence = AIConversationStorage.Persistence.live()
        var encodedMessages = 0
        var writeCalled = false
        persistence.encodeMessage = { message in
            encodedMessages += 1
            if encodedMessages == 2 { throw TestFailure() }
            return try AIConversationStorage.Persistence.live().encodeMessage(message)
        }
        persistence.writeAtomically = { _, _ in writeCalled = true }
        let storage = AIConversationStorage(conversationsDirectoryURL: fixture.directory, persistence: persistence, now: { fixture.date })

        let receipt = storage.save(id: fixture.id, title: "Changed", messages: makeMessages(), model: "hermes")

        #expect(receipt.code == .primaryEncodeFailed)
        #expect(!writeCalled)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.bytes)
        #expect(FileManager.default.fileExists(atPath: fixture.fileURL.path))
    }

    @Test("atomic write failure restores the prior bytes and filename")
    @MainActor
    func writeFailurePreservesPriorFile() throws {
        let fixture = try seededStorage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var persistence = AIConversationStorage.Persistence.live()
        persistence.writeAtomically = { data, url in
            try data.write(to: url, options: .atomic)
            throw TestFailure()
        }
        let storage = AIConversationStorage(conversationsDirectoryURL: fixture.directory, persistence: persistence, now: { fixture.date })

        let receipt = storage.save(id: fixture.id, title: "Original", messages: makeMessages(), model: "changed")

        #expect(receipt.code == .primaryWriteFailed)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.bytes)
        #expect(storage.conversations.map(\.filename) == [fixture.fileURL.lastPathComponent])
    }

    @Test("read-back verification failure restores the prior bytes and filename")
    @MainActor
    func readBackFailurePreservesPriorFile() throws {
        let fixture = try seededStorage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        var persistence = AIConversationStorage.Persistence.live()
        persistence.read = { _ in Data("corrupt".utf8) }
        let storage = AIConversationStorage(conversationsDirectoryURL: fixture.directory, persistence: persistence, now: { fixture.date })

        let receipt = storage.save(id: fixture.id, title: "Original", messages: makeMessages(), model: "changed")

        #expect(receipt.code == .primaryVerificationFailed)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.bytes)
        #expect(storage.conversations.map(\.filename) == [fixture.fileURL.lastPathComponent])
    }

    @Test("renamed save removes the old JSONL only after verified replacement")
    @MainActor
    func renameDeletesOldAfterVerification() throws {
        let fixture = try seededStorage()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let storage = AIConversationStorage(conversationsDirectoryURL: fixture.directory, now: { fixture.date })

        let receipt = storage.save(id: fixture.id, title: "Renamed Conversation", messages: makeMessages(), model: "hermes")

        let newFilename = try #require(receipt.filename)
        #expect(receipt.isCommitted)
        #expect(newFilename != fixture.fileURL.lastPathComponent)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))
        #expect(FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent(newFilename).path))
    }

    private func makeSummary(
        id: UUID,
        title: String,
        updated: Date,
        activeRuntimeSessionID: String
    ) -> AIConversationSummary {
        AIConversationSummary(
            id: id,
            title: title,
            created: Date(timeIntervalSince1970: 0),
            updated: updated,
            messageCount: 2,
            filename: "\(id.uuidString).jsonl",
            runtimeID: CiderAgentChatRegistry.hermesRuntimeID,
            activeRuntimeSessionID: activeRuntimeSessionID,
            runtimeSessionLineage: [activeRuntimeSessionID],
            runtimeSource: "cider",
            runtimeLastSyncedAt: updated
        )
    }

    @MainActor
    private func seededStorage() throws -> (directory: URL, id: UUID, date: Date, fileURL: URL, bytes: Data) {
        let directory = try makeTemporaryDirectory()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let id = UUID()
        let storage = AIConversationStorage(conversationsDirectoryURL: directory, now: { date })
        let receipt = storage.save(id: id, title: "Original", messages: makeMessages(), model: "hermes")
        let filename = try #require(receipt.filename)
        let fileURL = directory.appendingPathComponent(filename)
        return (directory, id, date, fileURL, try Data(contentsOf: fileURL))
    }

    private func makeMessages() -> [AIAssistantMessage] {
        let date = Date(timeIntervalSince1970: 1_799_999_000)
        return [
            AIAssistantMessage(id: UUID(), role: .user, content: "repeat", timestamp: date),
            AIAssistantMessage(id: UUID(), role: .assistant, content: "repeat", timestamp: date),
        ]
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid774-conversations-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
