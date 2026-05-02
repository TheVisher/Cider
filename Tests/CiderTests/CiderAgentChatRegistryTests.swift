import Foundation
import Testing
@testable import Cider

struct CiderAgentChatRegistryTests {
    @Test("empty registry does not create seeded Hermes main brain")
    func emptyRegistryDoesNotCreateSeededMainBrain() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let record = try registry.loadMainBrain()

        #expect(record == nil)
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("cider.main.json").path))
    }

    @Test("create main brain persists caller supplied Hermes state")
    func createMainBrainPersistsCallerSuppliedHermesState() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let conversationID = UUID()
        let state = HermesConversationState(
            conversationID: conversationID,
            activeRuntimeSessionID: "fresh-session-2",
            runtimeSessionLineage: ["fresh-session-1", "fresh-session-2"],
            title: "Latest Telegram",
            source: "telegram",
            lastSyncedAt: Date(timeIntervalSince1970: 1_777_680_000)
        )

        let created = try registry.createMainBrain(from: state)
        let loaded = try registry.loadMainBrain()

        #expect(created.stableID == CiderAgentChatRegistry.mainBrainStableID)
        #expect(created.title == CiderAgentChatRegistry.mainBrainTitle)
        #expect(created.kind == CiderAgentChatRegistry.mainBrainKind)
        #expect(created.conversationID == conversationID)
        #expect(created.runtimeID == "hermes")
        #expect(created.activeRuntimeSessionID == "fresh-session-2")
        #expect(created.runtimeSessionLineage == ["fresh-session-1", "fresh-session-2"])
        #expect(created.defaultInCider)
        #expect(loaded == created)
    }

    @Test("later loads preserve the same conversation identity")
    func laterLoadsPreserveConversationIdentity() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let state = HermesConversationState(
            activeRuntimeSessionID: "session-a",
            runtimeSessionLineage: ["session-a"],
            title: "Main Brain",
            source: "telegram"
        )
        let first = try registry.createMainBrain(from: state)
        let second = try registry.loadMainBrain()

        #expect(second?.conversationID == first.conversationID)
        #expect(second?.stableID == first.stableID)
        #expect(second?.runtimeSessionLineage == first.runtimeSessionLineage)
    }

    @Test("Hermes updates keep the stable chat while moving runtime pointer")
    func hermesUpdatesMoveRuntimePointer() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let first = try registry.createMainBrain(from: HermesConversationState(
            activeRuntimeSessionID: "20260501_120144_e3d994",
            runtimeSessionLineage: ["20260501_120144_e3d994"],
            title: "Cider Vault Agent #4",
            source: "telegram"
        ))
        let state = HermesConversationState(
            conversationID: first.conversationID,
            activeRuntimeSessionID: "20260501_130000_next",
            runtimeSessionLineage: [
                "20260501_120144_e3d994",
                "20260501_130000_next"
            ],
            title: "Hermes title",
            source: "telegram"
        )

        let updated = try registry.updateMainBrain(from: state)
        let loaded = try registry.loadMainBrain()

        #expect(updated.stableID == CiderAgentChatRegistry.mainBrainStableID)
        #expect(updated.conversationID == first.conversationID)
        #expect(updated.title == CiderAgentChatRegistry.mainBrainTitle)
        #expect(updated.activeRuntimeSessionID == "20260501_130000_next")
        #expect(updated.runtimeSessionLineage == [
            "20260501_120144_e3d994",
            "20260501_130000_next"
        ])
        #expect(loaded?.stableID == updated.stableID)
        #expect(loaded?.conversationID == updated.conversationID)
        #expect(loaded?.activeRuntimeSessionID == updated.activeRuntimeSessionID)
        #expect(loaded?.runtimeSessionLineage == updated.runtimeSessionLineage)
    }

    @Test("named Hermes chat starts as stable local record without Hermes session")
    func namedHermesChatStartsAsStableLocalRecordWithoutHermesSession() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)

        let chat = try registry.createHermesChat(title: "  Cider   Dashboard Worktree  ", scope: "project")
        let loaded = try registry.loadChat(stableID: chat.stableID)

        #expect(chat.stableID == "cider.cider-dashboard-worktree")
        #expect(chat.title == "Cider Dashboard Worktree")
        #expect(chat.hermesTitle == "Cider Dashboard Worktree")
        #expect(chat.kind == CiderAgentChatRegistry.hermesChatKind)
        #expect(chat.scope == "project")
        #expect(chat.activeRuntimeSessionID.isEmpty)
        #expect(chat.runtimeSessionLineage.isEmpty)
        #expect(!chat.defaultInCider)
        #expect(!chat.archived)
        #expect(loaded == chat)
    }

    @Test("named Hermes chat stable IDs are unique and survive rename")
    func namedHermesChatStableIDsAreUniqueAndSurviveRename() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)

        let first = try registry.createHermesChat(title: "Cider Scratchpad", scope: "scratchpad")
        let second = try registry.createHermesChat(title: "Cider Scratchpad", scope: "scratchpad")
        let renamed = try registry.renameChat(stableID: first.stableID, title: "Cider Web Review")

        #expect(first.stableID == "cider.cider-scratchpad")
        #expect(second.stableID == "cider.cider-scratchpad-2")
        #expect(renamed.stableID == first.stableID)
        #expect(renamed.title == "Cider Web Review")
        #expect(renamed.hermesTitle == "Cider Web Review")
    }

    @Test("archived named chats disappear from default list")
    func archivedNamedChatsDisappearFromDefaultList() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let visible = try registry.createHermesChat(title: "Cider Web Review", scope: nil)
        let archived = try registry.createHermesChat(title: "Cider Scratchpad", scope: nil)

        try registry.archiveChat(stableID: archived.stableID)

        #expect(try registry.listChats().map(\.stableID) == [visible.stableID])
        #expect(try registry.listChats(includeArchived: true).map(\.stableID).contains(archived.stableID))
    }

    @Test("Telegram resume command uses Hermes visible title")
    func telegramResumeCommandUsesHermesVisibleTitle() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let chat = try registry.createHermesChat(title: "Cider Dashboard Worktree", scope: nil)

        #expect(CiderAgentChatRegistry.telegramResumeCommand(for: chat) == "/resume Cider Dashboard Worktree")
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
