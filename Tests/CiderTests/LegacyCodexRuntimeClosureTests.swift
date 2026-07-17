import Foundation
import Testing
@testable import Cider

@Suite("Legacy Codex production closure", .serialized)
struct LegacyCodexRuntimeClosureTests {
    @Test("production UI and composition do not expose the legacy Codex runtime")
    func productionUIAndCompositionExcludeLegacyCodex() throws {
        let sources = try ProductionAgentSourceTree.load()
        let panel = try sources.source(at: "Views/AIAssistant/AIAssistantPanelView.swift")
        let viewModel = try sources.source(at: "ViewModels/AIAssistantViewModel.swift")

        #expect(!panel.contains("switchRuntime(to: .codexCLI)"))
        #expect(!panel.contains("Text(\"Codex CLI\")"))
        #expect(!viewModel.contains("CodexProcessRuntime("))
        #expect(!viewModel.contains("return codexRuntime"))
    }

    @Test("production runtime enumeration excludes legacy Codex")
    func productionRuntimeEnumerationExcludesLegacyCodex() {
        #expect(AIAgentRuntimeSelection.productionSelectable == [
            .appleIntelligence,
            .localModel,
            .hermes,
        ])
        #expect(AIAgentRuntimeSelection(rawValue: "codexCLI") == nil)
    }

    @Test("persisted legacy Codex selection migrates once and reopens safely")
    func persistedCodexSelectionMigratesAndReopens() throws {
        let suiteName = "LegacyCodexRuntimeClosureTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("codexCLI", forKey: AIAgentRuntimeSelectionStore.defaultsKey)

        let initialStore = AIAgentRuntimeSelectionStore(defaults: defaults)
        #expect(initialStore.load(localModelEnabled: true) == .appleIntelligence)
        #expect(defaults.string(forKey: AIAgentRuntimeSelectionStore.defaultsKey) == "appleIntelligence")

        let reopenedStore = AIAgentRuntimeSelectionStore(defaults: defaults)
        #expect(reopenedStore.load(localModelEnabled: true) == .appleIntelligence)
        #expect(defaults.string(forKey: AIAgentRuntimeSelectionStore.defaultsKey) == "appleIntelligence")
    }

    @Test("direct local invocation of the legacy Codex identity fails before spawn")
    func directLegacyCodexInvocationFailsBeforeSpawn() async {
        let runtime = LegacyCodexSpawnRecordingRuntime()
        let orchestrator = AgentOrchestrator()
        await orchestrator.setRuntime(runtime)

        do {
            _ = try await orchestrator.handleMessage(.uiPanel(
                text: "attempt legacy runtime",
                threadID: UUID(),
                context: .empty
            ))
            Issue.record("Legacy Codex invocation unexpectedly succeeded")
        } catch let error as AgentError {
            guard case .runtimeUnavailable(let runtimeID, let reason) = error else {
                Issue.record("Expected typed runtimeUnavailable, got \(error)")
                return
            }
            #expect(runtimeID == LegacyCodexRuntimePolicy.runtimeID)
            #expect(reason == LegacyCodexRuntimePolicy.unavailableReason)
        } catch {
            Issue.record("Expected AgentError, got \(error)")
        }

        #expect(runtime.startCount == 0)
        #expect(runtime.sendCount == 0)
        let health = await orchestrator.runtimeHealth()
        #expect(health.status == .unavailable)
        #expect(health.detail == LegacyCodexRuntimePolicy.unavailableReason)
        #expect(await orchestrator.runtimeIdentity() == nil)
    }

    @Test("orchestrator startup of the legacy Codex identity fails before spawn")
    func orchestratorLegacyCodexStartupFailsBeforeSpawn() async {
        let runtime = LegacyCodexSpawnRecordingRuntime()
        let orchestrator = AgentOrchestrator()
        await orchestrator.setRuntime(runtime)

        do {
            try await orchestrator.startRuntimeIfNeeded()
            Issue.record("Legacy Codex orchestrator startup unexpectedly succeeded")
        } catch let error as AgentError {
            guard case .runtimeUnavailable(let runtimeID, let reason) = error else {
                Issue.record("Expected typed runtimeUnavailable, got \(error)")
                return
            }
            #expect(runtimeID == LegacyCodexRuntimePolicy.runtimeID)
            #expect(reason == LegacyCodexRuntimePolicy.unavailableReason)
        } catch {
            Issue.record("Expected AgentError, got \(error)")
        }

        #expect(runtime.startCount == 0)
        #expect(runtime.sendCount == 0)
    }

    @Test("system wake targeting the legacy Codex identity fails before spawn")
    func systemLegacyCodexInvocationFailsBeforeSpawn() async {
        let runtime = LegacyCodexSpawnRecordingRuntime()
        let orchestrator = AgentOrchestrator()
        await orchestrator.setRuntime(runtime)

        do {
            _ = try await orchestrator.wake(purpose: .dailyDigest)
            Issue.record("Legacy Codex system wake unexpectedly succeeded")
        } catch let error as AgentError {
            guard case .runtimeUnavailable(let runtimeID, let reason) = error else {
                Issue.record("Expected typed runtimeUnavailable, got \(error)")
                return
            }
            #expect(runtimeID == LegacyCodexRuntimePolicy.runtimeID)
            #expect(reason == LegacyCodexRuntimePolicy.unavailableReason)
        } catch {
            Issue.record("Expected AgentError, got \(error)")
        }

        #expect(runtime.startCount == 0)
        #expect(runtime.sendCount == 0)
    }

    @Test("supported local and system runtime behavior is unchanged")
    func supportedRuntimeBehaviorIsUnchanged() async throws {
        let runtime = SupportedSpawnRecordingRuntime()
        let orchestrator = AgentOrchestrator()
        await orchestrator.setRuntime(runtime)

        let direct = try await orchestrator.handleMessage(.uiPanel(
            text: "supported local request",
            threadID: UUID(),
            context: .empty
        ))
        let background = try await orchestrator.wake(purpose: .dailyDigest)

        #expect(direct.text == "supported")
        #expect(background.text == "supported")
        #expect(runtime.startCount == 2)
        #expect(runtime.sendCount == 2)
    }

    @Test("production Swift tree has no unbounded Codex launch authority")
    func productionTreeHasNoUnboundedCodexAuthority() throws {
        let sources = try ProductionAgentSourceTree.load()

        #expect(sources.swiftFiles.count > 100)
        for knownOwner in [
            "App/AppDelegate.swift",
            "Services/Agent/AgentOrchestrator.swift",
            "ViewModels/AIAssistantViewModel.swift",
            "Views/AIAssistant/AIAssistantPanelView.swift",
        ] {
            #expect(sources.relativePaths.contains(knownOwner))
        }

        let unsafeAuthorityOwners = sources.swiftFiles.compactMap { file -> String? in
            let source = file.source.lowercased()
            guard source.contains("approvalpolicy")
                    && source.contains("never")
                    && source.contains("danger-full-access")
            else { return nil }
            return file.relativePath
        }
        let vaultRootCodexOwners = sources.swiftFiles.compactMap { file -> String? in
            let source = file.source.lowercased()
            guard source.contains("codexprocessruntime")
                    && source.contains("vault")
            else { return nil }
            return file.relativePath
        }

        #expect(unsafeAuthorityOwners.isEmpty)
        #expect(vaultRootCodexOwners.isEmpty)
    }
}

