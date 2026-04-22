import Foundation
import Testing
@testable import Cider

@MainActor
struct AIConversationStorageTests {
    @Test("resaving a conversation preserves its original on-disk created date")
    func resavingConversationPreservesOriginalCreatedDate() throws {
        let harness = try StorageHarness()
        defer { harness.tearDown() }

        let id = UUID()
        let originalCreatedAt = Date(timeIntervalSince1970: 1_577_836_800) // 2020-01-01T00:00:00Z
        try harness.seedConversation(
            id: id,
            title: "Seeded Title",
            createdAt: originalCreatedAt,
            updatedAt: originalCreatedAt,
            messages: [AIAssistantMessage(role: .user, content: "seed")]
        )

        let storage = AIConversationStorage()

        storage.save(
            id: id,
            title: "Renamed Conversation",
            messages: [
                AIAssistantMessage(role: .user, content: "seed"),
                AIAssistantMessage(role: .assistant, content: "world")
            ],
            model: "apple-intelligence"
        )

        let updatedSummary = try #require(storage.conversations.first(where: { $0.id == id }))
        #expect(updatedSummary.created == originalCreatedAt)
        #expect(updatedSummary.title == "Renamed Conversation")
    }

    @Test("renaming a saved conversation leaves one file and preserves messages")
    func renamingConversationKeepsOneFileAndMessages() throws {
        let harness = try StorageHarness()
        defer { harness.tearDown() }

        let id = UUID()
        let storage = AIConversationStorage()
        let originalMessages = [
            AIAssistantMessage(role: .user, content: "first"),
            AIAssistantMessage(role: .assistant, content: "second")
        ]

        storage.save(id: id, title: "Alpha", messages: originalMessages, model: "apple-intelligence")
        storage.save(id: id, title: "Beta", messages: originalMessages, model: "apple-intelligence")

        let files = try harness.conversationFiles()
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent.contains("beta") == true)

        let loadedMessages = try #require(storage.loadMessages(for: id))
        #expect(loadedMessages.map(\.content) == originalMessages.map(\.content))
    }
}

@MainActor
private struct StorageHarness {
    private struct SeedConversationMeta: Codable {
        let id: UUID
        let title: String
        let created: Date
        let updated: Date
        let model: String
        let messageCount: Int
        let type: String
    }

    let rootURL: URL
    let previousVaultOverride: URL?

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        previousVaultOverride = StoragePaths.vaultOverride
        StoragePaths.vaultOverride = rootURL
        StoragePaths.invalidateCachedDirectory()
    }

    func conversationFiles() throws -> [URL] {
        let conversationsDir = rootURL
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("ai-conversations", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(
            at: conversationsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "jsonl" }
    }

    func seedConversation(
        id: UUID,
        title: String,
        createdAt: Date,
        updatedAt: Date,
        messages: [AIAssistantMessage],
        model: String = "apple-intelligence"
    ) throws {
        let conversationsDir = rootURL
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("ai-conversations", isDirectory: true)
        try FileManager.default.createDirectory(at: conversationsDir, withIntermediateDirectories: true)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let slug = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(5)
            .joined(separator: "-")
        let filename = "\(dateFormatter.string(from: createdAt))-\(slug)-\(id.uuidString.prefix(8).lowercased()).jsonl"
        let fileURL = conversationsDir.appendingPathComponent(filename)

        let meta = SeedConversationMeta(
            id: id,
            title: title,
            created: createdAt,
            updated: updatedAt,
            model: model,
            messageCount: messages.count,
            type: "metadata"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metaLine = String(data: try encoder.encode(meta), encoding: .utf8) ?? ""
        let messageLines = try messages.map { message in
            String(data: try encoder.encode(message), encoding: .utf8) ?? ""
        }
        let content = ([metaLine] + messageLines).joined(separator: "\n") + "\n"
        try content.write(to: fileURL, atomically: true, encoding: String.Encoding.utf8)
    }

    func tearDown() {
        StoragePaths.vaultOverride = previousVaultOverride
        StoragePaths.invalidateCachedDirectory()
        try? FileManager.default.removeItem(at: rootURL)
    }
}
