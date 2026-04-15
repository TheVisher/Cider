import Foundation
import os

/// Persistent Codex app-server-backed runtime.
///
/// This keeps one long-lived Codex process alive and talks to it over the
/// app-server JSON-RPC protocol on stdio. Phase 1 supports a single active
/// thread with plain-text user input and plain-text final assistant output.
final class CodexProcessRuntime: @unchecked Sendable, ProcessAgentRuntime {
    let id = "process.codex-cli"
    let displayName = "Codex CLI"
    let kind: AgentRuntimeKind = .process
    let capabilities = AgentRuntimeCapabilities(
        supportsToolCalling: false,
        supportsStreaming: false,
        maxContextTokens: 0
    )

    let launchPath: String
    let arguments: [String]
    let workingDirectoryURL: URL
    let environment: [String: String]

    private let logger = Logger(subsystem: "com.cider.app", category: "CodexProcessRuntime")
    private let processManager = AgentProcessManager(loggerCategory: "CodexProcessManager")
    private let sessionState = SessionState()
    private let operationGate = AsyncOperationGate()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?
    private let startupTimeout: Duration = .seconds(20)
    private let turnTimeout: Duration = .seconds(120)
    private let initializeRetryCount = 1

    init(
        launchPath: String? = nil,
        workingDirectoryURL: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        arguments: [String] = ["app-server", "--listen", "stdio://"],
        environment: [String: String] = [:]
    ) {
        self.launchPath = launchPath ?? Self.resolveCodexPath()
        self.workingDirectoryURL = workingDirectoryURL
        self.arguments = arguments
        self.environment = Self.defaultEnvironment().merging(environment) { _, new in new }
    }

    func start() async throws {
        try await operationGate.run {
            try await self.startUnlocked()
        }
    }

    func stop() async {
        await operationGate.runVoid {
            self.stdoutTask?.cancel()
            self.stderrTask?.cancel()
            self.stdoutTask = nil
            self.stderrTask = nil
            await self.sessionState.resetForNewProcess()
            await self.processManager.stop()
        }
    }

    func health() async -> AgentRuntimeHealth {
        let base = await processManager.health()
        let threadID = await sessionState.threadID
        let detail = threadID == nil ? base.detail : "\(base.detail) — thread ready"
        return AgentRuntimeHealth(
            status: base.status,
            detail: detail,
            lastStartedAt: base.lastStartedAt,
            lastActivityAt: base.lastActivityAt,
            lastError: base.lastError
        )
    }

    func send(_ request: AgentRuntimeRequest) async throws -> AgentRuntimeResponse {
        try await operationGate.run {
            try await self.startUnlocked()
            await self.processManager.markActivity()

            let threadID = try await self.ensureThreadStarted()
            let requestID = await self.sessionState.nextRequestID()
            let turnText = self.buildTurnText(from: request)
            self.logger.info("Codex turn starting on thread \(threadID, privacy: .public) with request \(requestID, privacy: .public)")
            let turnPayload = self.makeTurnStartPayload(
                requestID: requestID,
                threadID: threadID,
                text: turnText
            )

            try await self.sessionState.prepareTurn(requestID: requestID)
            try await self.writeJSONObject(turnPayload)
            let responseText = try await self.withTimeout("turn/start \(requestID)", timeout: self.turnTimeout) { [self] in
                try await self.sessionState.waitForTurnCompletion(requestID: requestID)
            }
            self.logger.info("Codex turn completed for request \(requestID, privacy: .public)")
            return AgentRuntimeResponse(text: responseText, toolRequests: [])
        }
    }

