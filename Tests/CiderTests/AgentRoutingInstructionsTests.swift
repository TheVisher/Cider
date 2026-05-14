import Foundation
import Testing
@testable import Cider

struct AgentRoutingInstructionsTests {
    @Test("routing doctrine includes the core vault rules")
    func includesCoreVaultRules() {
        let text = AgentRoutingInstructions.vaultSaveRoutingDoctrine

        #expect(text.contains("Do not invent new top-level folders."))
        #expect(text.contains("Food"))
        #expect(text.contains("People"))
        #expect(text.contains("Inbox"))
        #expect(text.contains("For bookmarks, notes, and contacts, route before creating when the destination is reasonably clear."))
        #expect(text.contains("prefer saving the raw URL"))
        #expect(text.contains("native title and thumbnail capture"))
        #expect(text.contains("If the destination is unclear, save to Inbox and explain why."))
    }

    @Test("remote channels cannot use process runtimes")
    func remoteChannelsCannotUseProcessRuntimes() async throws {
        let tempVault = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempVault, withIntermediateDirectories: true)

        let previousVaultOverride = StoragePaths.vaultOverride
        StoragePaths.vaultOverride = tempVault
        StoragePaths.invalidateCachedDirectory()
        defer {
            StoragePaths.vaultOverride = previousVaultOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: tempVault)
        }

        let runtime = PromptCapturingProcessRuntime()
        let orchestrator = AgentOrchestrator()
        await orchestrator.setRuntime(runtime)

        await #expect(throws: AgentError.self) {
            _ = try await orchestrator.handleMessage(.telegram(
                text: "save this https://www.imdb.com/title/tt8633478 to Media/Movies",
                threadID: UUID(),
                channelThreadID: "test-chat",
                context: .empty,
                senderID: "tester",
                senderDisplayName: "Tester"
            ))
        }
        #expect(runtime.lastSystemPrompt == nil)
    }
}

private final class PromptCapturingProcessRuntime: @unchecked Sendable, AgentRuntime {
    let id = "test-process-runtime"
    let displayName = "Test Process Runtime"
    let kind: AgentRuntimeKind = .process
    let capabilities = AgentRuntimeCapabilities(
        supportsToolCalling: true,
        supportsStreaming: false,
        maxContextTokens: 8192
    )

    private let lock = NSLock()
    private var capturedSystemPrompt: String?

    var lastSystemPrompt: String? {
        lock.withLock { capturedSystemPrompt }
    }

    func start() async throws {}
    func stop() async {}
    func health() async -> AgentRuntimeHealth { .idle }

    func send(_ request: AgentRuntimeRequest) async throws -> AgentRuntimeResponse {
        lock.withLock {
            capturedSystemPrompt = request.systemPrompt
        }
        return AgentRuntimeResponse(text: "ok", toolRequests: [])
    }

    func stream(_ request: AgentRuntimeRequest) -> AsyncThrowingStream<AgentRuntimeEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func resetThread(_ threadID: UUID) async {}
}
