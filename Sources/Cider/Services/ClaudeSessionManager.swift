import Foundation
import os.log

/// Manages Claude Code agent sessions — CRUD, process spawning per message.
///
/// Architecture: Each user message spawns a new `claude -p "..." --output-format stream-json` process.
/// Multi-turn conversation is maintained via `--resume SESSION_ID` (Claude's own session ID,
/// returned in the `system` stream event). The process runs until the response is complete, then exits.
@MainActor
final class ClaudeSessionManager: ObservableObject {
    static let shared = ClaudeSessionManager()

    @Published private(set) var sessions: [ClaudeSession] = []

    /// Currently running process per session (at most one at a time).
    private var processes: [UUID: Process] = [:]
    private var readTasks: [UUID: Task<Void, Never>] = [:]
    /// Accumulates partial assistant text between tool-use boundaries.
    private var pendingAssistantText: [UUID: String] = [:]
    /// Cached path to the `claude` binary.
    private var cachedClaudePath: String?

    private let logger = Logger(subsystem: "com.cider.app", category: "ClaudeSessionManager")

    private var sessionsDir: URL {
        StoragePaths.directoryURL(for: .claudeSessions)
    }

    private var dataFileURL: URL {
        sessionsDir.appendingPathComponent("_cider_claude_sessions.json")
    }

    private init() {
        ensureDirectory()
        load()
    }

