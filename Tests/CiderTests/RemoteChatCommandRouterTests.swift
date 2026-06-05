import Testing
@testable import Cider

struct RemoteChatCommandRouterTests {
    @Test("non-command remote chat text is ignored")
    func nonCommandRemoteChatTextIsIgnored() async throws {
        let response = await RemoteChatCommandRouter.response(
            for: "save this please",
            channelDisplayName: "Discord",
            bridgeStatusSummary: { "Discord bridge: healthy" },
            runtimeSummary: { "Runtime selection: Apple Intelligence" },
            switchRuntime: { _ in },
            restartRuntime: {}
        )

        #expect(response == nil)
    }

    @Test("help command is channel agnostic")
    func helpCommandIsChannelAgnostic() async throws {
        let telegram = try #require(await RemoteChatCommandRouter.response(
            for: "/help",
            channelDisplayName: "Telegram",
            bridgeStatusSummary: { "Telegram bridge: healthy" },
            runtimeSummary: { "Runtime selection: Apple Intelligence" },
            switchRuntime: { _ in },
            restartRuntime: {}
        ))
        let discord = try #require(await RemoteChatCommandRouter.response(
            for: "/agent",
            channelDisplayName: "Discord",
            bridgeStatusSummary: { "Discord bridge: healthy" },
            runtimeSummary: { "Runtime selection: Apple Intelligence" },
            switchRuntime: { _ in },
            restartRuntime: {}
        ))

        #expect(telegram.contains("Cider Telegram commands:"))
        #expect(discord.contains("Cider Discord commands:"))
        #expect(discord.contains("/runtime apple|local"))
        #expect(discord.contains("/restart"))
    }

    @Test("future channels refuse Codex runtime selection")
    func futureChannelsRefuseCodexRuntimeSelection() async throws {
        let recorder = RemoteChatCommandRecorder()
        let response = try #require(await RemoteChatCommandRouter.response(
            for: "/runtime codex-cli",
            channelDisplayName: "Matrix",
            bridgeStatusSummary: { "Matrix bridge: healthy" },
            runtimeSummary: { "Runtime selection: Apple Intelligence" },
            switchRuntime: { await recorder.switchRuntime(to: $0) },
            restartRuntime: {}
        ))

        #expect(await recorder.switchedRuntime == nil)
        #expect(response == "Unknown runtime. Use /runtime apple or /runtime local. Codex CLI is only available from the local Cider UI.")
    }

    @Test("runtime and restart commands use injected safe operations")
    func runtimeAndRestartCommandsUseInjectedSafeOperations() async throws {
        let recorder = RemoteChatCommandRecorder()

        let switchResponse = try #require(await RemoteChatCommandRouter.response(
            for: "/runtime local",
            channelDisplayName: "Discord",
            bridgeStatusSummary: { "Discord bridge: healthy" },
            runtimeSummary: { "Runtime selection: Local Qwen" },
            switchRuntime: { await recorder.switchRuntime(to: $0) },
            restartRuntime: { await recorder.recordRestart() }
        ))
        let restartResponse = try #require(await RemoteChatCommandRouter.response(
            for: "/restart",
            channelDisplayName: "Discord",
            bridgeStatusSummary: { "Discord bridge: healthy" },
            runtimeSummary: { "Runtime selection: Local Qwen" },
            switchRuntime: { await recorder.switchRuntime(to: $0) },
            restartRuntime: { await recorder.recordRestart() }
        ))

        #expect(await recorder.switchedRuntime == .localModel)
        #expect(switchResponse == "Switched runtime.\nRuntime selection: Local Qwen")
        #expect(await recorder.restartCount == 1)
        #expect(restartResponse == "Runtime restarted.\nRuntime selection: Local Qwen")
    }

    @Test("status command combines bridge and runtime summaries")
    func statusCommandCombinesBridgeAndRuntimeSummaries() async throws {
        let response = try #require(await RemoteChatCommandRouter.response(
            for: "/status",
            channelDisplayName: "Discord",
            bridgeStatusSummary: { "Discord bridge: healthy\nBridge detail: configured" },
            runtimeSummary: { "Runtime selection: Hermes" },
            switchRuntime: { _ in },
            restartRuntime: {}
        ))

        #expect(response == "Discord bridge: healthy\nBridge detail: configured\n\nRuntime selection: Hermes")
    }
}

private actor RemoteChatCommandRecorder {
    private(set) var switchedRuntime: AIAgentRuntimeSelection?
    private(set) var restartCount = 0

    func switchRuntime(to runtime: AIAgentRuntimeSelection) {
        switchedRuntime = runtime
    }

    func recordRestart() {
        restartCount += 1
    }
}
