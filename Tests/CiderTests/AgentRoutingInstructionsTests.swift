import Foundation
import Testing
@testable import Cider

struct AgentRoutingInstructionsTests {
    @Test("routing doctrine includes the core vault rules")
    func includesCoreVaultRules() {
        let text = AgentRoutingInstructions.vaultSaveRoutingDoctrine

        #expect(text.contains("item/capture/review/storage APIs"))
        #expect(text.contains("capture add"))
        #expect(text.contains("item get"))
        #expect(text.contains("item search"))
        #expect(text.contains("item context"))
        #expect(text.contains("item related"))
        #expect(text.contains("item why-surfaced"))
        #expect(text.contains("review/routing flows"))
        #expect(text.contains("confirmed state and provenance"))
        #expect(text.contains("Kanban card"))
    }

    @Test("routing doctrine avoids legacy-first agent surfaces")
    func avoidsLegacyFirstAgentSurfaces() {
        let text = AgentRoutingInstructions.vaultSaveRoutingDoctrine

        #expect(text.contains("Avoid legacy-first surfaces"))
        #expect(text.contains("memory"))
        #expect(text.contains("embeddings"))
        #expect(text.contains("folder kanban"))
        #expect(text.contains("old search/query/recent/snapshot/status"))
        #expect(text.contains("instead of working around the backend"))
        #expect(!text.contains("Use the existing vault domains:"))
        #expect(!text.contains("For bookmarks, notes, and contacts, route before creating"))
        #expect(!text.contains("save to Inbox and explain why"))
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

    @Test("process runtime routing hints prefer second brain v1 cli")
    func processRuntimeRoutingHintsPreferSecondBrainV1CLI() async throws {
        let runtime = PromptCapturingProcessRuntime()
        let orchestrator = AgentOrchestrator()
        await orchestrator.setRuntime(runtime)

        _ = try await orchestrator.handleMessage(.uiPanel(
            text: "how many bookmarks do I have?",
            threadID: UUID(),
            context: .empty
        ))
        let countPrompt = try #require(runtime.lastSystemPrompt)
        #expect(countPrompt.contains("cider-cli item graph-health --json"))
        #expect(countPrompt.contains("cider-cli storage audit --json"))
        #expect(!countPrompt.contains("cider-cli status --json"))

        _ = try await orchestrator.handleMessage(.uiPanel(
            text: "save https://example.com",
            threadID: UUID(),
            context: .empty
        ))
        let capturePrompt = try #require(runtime.lastSystemPrompt)
        #expect(capturePrompt.contains("cider-cli capture add --kind bookmark --url \"<url>\" --json"))
        #expect(capturePrompt.contains("cider-cli item get <type> <id> --json"))
        #expect(!capturePrompt.contains("cider-cli bookmark add"))
        #expect(!capturePrompt.contains("cider-cli bookmark get"))
        #expect(!capturePrompt.contains("cider-cli duplicate-check"))

        _ = try await orchestrator.handleMessage(.uiPanel(
            text: "schedule a meeting with Avery next Friday at 10:30",
            threadID: UUID(),
            context: .empty
        ))
        let eventPrompt = try #require(runtime.lastSystemPrompt)
        #expect(eventPrompt.contains("cider-cli capture add --kind event --title \"<title>\" --date yyyy-MM-dd --time \"<time>\" --location \"<place>\" --stdin --json"))
        #expect(!eventPrompt.contains("cider-cli capture add \"<event text>\" --json"))
        #expect(!eventPrompt.contains("cider-cli event create"))

        _ = try await orchestrator.handleMessage(.uiPanel(
            text: "save this image as a todo",
            threadID: UUID(),
            context: .empty
        ))
        let imageTodoPrompt = try #require(runtime.lastSystemPrompt)
        #expect(imageTodoPrompt.contains("cider-cli capture add --kind todo --stdin --json"))
        #expect(imageTodoPrompt.contains("read the image once"))
        #expect(imageTodoPrompt.contains("one capture command plus item get verification"))
        #expect(!imageTodoPrompt.contains("cider-cli todo create"))
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
