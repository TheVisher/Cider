import Foundation
import SQLite3
import os

struct HermesConversationState: Codable, Equatable, Sendable {
    var conversationID: UUID
    var runtimeID: String
    var activeRuntimeSessionID: String
    var runtimeSessionLineage: [String]
    var title: String?
    var source: String?
    var lastSyncedAt: Date?

    init(
        conversationID: UUID = UUID(),
        runtimeID: String = "hermes",
        activeRuntimeSessionID: String,
        runtimeSessionLineage: [String]? = nil,
        title: String? = nil,
        source: String? = nil,
        lastSyncedAt: Date? = nil
    ) {
        self.conversationID = conversationID
        self.runtimeID = runtimeID
        self.activeRuntimeSessionID = activeRuntimeSessionID
        self.runtimeSessionLineage = runtimeSessionLineage ?? [activeRuntimeSessionID]
        self.title = title
        self.source = source
        self.lastSyncedAt = lastSyncedAt
    }
}

struct HermesSessionContinuation: Equatable, Sendable {
    let activeSessionID: String
    let lineage: [String]
    let title: String?
    let source: String?
}

struct HermesTranscript: Equatable, Sendable {
    let sessionID: String
    let source: String?
    let title: String?
    let messages: [HermesTranscriptMessage]
}

struct HermesTranscriptMessage: Equatable, Sendable {
    let externalID: String
    let sourceSessionID: String
    let role: AIAssistantMessage.Role
    let content: String
    let timestamp: Date
}

enum HermesSessionClientError: Error, LocalizedError {
    case stateDatabaseUnavailable(String)
    case sqlitePrepare(String)
    case sqliteStep(String)
    case sessionNotFound(String)
    case hermesExecutableUnavailable(String)
    case hermesCommandFailed(String)
    case invalidTranscript

    var errorDescription: String? {
        switch self {
        case .stateDatabaseUnavailable(let path):
            return "Hermes state database is unavailable at \(path)"
        case .sqlitePrepare(let detail):
            return "Hermes SQLite prepare failed: \(detail)"
        case .sqliteStep(let detail):
            return "Hermes SQLite step failed: \(detail)"
        case .sessionNotFound(let id):
            return "Hermes session not found: \(id)"
        case .hermesExecutableUnavailable(let path):
            return "Hermes executable is unavailable at \(path)"
        case .hermesCommandFailed(let detail):
            return "Hermes command failed: \(detail)"
        case .invalidTranscript:
            return "Hermes transcript export could not be decoded"
        }
    }
}

struct HermesSessionContinuationResolver {
    let stateDatabaseURL: URL

    init(stateDatabaseURL: URL = HermesPaths.defaultStateDatabaseURL) {
        self.stateDatabaseURL = stateDatabaseURL
    }

    func resolveContinuation(from sessionID: String) throws -> HermesSessionContinuation {
        var db: OpaquePointer?
        guard sqlite3_open_v2(stateDatabaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw HermesSessionClientError.stateDatabaseUnavailable(stateDatabaseURL.path)
        }
        defer { sqlite3_close(db) }

        guard let startingRecord = try sessionRecord(id: sessionID, db: db) else {
            throw HermesSessionClientError.sessionNotFound(sessionID)
        }

        var active = startingRecord
        var lineage = [startingRecord.id]
        var seen = Set(lineage)

        while let child = try newestChild(of: active.id, db: db), !seen.contains(child.id) {
            active = child
            lineage.append(child.id)
            seen.insert(child.id)
        }

        return HermesSessionContinuation(
            activeSessionID: active.id,
            lineage: lineage,
            title: active.title,
            source: active.source
        )
    }

    func latestSession(source preferredSource: String? = "telegram") throws -> HermesSessionContinuation? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(stateDatabaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw HermesSessionClientError.stateDatabaseUnavailable(stateDatabaseURL.path)
        }
        defer { sqlite3_close(db) }

        if let preferredSource,
           let preferred = try latestSessionRecord(source: preferredSource, db: db) {
            return try resolveContinuation(from: preferred.id)
        }