    // MARK: - Directory

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
    }

    // MARK: - CRUD

    @discardableResult
    func createSession(name: String, projectPath: String) -> ClaudeSession {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Agent" : trimmed
        let session = ClaudeSession(name: finalName, projectPath: projectPath)
        sessions.append(session)
        persist()
        return session
    }

    func deleteSession(_ id: UUID) {
        stopSession(id)
        sessions.removeAll { $0.id == id }
        persist()
    }

    func session(for id: UUID) -> ClaudeSession? {
        sessions.first { $0.id == id }
    }

    // MARK: - Path Resolution

    /// Resolve the full path to the `claude` binary by checking common locations
    /// and falling back to a login shell lookup (since GUI apps don't inherit shell PATH).
    private func resolveClaudePath() -> String? {
        if let cached = cachedClaudePath, FileManager.default.isExecutableFile(atPath: cached) {
            return cached
        }
        let knownPaths = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(NSHomeDirectory())/.npm/bin/claude",
            "\(NSHomeDirectory())/.local/bin/claude",
            "/Applications/cmux.app/Contents/Resources/bin/claude",
        ]
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedClaudePath = path
                return path
            }
        }
        // Fall back to login shell resolution
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/bin/zsh")
        whichProcess.arguments = ["-l", "-c", "which claude"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        whichProcess.standardError = FileHandle.nullDevice
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !result.isEmpty && FileManager.default.isExecutableFile(atPath: result) {
                cachedClaudePath = result
                return result
            }
        } catch {
            logger.error("Failed to resolve claude path via shell: \(error.localizedDescription)")
        }
        return nil
    }

    /// Build an environment dict that includes the user's shell PATH,
    /// since macOS GUI apps only get the minimal system PATH.
    private var cachedShellEnv: [String: String]?
    private func shellEnvironment() -> [String: String] {
        if let cached = cachedShellEnv { return cached }
        var env = ProcessInfo.processInfo.environment
        let shellPath = Process()
        shellPath.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shellPath.arguments = ["-l", "-c", "echo $PATH"]
        let pipe = Pipe()
        shellPath.standardOutput = pipe
        shellPath.standardError = FileHandle.nullDevice
        do {
            try shellPath.run()
            shellPath.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
                env["PATH"] = path
            }
        } catch {
            // Fall back to system environment
        }
        cachedShellEnv = env
        return env
    }

    // MARK: - Message Sending (spawns process per message)

    func sendMessage(_ text: String, to id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }

        // Don't allow sending while a process is already running
        guard processes[id] == nil else {
            logger.warning("Process already running for session \(id), ignoring message")
            return
        }

        guard let claudePath = resolveClaudePath() else {
            sessions[index].status = .error("Claude CLI not found. Install it or check your PATH.")
            persist()
            return
        }

        // Add user message
        let userMsg = ClaudeSessionMessage(role: .user, content: text)
        sessions[index].messages.append(userMsg)
        sessions[index].status = .working
        sessions[index].updatedAt = Date()
        persist()

        // Build arguments
        var args = ["-p", text, "--output-format", "stream-json", "--verbose", "--dangerously-skip-permissions"]
        if let claudeSessionID = sessions[index].claudeSessionID {
            args += ["--resume", claudeSessionID]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: claudePath)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: sessions[index].projectPath)
        process.environment = shellEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            logger.error("Failed to start Claude process: \(error.localizedDescription)")
            sessions[index].status = .error(error.localizedDescription)
            persist()
            return
        }

        processes[id] = process

        // Read stdout
        let stdoutHandle = stdoutPipe.fileHandleForReading
        readTasks[id] = Task { [weak self] in
            do {
                for try await line in stdoutHandle.bytes.lines {
                    guard !Task.isCancelled else { break }
                    await MainActor.run { self?.handleStreamLine(line, sessionID: id) }
                }
            } catch {
                // Stream ended
            }
            await MainActor.run { self?.handleProcessExit(sessionID: id) }
        }

        // Read stderr for error reporting
        let stderrHandle = stderrPipe.fileHandleForReading
        Task { [weak self] in
            var stderrLines: [String] = []
            do {
                for try await line in stderrHandle.bytes.lines {
                    stderrLines.append(line)
                    self?.logger.warning("Claude stderr [\(id)]: \(line)")
                }
            } catch { /* stream ended */ }
            if !stderrLines.isEmpty {
                let errorText = stderrLines.suffix(3).joined(separator: "\n")
                await MainActor.run {
                    guard let self else { return }
                    if let idx = self.sessions.firstIndex(where: { $0.id == id }) {
                        if case .stopped = self.sessions[idx].status {
                            self.sessions[idx].status = .error(errorText)
                            self.persist()
                        }
                    }
                }
            }
        }

        process.terminationHandler = { [weak self] proc in
            self?.logger.info("Claude process exited with code \(proc.terminationStatus) for session \(id)")
        }
    }

    /// Stop a currently running process for a session.
    func stopSession(_ id: UUID) {
        readTasks[id]?.cancel()
        readTasks.removeValue(forKey: id)

        if let process = processes[id], process.isRunning {
            process.terminate()
        }
        processes.removeValue(forKey: id)
        pendingAssistantText.removeValue(forKey: id)

        if let index = sessions.firstIndex(where: { $0.id == id }) {
            sessions[index].status = .idle
            sessions[index].updatedAt = Date()
            persist()
        }
    }

    // MARK: - Stream Handling

    private func handleStreamLine(_ line: String, sessionID: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        guard let event = ClaudeStreamEvent.parse(line) else { return }

        switch event {
        case .system(let claudeID, _):
            // Capture Claude's session ID for --resume on subsequent messages
            if let claudeID, sessions[index].claudeSessionID == nil {
                sessions[index].claudeSessionID = claudeID
                logger.info("Captured Claude session ID: \(claudeID)")
            }

        case .assistantText(let text):
            pendingAssistantText[sessionID, default: ""] += text

        case .toolUse(let name, let input):
            flushPendingAssistantText(sessionID: sessionID, index: index)
            let preview = input.prefix(500)
            let msg = ClaudeSessionMessage(role: .toolUse, content: String(preview), toolName: name)
            sessions[index].messages.append(msg)

        case .toolResult(let name, let output):
            let preview = output.prefix(500)
            let msg = ClaudeSessionMessage(role: .toolResult, content: String(preview), toolName: name)
            sessions[index].messages.append(msg)

        case .result(let text, _):
            // Flush any remaining streamed text
            let hadPendingText = pendingAssistantText[sessionID] != nil
            flushPendingAssistantText(sessionID: sessionID, index: index)
            // Only add result text if we didn't already capture it via streaming events
            if !hadPendingText && !text.isEmpty {
                let msg = ClaudeSessionMessage(role: .assistant, content: text)
                sessions[index].messages.append(msg)
            }
            sessions[index].status = .idle

        case .unknown:
            break
        }

        sessions[index].updatedAt = Date()
        persist()
    }

    private func flushPendingAssistantText(sessionID: UUID, index: Int) {
        guard let text = pendingAssistantText.removeValue(forKey: sessionID), !text.isEmpty else { return }
        let msg = ClaudeSessionMessage(role: .assistant, content: text)
        sessions[index].messages.append(msg)
    }

    private func handleProcessExit(sessionID: UUID) {
        // Guard against double-call (readTask completion + terminationHandler both fire)
        guard processes.removeValue(forKey: sessionID) != nil else { return }
        readTasks.removeValue(forKey: sessionID)
        pendingAssistantText.removeValue(forKey: sessionID)

        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            // If still "working" when process exits, mark as idle (response complete)
            if case .working = sessions[index].status {
                sessions[index].status = .idle
            }
            sessions[index].updatedAt = Date()
            persist()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: dataFileURL.path) else { return }
        do {
            let data = try Data(contentsOf: dataFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var loaded = try decoder.decode([ClaudeSession].self, from: data)
            // Reset active statuses since processes don't survive restarts
            for i in loaded.indices {
                if case .working = loaded[i].status { loaded[i].status = .idle }
                if case .waitingForApproval = loaded[i].status { loaded[i].status = .idle }
            }
            sessions = loaded
        } catch {
            logger.error("Failed to load Claude sessions: \(error.localizedDescription)")
            sessions = []
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(sessions)
            try data.write(to: dataFileURL, options: .atomic)
        } catch {
            logger.error("Failed to persist Claude sessions: \(error.localizedDescription)")
        }
    }
}
