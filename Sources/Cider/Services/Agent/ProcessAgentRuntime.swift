import Foundation

/// Base abstraction for long-lived CLI/process-backed agent runtimes.
protocol ProcessAgentRuntime: AgentRuntime {
    var launchPath: String { get }
    var arguments: [String] { get }
    var workingDirectoryURL: URL { get }
    var environment: [String: String] { get }
}