    private func startUnlocked() async throws {
        let health = await processManager.health()
        if health.status == .running { return }

        try await processManager.start(
            launchPath: launchPath,
            arguments: arguments,
            workingDirectoryURL: workingDirectoryURL,
            environment: environment
        )

        guard let stdout = await processManager.stdoutHandle(),
              let stderr = await processManager.stderrHandle()
        else {
            throw AgentError.deliveryFailed("Codex process stdio pipes are unavailable")
        }

        await sessionState.resetForNewProcess()
        installReaders(stdout: stdout, stderr: stderr)
        logger.info("Codex runtime starting initialize handshake")
        try await sendInitialize()
        logger.info("Codex runtime initialize completed")
        try await ensureThreadStarted()
        logger.info("Codex runtime thread ready")
    }

    func stream(_ request: AgentRuntimeRequest) -> AsyncThrowingStream<AgentRuntimeEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await send(request)
                    continuation.yield(.done(response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetThread(_ threadID: UUID) async {
        await operationGate.runVoid {
            self.logger.info("resetThread requested for Codex runtime thread \(threadID.uuidString, privacy: .public)")
            await self.sessionState.clearThread()
        }
    }

    private func installReaders(stdout: FileHandle, stderr: FileHandle) {
        stdoutTask?.cancel()
        stderrTask?.cancel()

        stdoutTask = Task { [weak self] in
            guard let self else { return }
            await self.readLoop(from: stdout, source: "stdout")
        }

        stderrTask = Task { [weak self] in
            guard let self else { return }
            await self.readLoop(from: stderr, source: "stderr")
        }
    }

    private func sendInitialize() async throws {
        var lastError: Error?

        for attempt in 0...initializeRetryCount {
            let requestID = await sessionState.nextRequestID()
            try await sessionState.registerRequest(id: requestID)
            let payload: [String: Any] = [
                "jsonrpc": "2.0",
                "id": requestID,
                "method": "initialize",
                "params": [
                    "clientInfo": [
                        "name": "Cider",
                        "version": "0.1"
                    ]
                ]
            ]

            logger.debug("Codex initialize request attempt \(attempt + 1, privacy: .public) id \(requestID, privacy: .public)")

            do {
                try await writeJSONObject(payload)
                _ = try await withTimeout("initialize \(requestID)", timeout: self.startupTimeout) { [self] in
                    try await self.sessionState.waitForRequest(id: requestID)
                }
                await sessionState.setInitialized()
                return
            } catch {
                lastError = error
                logger.error("Codex initialize attempt \(attempt + 1, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                guard attempt < initializeRetryCount else { break }
            }
        }

        throw lastError ?? AgentError.deliveryFailed("Codex initialize failed")
    }

    @discardableResult
    private func ensureThreadStarted() async throws -> String {
        if let existing = await sessionState.threadID {
            return existing
        }

        let requestID = await sessionState.nextRequestID()
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "thread/start",
            "params": [
                "cwd": workingDirectoryURL.path,
                "approvalPolicy": "never",
                "sandbox": "danger-full-access",
                "experimentalRawEvents": false
            ]
        ]
        try await writeJSONObject(payload)
        return try await withTimeout("thread/start \(requestID)", timeout: self.startupTimeout) { [self] in
            try await self.sessionState.waitForThreadID()
        }
    }

    private func handleStdoutLine(_ line: String) async {
        logger.debug("Codex stdout raw: \(line, privacy: .public)")
        guard let data = line.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            logger.debug("Ignoring non-JSON Codex stdout line")
            return
        }

        if let id = raw["id"] as? String {
            logger.debug("Codex response received for id \(id, privacy: .public)")
            if let errorObject = raw["error"] as? [String: Any] {
                let message = errorObject["message"] as? String ?? "Unknown Codex error"
                await sessionState.failRequest(id: id, error: AgentError.deliveryFailed(message))
                return
            }
            if let result = raw["result"] as? [String: Any] {
                await sessionState.completeRequest(id: id, result: try? JSONSerialization.data(withJSONObject: result))
            }
            return
        }

        guard let method = raw["method"] as? String,
              let params = raw["params"] as? [String: Any]
        else {
            return
        }

        switch method {
        case "item/agentMessage/delta":
            let turnID = params["turnId"] as? String
            let delta = params["delta"] as? String ?? ""
            await sessionState.appendTurnDelta(turnID: turnID, delta: delta)
        case "item/completed":
            if let item = params["item"] as? [String: Any],
               let type = item["type"] as? String,
               type == "agentMessage",
               let turnID = params["turnId"] as? String,
               let text = item["text"] as? String {
                await sessionState.setTurnFinalText(turnID: turnID, text: text)
            }
        case "turn/completed":
            guard let turn = params["turn"] as? [String: Any],
                  let turnID = turn["id"] as? String
            else { return }
            logger.debug("Codex turn/completed for turn \(turnID, privacy: .public)")
            await sessionState.completeTurn(turnID: turnID)
        case "thread/started":
            if let thread = params["thread"] as? [String: Any],
               let threadID = thread["id"] as? String {
                logger.debug("Codex thread/started \(threadID, privacy: .public)")
                await sessionState.setThreadID(threadID)
            }
        default:
            break
        }
    }

    private func readLoop(from handle: FileHandle, source: String) async {
        var buffer = Data()

        while !Task.isCancelled {
            let chunk = handle.availableData
            if chunk.isEmpty { break }

            buffer.append(chunk)

            while let newlineIndex = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: newlineIndex)
                buffer.removeSubrange(...newlineIndex)
                guard let rawLine = String(data: lineData, encoding: .utf8) else { continue }
                let line = rawLine.trimmingCharacters(in: .newlines)
                guard !line.isEmpty else { continue }

                if source == "stdout" {
                    await processManager.markActivity()
                    await handleStdoutLine(line)
                } else {
                    logger.debug("Codex stderr: \(line, privacy: .public)")
                }
            }
        }

