import Darwin
import Foundation
import os

/// Manages the lifecycle of one long-lived agent subprocess.
actor AgentProcessManager {
    private let logger: Logger

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    private var status: AgentRuntimeStatus = .idle
    private var lastStartedAt: Date?
    private var lastActivityAt: Date?
    private var lastError: String?
    private var restartCount = 0

    init(loggerCategory: String) {
        self.logger = Logger(subsystem: "com.cider.app", category: loggerCategory)
    }

    func start(
        launchPath: String,
        arguments: [String],
        workingDirectoryURL: URL,
        environment: [String: String] = [:]
    ) async throws {
        if let process, process.isRunning { return }

        guard FileManager.default.isExecutableFile(atPath: launchPath) else {
            status = .unavailable
            lastError = "Executable not found: \(launchPath)"
            throw AgentError.deliveryFailed(lastError ?? "Executable unavailable")
        }

        status = restartCount == 0 ? .starting : .restarting
        lastError = nil

        let proc = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = arguments
        proc.currentDirectoryURL = workingDirectoryURL
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        var env: [String: String] = [:]
        for (key, value) in environment {
            env[key] = value
        }
        proc.environment = env

        proc.terminationHandler = { [weak self] terminated in
            Task {
                await self?.handleTermination(status: terminated.terminationStatus)
            }
        }

        do {
            try proc.run()
            self.process = proc
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.stderrPipe = stderr
            self.status = .running
            self.lastStartedAt = Date()
            self.lastActivityAt = Date()
            self.logger.info("Started agent process: \(launchPath, privacy: .public) \(arguments.joined(separator: " "), privacy: .public)")
        } catch {
            self.status = .failed
            self.lastError = error.localizedDescription
            self.logger.error("Failed to start agent process: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func stop() async {
        guard let process else {
            status = .stopped
            return
        }

        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        cleanupAfterStop()
        status = .stopped
        logger.info("Stopped agent process")
    }

    func restart(
        launchPath: String,
        arguments: [String],
        workingDirectoryURL: URL,
        environment: [String: String] = [:]
    ) async throws {
        restartCount += 1
        await stop()
        try await start(
            launchPath: launchPath,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            environment: environment
        )
    }

    func health() -> AgentRuntimeHealth {
        AgentRuntimeHealth(
            status: status,
            detail: healthDetail(),
            lastStartedAt: lastStartedAt,
            lastActivityAt: lastActivityAt,
            lastError: lastError
        )
    }

    func markActivity() {
        lastActivityAt = Date()
    }

    func stdinHandle() -> FileHandle? {
        stdinPipe?.fileHandleForWriting
    }

    func stdoutHandle() -> FileHandle? {
        stdoutPipe?.fileHandleForReading
    }

    func stderrHandle() -> FileHandle? {
        stderrPipe?.fileHandleForReading
    }

    private func handleTermination(status terminationStatus: Int32) {
        lastActivityAt = Date()

        if self.status == .stopped {
            cleanupAfterStop()
            return
        }

        cleanupAfterStop()
        self.status = .failed
        self.lastError = "Process exited with status \(terminationStatus)"
        logger.error("Agent process exited with status \(terminationStatus)")
    }

    private func cleanupAfterStop() {
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    private func healthDetail() -> String {
        switch status {
        case .idle:
            return "Runtime has not been started"
        case .starting:
            return "Runtime is starting"
        case .running:
            return "Runtime is running"
        case .restarting:
            return "Runtime is restarting"
        case .stopped:
            return "Runtime is stopped"
        case .failed:
            return lastError ?? "Runtime failed"
        case .unavailable:
            return lastError ?? "Runtime unavailable"
        }
    }
}