        guard let any = try latestSessionRecord(source: nil, db: db) else { return nil }
        return try resolveContinuation(from: any.id)
    }

    private func sessionRecord(id: String, db: OpaquePointer?) throws -> HermesSessionRecord? {
        var stmt: OpaquePointer?
        let sql = "SELECT id, source, title FROM sessions WHERE id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HermesSessionClientError.sqlitePrepare(errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            return HermesSessionRecord(stmt: stmt)
        }
        if result == SQLITE_DONE { return nil }
        throw HermesSessionClientError.sqliteStep(errorMessage(db))
    }

    private func newestChild(of sessionID: String, db: OpaquePointer?) throws -> HermesSessionRecord? {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, source, title
        FROM sessions
        WHERE parent_session_id = ?
        ORDER BY started_at DESC
        LIMIT 1;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HermesSessionClientError.sqlitePrepare(errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)

        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            return HermesSessionRecord(stmt: stmt)
        }
        if result == SQLITE_DONE { return nil }
        throw HermesSessionClientError.sqliteStep(errorMessage(db))
    }

    private func latestSessionRecord(source: String?, db: OpaquePointer?) throws -> HermesSessionRecord? {
        var stmt: OpaquePointer?
        let sql: String
        if source == nil {
            sql = """
            SELECT id, source, title
            FROM sessions
            ORDER BY started_at DESC
            LIMIT 1;
            """
        } else {
            sql = """
            SELECT id, source, title
            FROM sessions
            WHERE source = ?
            ORDER BY started_at DESC
            LIMIT 1;
            """
        }

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HermesSessionClientError.sqlitePrepare(errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        if let source {
            sqlite3_bind_text(stmt, 1, source, -1, SQLITE_TRANSIENT)
        }

        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            return HermesSessionRecord(stmt: stmt)
        }
        if result == SQLITE_DONE { return nil }
        throw HermesSessionClientError.sqliteStep(errorMessage(db))
    }

    private func errorMessage(_ db: OpaquePointer?) -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }
}

enum HermesTranscriptParser {
    static func parse(_ data: Data) throws -> HermesTranscript {
        let decoder = JSONDecoder()
        let export = try decoder.decode(HermesSessionExport.self, from: data)
        let messages = export.messages.compactMap { exported -> HermesTranscriptMessage? in
            guard let role = AIAssistantMessage.Role(rawValue: exported.role),
                  role == .user || role == .assistant,
                  let content = exported.content?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty
            else {
                return nil
            }

            let sourceSessionID = exported.sessionID ?? export.id
            return HermesTranscriptMessage(
                externalID: "hermes:\(sourceSessionID):\(exported.flexibleID.stringValue)",
                sourceSessionID: sourceSessionID,
                role: role,
                content: content,
                timestamp: Date(timeIntervalSince1970: exported.timestamp ?? Date().timeIntervalSince1970)
            )
        }

        return HermesTranscript(
            sessionID: export.id,
            source: export.source,
            title: export.title,
            messages: messages
        )
    }
}

enum HermesTranscriptMerger {
    static func merge(
        existing: [AIAssistantMessage],
        incoming: [HermesTranscriptMessage]
    ) -> [AIAssistantMessage] {
        var seen = Set(existing.compactMap(\.sourceID))
        var merged = existing

        for message in incoming.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard !seen.contains(message.externalID) else { continue }
            merged.append(AIAssistantMessage(
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                sourceID: message.externalID,
                sourceSessionID: message.sourceSessionID,
                sourceName: "Hermes"
            ))
            seen.insert(message.externalID)
        }

        return merged
    }
}

final class HermesSessionService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.cider.app", category: "HermesSessionService")
    private let resolver: HermesSessionContinuationResolver
    private let runner: HermesCommandRunning

    init(
        stateDatabaseURL: URL = HermesPaths.defaultStateDatabaseURL,
        runner: HermesCommandRunning = HermesProcessRunner()
    ) {
        self.resolver = HermesSessionContinuationResolver(stateDatabaseURL: stateDatabaseURL)
        self.runner = runner
    }

    func attachLatestTelegramConversation(conversationID: UUID = UUID()) async throws -> HermesSyncResult {
        guard let latest = try resolver.latestSession(source: "telegram") else {
            throw HermesSessionClientError.sessionNotFound("latest telegram session")
        }
        let state = HermesConversationState(
            conversationID: conversationID,
            activeRuntimeSessionID: latest.activeSessionID,
            runtimeSessionLineage: latest.lineage,
            title: latest.title,
            source: latest.source
        )
        return try await sync(state: state, existingMessages: [])
    }

    func sync(
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        let continuation = try resolver.resolveContinuation(from: state.activeRuntimeSessionID)
        let transcriptData = try await runner.runHermes(arguments: [
            "sessions", "export",
            "--session-id", continuation.activeSessionID,
            "-"
        ])
        let transcript = try HermesTranscriptParser.parse(transcriptData)
        let merged = HermesTranscriptMerger.merge(existing: existingMessages, incoming: transcript.messages)

        var nextState = state
        nextState.activeRuntimeSessionID = continuation.activeSessionID
        nextState.runtimeSessionLineage = mergedLineage(state.runtimeSessionLineage, continuation.lineage)
        nextState.title = transcript.title ?? continuation.title ?? state.title
        nextState.source = transcript.source ?? continuation.source ?? state.source
        nextState.lastSyncedAt = Date()

        return HermesSyncResult(state: nextState, messages: merged)
    }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        let continuation = try resolver.resolveContinuation(from: state.activeRuntimeSessionID)
        _ = try await runner.runHermes(arguments: [
            "chat",
            "--resume", continuation.activeSessionID,
            "--query", text,
            "--quiet"
        ], timeout: 180)

        var nextState = state
        nextState.activeRuntimeSessionID = continuation.activeSessionID
        nextState.runtimeSessionLineage = mergedLineage(state.runtimeSessionLineage, continuation.lineage)
        return try await sync(state: nextState, existingMessages: existingMessages)
    }

    private func mergedLineage(_ existing: [String], _ incoming: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for id in existing + incoming where !seen.contains(id) {
            result.append(id)
            seen.insert(id)
        }
        return result
    }
}

