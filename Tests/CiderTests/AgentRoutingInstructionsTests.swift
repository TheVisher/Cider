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
        #expect(text.contains("native title and thumbnail enrichment"))
        #expect(text.contains("If the destination is unclear, save to Inbox and explain why."))
    }

    @Test("process runtime bookmark capture prompt prefers raw URL save and native enrichment")
    func processRuntimeBookmarkCapturePromptPrefersRawURLSave() async throws {
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

        _ = try await orchestrator.handleMessage(
            .telegram(
                text: "save this https://www.imdb.com/title/tt8633478 to Media/Movies",
                threadID: UUID(),
                channelThreadID: "test-chat",
                context: .empty,
                senderID: "tester",
                senderDisplayName: "Tester"
            )
        )

        let prompt = runtime.lastSystemPrompt
        #expect(prompt?.contains("cider-cli bookmark add \"<url>\" --path \"<vault-path>\"") == true)
        #expect(prompt?.contains("Do not pass `--title` unless the user explicitly gave the final title") == true)
        #expect(prompt?.contains("Only add extra AI enrichment after the bookmark already exists") == true)
        #expect(prompt?.contains("You are Cider's Telegram bookmark capture fast path.") == true)
        #expect(prompt?.contains("Do not invoke external skills or read skill docs.") == true)
        #expect(prompt?.contains("Default to `Inbox/Bookmarks` if routing is not obvious within one quick check.") == true)
        #expect(prompt?.contains("--title \"<title>\"") == false)
        #expect(prompt?.contains("Vault agent instructions:") == false)
        #expect(prompt?.contains("Recent prior turns:") == false)
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