        if !buffer.isEmpty,
           let rawLine = String(data: buffer, encoding: .utf8) {
            let line = rawLine.trimmingCharacters(in: .newlines)
            if !line.isEmpty {
                if source == "stdout" {
                    await processManager.markActivity()
                    await handleStdoutLine(line)
                } else {
                    logger.debug("Codex stderr: \(line, privacy: .public)")
                }
            }
        }
    }

    private func writeJSONObject(_ object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let handle = await processManager.stdinHandle() else {
            throw AgentError.deliveryFailed("Codex stdin is unavailable")
        }
        try handle.write(contentsOf: data + Data([0x0A]))
    }

    private func makeTurnStartPayload(requestID: String, threadID: String, text: String) -> [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": requestID,
            "method": "turn/start",
            "params": [
                "threadId": threadID,
                "input": [
                    [
                        "type": "text",
                        "text": text,
                        "text_elements": []
                    ]
                ]
            ]
        ]
    }

    private func buildTurnText(from request: AgentRuntimeRequest) -> String {
        let latestUserText = request.messages.last(where: { $0.role == .user })?.content
            ?? request.messages.last?.content
            ?? ""

        var parts: [String] = []

        if !request.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("Cider instructions:\n\(request.systemPrompt)")
        }

        parts.append("Channel: \(request.channel.rawValue)")

        if !latestUserText.isEmpty {
            parts.append("User message:\n\(latestUserText)")
        }

        return parts.joined(separator: "\n\n")
    }

    private static func resolveCodexPath() -> String {
        let candidates = [
            "/usr/local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/Users/minivish/.local/bin/codex"
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        return "/usr/local/bin/codex"
    }

    private static func defaultEnvironment() -> [String: String] {
        let pathCandidates = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Users/minivish/.local/bin",
            "/Users/minivish/.bun/bin",
            "/Users/minivish/Library/pnpm",
            "/Users/minivish/.cargo/bin"
        ]

        let inherited = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":")
            .map(String.init) ?? []

        var combined: [String] = []
        for path in pathCandidates + inherited where !combined.contains(path) {
            combined.append(path)
        }

        return ["PATH": combined.joined(separator: ":")]
    }

    private func withTimeout<T: Sendable>(
        _ label: String,
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw AgentError.deliveryFailed("Codex runtime timed out during \(label)")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

private actor SessionState {
    enum SessionError: Error {
        case invalidState(String)
    }

    private var requestCounter = 0
    private(set) var initialized = false
    private(set) var threadID: String?
    private var completedRequests: [String: Result<Data, Error>] = [:]
    private var activeTurnRequestIDs: [String: String] = [:]
    private var activeTurnIDsByRequest: [String: String] = [:]
    private var activeTurnTexts: [String: String] = [:]
    private var completedTurns: [String: Result<String, Error>] = [:]

    func resetForNewProcess() {
        initialized = false
        threadID = nil
        completedRequests.removeAll()
        activeTurnRequestIDs.removeAll()
        activeTurnIDsByRequest.removeAll()
        activeTurnTexts.removeAll()
        completedTurns.removeAll()
    }

    func nextRequestID() -> String {
        requestCounter += 1
        return "cider-\(requestCounter)"
    }

    func setInitialized() {
        initialized = true
    }

    func setThreadID(_ id: String) {
        threadID = id
    }

    func clearThread() {
        threadID = nil
    }

    func registerRequest(id: String) throws {
        if completedRequests[id] != nil || activeTurnIDsByRequest[id] != nil {
            throw SessionError.invalidState("Duplicate request id: \(id)")
        }
    }

    func waitForRequest(id: String) async throws -> Data {
        while true {
            if let completed = completedRequests.removeValue(forKey: id) {
                return try completed.get()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func waitForThreadID() async throws -> String {
        while true {
            if let threadID {
                return threadID
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func completeRequest(id: String, result: Data?) {
        guard let result else {
            failRequest(id: id, error: SessionError.invalidState("Missing result data for request \(id)"))
            return
        }
        if let raw = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
           let turn = raw["turn"] as? [String: Any],
           let turnID = turn["id"] as? String {
            activeTurnIDsByRequest[id] = turnID
            activeTurnRequestIDs[turnID] = id
        }
        completedRequests[id] = .success(result)
    }

    func failRequest(id: String, error: Error) {
        completedRequests[id] = .failure(error)
        if let turnID = activeTurnIDsByRequest.removeValue(forKey: id) {
            activeTurnRequestIDs.removeValue(forKey: turnID)
            activeTurnTexts.removeValue(forKey: turnID)
            completedTurns[turnID] = .failure(error)
        }
    }

    func prepareTurn(requestID: String) throws {
        if completedRequests[requestID] != nil || activeTurnIDsByRequest[requestID] != nil {
            throw SessionError.invalidState("Turn request already pending: \(requestID)")
        }
    }

    func waitForTurnCompletion(requestID: String) async throws -> String {
        let turnID = try await waitForTurnID(requestID: requestID)
        while true {
            if let completed = completedTurns.removeValue(forKey: turnID) {
                return try completed.get()
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func waitForTurnID(requestID: String) async throws -> String {
        if let existing = activeTurnIDsByRequest[requestID] {
            return existing
        }

        while activeTurnIDsByRequest[requestID] == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        return activeTurnIDsByRequest[requestID]!
    }

    func appendTurnDelta(turnID: String?, delta: String) {
        guard let turnID else { return }
        activeTurnTexts[turnID, default: ""] += delta
    }

    func setTurnFinalText(turnID: String, text: String) {
        activeTurnTexts[turnID] = text
    }

    func completeTurn(turnID: String) {
        let text = activeTurnTexts.removeValue(forKey: turnID) ?? ""
        let requestID = activeTurnRequestIDs.removeValue(forKey: turnID)
        if let requestID {
            activeTurnIDsByRequest.removeValue(forKey: requestID)
        }
        completedTurns[turnID] = .success(text)
    }
}

private actor AsyncOperationGate {
    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    func runVoid(_ operation: @escaping @Sendable () async -> Void) async {
        await acquire()
        defer { release() }
        await operation()
    }

    private func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isHeld = false
            return
        }
        let next = waiters.removeFirst()
        next.resume()
    }
}