private final class LegacyCodexSpawnRecordingRuntime: @unchecked Sendable, AgentRuntime {
    let id = "process.codex-cli"
    let displayName = "Codex CLI"
    let kind: AgentRuntimeKind = .process
    let capabilities = AgentRuntimeCapabilities(
        supportsToolCalling: false,
        supportsStreaming: false,
        maxContextTokens: 0
    )

    private let lock = NSLock()
    private var starts = 0
    private var sends = 0

    var startCount: Int { lock.withLock { starts } }
    var sendCount: Int { lock.withLock { sends } }

    func start() async throws {
        lock.withLock { starts += 1 }
    }

    func stop() async {}
    func health() async -> AgentRuntimeHealth { .idle }

    func send(_ request: AgentRuntimeRequest) async throws -> AgentRuntimeResponse {
        lock.withLock { sends += 1 }
        return AgentRuntimeResponse(text: "unsafe", toolRequests: [])
    }

    func stream(_ request: AgentRuntimeRequest) -> AsyncThrowingStream<AgentRuntimeEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func resetThread(_ threadID: UUID) async {}
}

private final class SupportedSpawnRecordingRuntime: @unchecked Sendable, AgentRuntime {
    let id = "model.supported-test"
    let displayName = "Supported Test Runtime"
    let kind: AgentRuntimeKind = .model
    let capabilities = AgentRuntimeCapabilities(
        supportsToolCalling: false,
        supportsStreaming: false,
        maxContextTokens: 4_096
    )

    private let lock = NSLock()
    private var starts = 0
    private var sends = 0

    var startCount: Int { lock.withLock { starts } }
    var sendCount: Int { lock.withLock { sends } }

    func start() async throws {
        lock.withLock { starts += 1 }
    }

    func stop() async {}
    func health() async -> AgentRuntimeHealth { .idle }

    func send(_ request: AgentRuntimeRequest) async throws -> AgentRuntimeResponse {
        lock.withLock { sends += 1 }
        return AgentRuntimeResponse(text: "supported", toolRequests: [])
    }

    func stream(_ request: AgentRuntimeRequest) -> AsyncThrowingStream<AgentRuntimeEvent, Error> {
        AsyncThrowingStream { continuation in continuation.finish() }
    }

    func resetThread(_ threadID: UUID) async {}
}

private struct ProductionAgentSourceTree {
    struct SwiftFile {
        let relativePath: String
        let source: String
    }

    let swiftFiles: [SwiftFile]

    var relativePaths: Set<String> {
        Set(swiftFiles.map(\.relativePath))
    }

    static func load() throws -> ProductionAgentSourceTree {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = repositoryRoot.appendingPathComponent("Sources/Cider", isDirectory: true)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)

        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = try #require(FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ))
        var files: [SwiftFile] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift",
                  try fileURL.resourceValues(forKeys: Set(resourceKeys)).isRegularFile == true
            else { continue }
            let relativePath = String(fileURL.path.dropFirst(sourceRoot.path.count + 1))
            files.append(SwiftFile(
                relativePath: relativePath,
                source: try String(contentsOf: fileURL, encoding: .utf8)
            ))
        }

        #expect(!files.isEmpty)
        return ProductionAgentSourceTree(swiftFiles: files)
    }

    func source(at relativePath: String) throws -> String {
        try #require(swiftFiles.first(where: { $0.relativePath == relativePath })?.source)
    }
}
