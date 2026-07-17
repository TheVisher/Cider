import Foundation

enum RemoteChatCommandRouter {
    static func response(
        for text: String,
        channelDisplayName: String,
        bridgeStatusSummary: @Sendable () async -> String,
        runtimeSummary: @Sendable () async -> String,
        switchRuntime: @Sendable (AIAgentRuntimeSelection) async -> Void,
        restartRuntime: @Sendable () async throws -> Void
    ) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }

        let parts = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = parts.first?.lowercased() else { return nil }

        switch command {
        case "/help", "/agent":
            return helpText(channelDisplayName: channelDisplayName)

        case "/status":
            return "\(await bridgeStatusSummary())\n\n\(await runtimeSummary())"

        case "/runtime":
            if parts.count == 1 {
                return await runtimeSummary()
            }
            guard let selection = runtimeSelection(from: parts[1]) else {
                return "Unknown or unavailable runtime. Use /runtime apple, /runtime local, or /runtime hermes. Codex CLI is currently unavailable."
            }
            await switchRuntime(selection)
            return "Switched runtime.\n\(await runtimeSummary())"

        case "/restart":
            do {
                try await restartRuntime()
            } catch {
                return "Failed to restart runtime: \(error.localizedDescription)"
            }
            return "Runtime restarted.\n\(await runtimeSummary())"

        default:
            return "Unknown command. Send /help for available \(channelDisplayName) commands."
        }
    }

    private static func helpText(channelDisplayName: String) -> String {
        """
        Cider \(channelDisplayName) commands:
        /status — show bridge and runtime health
        /runtime — show active runtime
        /runtime apple|local|hermes — switch runtime
        /restart — restart the active runtime
        """
    }

    private static func runtimeSelection(from raw: String) -> AIAgentRuntimeSelection? {
        switch raw.lowercased() {
        case "codex", "codexcli", "codex-cli":
            return nil
        case "apple", "appleintelligence", "foundation":
            return .appleIntelligence
        case "local", "mlx", "qwen":
            return .localModel
        case "hermes":
            return .hermes
        default:
            return nil
        }
    }
}