struct HermesSyncResult: Sendable {
    let state: HermesConversationState
    let messages: [AIAssistantMessage]
}

protocol HermesCommandRunning: Sendable {
    func runHermes(arguments: [String], timeout: TimeInterval) async throws -> Data
}

extension HermesCommandRunning {
    func runHermes(arguments: [String]) async throws -> Data {
        try await runHermes(arguments: arguments, timeout: 30)
    }
}

struct HermesProcessRunner: HermesCommandRunning {
    let executablePath: String
    let workingDirectoryURL: URL

    init(
        executablePath: String = HermesPaths.resolveHermesExecutablePath(),
        workingDirectoryURL: URL = StoragePaths.cachedVaultDirectoryURL
    ) {
        self.executablePath = executablePath
        self.workingDirectoryURL = workingDirectoryURL
    }

    func runHermes(arguments: [String], timeout: TimeInterval) async throws -> Data {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw HermesSessionClientError.hermesExecutableUnavailable(executablePath)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectoryURL
            process.standardOutput = stdout
            process.standardError = stderr

            let completion = HermesProcessCompletionBox(continuation: continuation)
            let stdoutBuffer = HermesPipeBuffer()
            let stderrBuffer = HermesPipeBuffer()

            stdout.fileHandleForReading.readabilityHandler = { handle in
                stdoutBuffer.append(handle.availableData)
            }
            stderr.fileHandleForReading.readabilityHandler = { handle in
                stderrBuffer.append(handle.availableData)
            }

            process.terminationHandler = { proc in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                stdoutBuffer.append(stdout.fileHandleForReading.readDataToEndOfFile())
                stderrBuffer.append(stderr.fileHandleForReading.readDataToEndOfFile())
                if proc.terminationStatus == 0 {
                    completion.finish(.success(stdoutBuffer.data()))
                } else {
                    let detail = String(data: stderrBuffer.data(), encoding: .utf8) ?? "exit \(proc.terminationStatus)"
                    completion.finish(.failure(HermesSessionClientError.hermesCommandFailed(detail)))
                }
            }

            do {
                try process.run()
            } catch {
                completion.finish(.failure(error))
                return
            }

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                if process.isRunning {
                    process.terminate()
                    completion.finish(.failure(HermesSessionClientError.hermesCommandFailed("Timed out after \(Int(timeout)) seconds")))
                }
            }
        }
    }
}

private final class HermesPipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        storage.append(data)
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class HermesProcessCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Data, Error>

    init(continuation: CheckedContinuation<Data, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Data, Error>) {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return
        }
        completed = true
        lock.unlock()
        continuation.resume(with: result)
    }
}

enum HermesPaths {
    static var defaultStateDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("state.db")
    }

    static func resolveHermesExecutablePath() -> String {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/hermes").path,
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "hermes"
    }
}

private struct HermesSessionRecord {
    let id: String
    let source: String?
    let title: String?

    init(stmt: OpaquePointer?) {
        id = String(cString: sqlite3_column_text(stmt, 0))
        source = Self.optionalString(stmt, 1)
        title = Self.optionalString(stmt, 2)
    }

    private static func optionalString(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index)
        else {
            return nil
        }
        return String(cString: cString)
    }
}

private struct HermesSessionExport: Decodable {
    let id: String
    let source: String?
    let title: String?
    let messages: [HermesExportedMessage]
}

private struct HermesExportedMessage: Decodable {
    let flexibleID: FlexibleJSONID
    let sessionID: String?
    let role: String
    let content: String?
    let timestamp: Double?

    enum CodingKeys: String, CodingKey {
        case flexibleID = "id"
        case sessionID = "session_id"
        case role
        case content
        case timestamp
    }
}

private enum FlexibleJSONID: Decodable {
    case string(String)
    case int(Int)

    var stringValue: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
            return
        }
        self = .string(try container.decode(String.self))
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
