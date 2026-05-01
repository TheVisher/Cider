import Foundation
import Testing
@testable import Cider

struct CiderAgentChatRegistryTests {
    @Test("first load creates the seeded Cider main brain record")
    func firstLoadCreatesSeededMainBrainRecord() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let record = try registry.loadOrCreateMainBrain()

        #expect(record.stableID == CiderAgentChatRegistry.mainBrainStableID)
        #expect(record.title == CiderAgentChatRegistry.mainBrainTitle)
        #expect(record.kind == CiderAgentChatRegistry.mainBrainKind)
        #expect(record.runtimeID == "hermes")
        #expect(record.activeRuntimeSessionID == "20260501_120144_e3d994")
        #expect(record.runtimeSessionLineage == CiderAgentChatRegistry.seedHermesLineage)
        #expect(record.defaultInCider)
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("cider.main.json").path))
    }

    @Test("later loads preserve the same conversation identity")
    func laterLoadsPreserveConversationIdentity() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let first = try registry.loadOrCreateMainBrain()
        let second = try registry.loadOrCreateMainBrain()

        #expect(second.conversationID == first.conversationID)
        #expect(second.stableID == first.stableID)
        #expect(second.runtimeSessionLineage == first.runtimeSessionLineage)
    }

    @Test("Hermes updates keep the stable chat while moving runtime pointer")
    func hermesUpdatesMoveRuntimePointer() throws {
        let tempDir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let registry = CiderAgentChatRegistry(storageDirectoryURL: tempDir)
        let first = try registry.loadOrCreateMainBrain()
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
        let loaded = try registry.loadOrCreateMainBrain()

        #expect(updated.stableID == CiderAgentChatRegistry.mainBrainStableID)
        #expect(updated.conversationID == first.conversationID)
        #expect(updated.title == CiderAgentChatRegistry.mainBrainTitle)
        #expect(updated.activeRuntimeSessionID == "20260501_130000_next")
        #expect(updated.runtimeSessionLineage == [
            "20260501_045533_cce0d1c1",
            "20260501_100416_ebff7f",
            "20260501_114444_443f9e",
            "20260501_120144_e3d994",
            "20260501_130000_next"
        ])
        #expect(loaded.stableID == updated.stableID)
        #expect(loaded.conversationID == updated.conversationID)
        #expect(loaded.activeRuntimeSessionID == updated.activeRuntimeSessionID)
        #expect(loaded.runtimeSessionLineage == updated.runtimeSessionLineage)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
