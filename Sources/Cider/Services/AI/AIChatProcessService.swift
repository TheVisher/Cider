import Foundation
import os

/// Manages CLI processes for AI chat. Supports two modes:
/// - **One-shot:** Runs a command with arguments per message (e.g. `claude -p "hello"`).
///   Output streams back, process exits when done. Used for AI CLIs.
/// - **Persistent:** Keeps a long-running process (e.g. `/bin/zsh`). Input is piped via stdin.
///   Used for shell mode.
final class AIChatProcessService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.cider.app", category: "AIChatProcess")

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    /// Called on a background thread with each chunk of output text (ANSI-stripped).
    var onOutput: ((String) -> Void)?
    /// Called when the process exits.
    var onProcessExit: ((Int32) -> Void)?

    private let vaultPath: String = {
        StoragePaths.cachedVaultDirectoryURL.path
    }()

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    // MARK: - One-Shot Mode (AI CLIs)

    /// Run a command with arguments and stream its output. Process exits when done.
    /// Use this for AI CLIs like `claude -p "message"`.
    func runOneShot(command: String, arguments: [String]) {
        stop()

        guard let executablePath = resolveExecutable(command) else {
            logger.warning("Could not find executable: \(command)")
            onOutput?("Error: Could not find '\(command)' in your PATH. Make sure it's installed.\n")
            onProcessExit?(-1)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
        proc.environment = buildEnvironment()

        let output = Pipe()
        let error = Pipe()

        proc.standardOutput = output
        proc.standardError = error

        self.outputPipe = output
        self.errorPipe = error
        self.process = proc

        setupOutputHandlers(stdout: output, stderr: error)

        proc.terminationHandler = { [weak self] proc in
            self?.onProcessExit?(proc.terminationStatus)
        }

        do {
            try proc.run()
            logger.info("One-shot: \(executablePath) \(arguments.joined(separator: " "))")
        } catch {
            logger.error("Failed to start process: \(error.localizedDescription)")
            onOutput?("Error starting \(command): \(error.localizedDescription)\n")
            onProcessExit?(-1)
        }
    }

    // MARK: - Persistent Mode (Shell)

    /// Start a long-running process with stdin pipe. Use for shell mode.
    func startPersistent(command: String, arguments: [String] = []) {
        stop()

        guard let executablePath = resolveExecutable(command) else {
            logger.warning("Could not find executable: \(command)")
            onOutput?("Error: Could not find '\(command)' in your PATH. Make sure it's installed.\n")
            onProcessExit?(-1)
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        proc.currentDirectoryURL = URL(fileURLWithPath: vaultPath)
        proc.environment = buildEnvironment()

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()

        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = error

        self.inputPipe = input
        self.outputPipe = output
        self.errorPipe = error
        self.process = proc

        setupOutputHandlers(stdout: output, stderr: error)

        proc.terminationHandler = { [weak self] proc in
            self?.onProcessExit?(proc.terminationStatus)
        }

        do {
            try proc.run()
            logger.info("Persistent: \(executablePath)")
        } catch {
            logger.error("Failed to start process: \(error.localizedDescription)")
            onOutput?("Error starting \(command): \(error.localizedDescription)\n")
            onProcessExit?(-1)
        }
    }

    /// Send text to stdin of a persistent process.
    func send(_ text: String) {
        guard let inputPipe, process?.isRunning == true else { return }
        let data = Data((text + "\n").utf8)
        inputPipe.fileHandleForWriting.write(data)
    }

    func stop() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }

        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }

    // MARK: - Internal

    private func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "dumb"
        env["NO_COLOR"] = "1"
        env["PATH"] = expandedPATH()
        return env
    }

    private func setupOutputHandlers(stdout: Pipe, stderr: Pipe) {
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                // EOF — process closed stdout. Stop the handler to prevent CPU spin.
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                let cleaned = Self.stripANSI(text)
                if !cleaned.isEmpty {
                    self?.onOutput?(cleaned)
                }
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                let cleaned = Self.stripANSI(text)
                if !cleaned.isEmpty {
                    self?.onOutput?(cleaned)
                }
            }
        }
    }

    // MARK: - Path Resolution

    /// Build a comprehensive PATH string that includes common install locations.
    private func expandedPATH() -> String {
        var directories: [String] = []

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            directories.append(contentsOf: pathEnv.split(separator: ":").map(String.init))
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.npm/bin",
            "\(home)/.cargo/bin",
            "/usr/bin",
        ]

        for path in extraPaths where !directories.contains(path) {
            directories.append(path)
        }

        // nvm: check all installed node versions
        let nvmBase = "\(home)/.nvm/versions/node"
        if let nodeVersions = try? FileManager.default.contentsOfDirectory(atPath: nvmBase) {
            for version in nodeVersions {
                let binPath = (nvmBase as NSString).appendingPathComponent(version).appending("/bin")
                if !directories.contains(binPath) {
                    directories.append(binPath)
                }
            }
        }

        return directories.joined(separator: ":")
    }

    private func resolveExecutable(_ command: String) -> String? {
        if command.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }

        for dir in expandedPATH().split(separator: ":").map(String.init) {
            let fullPath = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: fullPath) {
                return fullPath
            }
        }

        return resolveViaShell(command)
    }

    private func resolveViaShell(_ command: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shell)
        proc.arguments = ["-lc", "which \(command)"]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let path, !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        } catch {
            logger.warning("Shell resolve failed for \(command): \(error.localizedDescription)")
        }

        return nil
    }

    // MARK: - ANSI Stripping

    private static let ansiRegex: NSRegularExpression = {
        let pattern = "\\x1B(?:\\[[0-9;?]*[a-zA-Z]|\\][^\u{07}]*\u{07}|\\(B)"
        return try! NSRegularExpression(pattern: pattern, options: [])
    }()

    static func stripANSI(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        var result = ansiRegex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        result = result.replacingOccurrences(of: "\r", with: "")
        return result
    }
}
