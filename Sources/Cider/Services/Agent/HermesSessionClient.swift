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
    var lastSyncedMessageID: String?
    var lastSyncedTimestamp: Date?
    var lastImportedRuntimeSessionID: String?

    init(
        conversationID: UUID = UUID(),
        runtimeID: String = "hermes",
        activeRuntimeSessionID: String,
        runtimeSessionLineage: [String]? = nil,
        title: String? = nil,
        source: String? = nil,
        lastSyncedAt: Date? = nil,
        lastSyncedMessageID: String? = nil,
        lastSyncedTimestamp: Date? = nil,
        lastImportedRuntimeSessionID: String? = nil
    ) {
        self.conversationID = conversationID
        self.runtimeID = runtimeID
        self.activeRuntimeSessionID = activeRuntimeSessionID
        self.runtimeSessionLineage = runtimeSessionLineage ?? [activeRuntimeSessionID]
        self.title = title
        self.source = source
        self.lastSyncedAt = lastSyncedAt
        self.lastSyncedMessageID = lastSyncedMessageID
        self.lastSyncedTimestamp = lastSyncedTimestamp
        self.lastImportedRuntimeSessionID = lastImportedRuntimeSessionID
    }
}

struct HermesSessionContinuation: Equatable, Sendable {
    let activeSessionID: String
    let lineage: [String]
    let title: String?
    let source: String?
    let startedAt: Double
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
    let attachments: [AIAssistantAttachment]
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

    init(stateDatabaseURL: URL? = nil) {
        self.stateDatabaseURL = stateDatabaseURL ?? HermesPaths.defaultStateDatabaseURL
    }

    func resolveContinuation(from sessionID: String) throws -> HermesSessionContinuation {
        try withReadOnlyDatabase { db in
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
                source: active.source,
                startedAt: active.startedAt
            )
        }
    }

    func latestSession(source preferredSource: String, newerThan sessionID: String) throws -> HermesSessionContinuation? {
        try withReadOnlyDatabase { db in
            guard let current = try sessionRecord(id: sessionID, db: db),
                  let latest = try latestSessionRecord(source: preferredSource, db: db),
                  latest.startedAt > current.startedAt
            else { return nil }

            return try resolveContinuation(from: latest.id)
        }
    }

    func latestSession(source preferredSource: String? = "telegram") throws -> HermesSessionContinuation? {
        try withReadOnlyDatabase { db in
            if let preferredSource,
               let preferred = try latestSessionRecord(source: preferredSource, db: db) {
                return try resolveContinuation(from: preferred.id)
            }

            guard let any = try latestSessionRecord(source: nil, db: db) else { return nil }
            return try resolveContinuation(from: any.id)
        }
    }

    func latestSession(title: String) throws -> HermesSessionContinuation? {
        let trimmedTitle = CiderAgentChatRegistry.sanitizedHermesTitle(title)
        guard !trimmedTitle.isEmpty else { return nil }

        return try withReadOnlyDatabase { db in
            guard let latest = try latestSessionRecord(title: trimmedTitle, db: db) else {
                return nil
            }

            let lineage = try lineageEnding(at: latest.id, db: db)
            return HermesSessionContinuation(
                activeSessionID: latest.id,
                lineage: lineage.isEmpty ? [latest.id] : lineage,
                title: latest.title,
                source: latest.source,
                startedAt: latest.startedAt
            )
        }
    }

    func sessionIDs(source preferredSource: String, in sessionIDs: [String]) throws -> [String] {
        guard !sessionIDs.isEmpty else { return [] }

        return try withReadOnlyDatabase { db in
            var matching = Set<String>()
            for sessionID in sessionIDs {
                guard let record = try sessionRecord(id: sessionID, db: db),
                      record.source == preferredSource
                else { continue }
                matching.insert(record.id)
            }

            return sessionIDs.filter { matching.contains($0) }
        }
    }

    private func withReadOnlyDatabase<T>(_ operation: (OpaquePointer?) throws -> T) throws -> T {
        if shouldOpenImmutableReadOnlyDatabaseFirst {
            return try withDatabase(
                path: immutableReadOnlyDatabaseURI(),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
                operation
            )
        }

        do {
            return try withDatabase(
                path: stateDatabaseURL.path,
                flags: SQLITE_OPEN_READONLY,
                operation
            )
        } catch let error as HermesSessionClientError
            where error.shouldRetryWithImmutableReadOnlyDatabase {
            return try withDatabase(
                path: immutableReadOnlyDatabaseURI(),
                flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI,
                operation
            )
        }
    }

    private func withDatabase<T>(
        path: String,
        flags: Int32,
        _ operation: (OpaquePointer?) throws -> T
    ) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw HermesSessionClientError.stateDatabaseUnavailable(stateDatabaseURL.path)
        }
        defer { sqlite3_close(db) }

        return try operation(db)
    }

    private var shouldOpenImmutableReadOnlyDatabaseFirst: Bool {
        FileManager.default.fileExists(atPath: stateDatabaseURL.path)
            && !FileManager.default.fileExists(atPath: stateDatabaseURL.path + "-wal")
    }

    private func immutableReadOnlyDatabaseURI() -> String {
        let allowedCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "?"))
        let encodedPath = stateDatabaseURL.path.addingPercentEncoding(withAllowedCharacters: allowedCharacters)
            ?? stateDatabaseURL.path
        return "file:\(encodedPath)?mode=ro&immutable=1"
    }

    private func sessionRecord(id: String, db: OpaquePointer?) throws -> HermesSessionRecord? {
        var stmt: OpaquePointer?
        let sql = "SELECT id, source, title, started_at FROM sessions WHERE id = ? LIMIT 1;"
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

    private func parentSessionID(of sessionID: String, db: OpaquePointer?) throws -> String? {
        var stmt: OpaquePointer?
        let sql = "SELECT parent_session_id FROM sessions WHERE id = ? LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HermesSessionClientError.sqlitePrepare(errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, sessionID, -1, SQLITE_TRANSIENT)

        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            guard sqlite3_column_type(stmt, 0) != SQLITE_NULL,
                  let rawParent = sqlite3_column_text(stmt, 0)
            else { return nil }
            return String(cString: rawParent)
        }
        if result == SQLITE_DONE { return nil }
        throw HermesSessionClientError.sqliteStep(errorMessage(db))
    }

    private func lineageEnding(at sessionID: String, db: OpaquePointer?) throws -> [String] {
        var lineage = [sessionID]
        var seen = Set(lineage)
        var current = sessionID

        while let parent = try parentSessionID(of: current, db: db), !seen.contains(parent) {
            lineage.insert(parent, at: 0)
            seen.insert(parent)
            current = parent
        }

        return lineage
    }

    private func newestChild(of sessionID: String, db: OpaquePointer?) throws -> HermesSessionRecord? {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, source, title, started_at
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
            SELECT id, source, title, started_at
            FROM sessions
            ORDER BY started_at DESC
            LIMIT 1;
            """
        } else {
            sql = """
            SELECT id, source, title, started_at
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

    private func latestSessionRecord(title: String, db: OpaquePointer?) throws -> HermesSessionRecord? {
        var stmt: OpaquePointer?
        let sql = """
        SELECT id, source, title, started_at
        FROM sessions
        WHERE title = ?
        ORDER BY started_at DESC
        LIMIT 1;
        """

        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw HermesSessionClientError.sqlitePrepare(errorMessage(db))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, title, -1, SQLITE_TRANSIENT)

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

private extension HermesSessionClientError {
    var shouldRetryWithImmutableReadOnlyDatabase: Bool {
        switch self {
        case .stateDatabaseUnavailable:
            return true
        case .sqlitePrepare(let detail), .sqliteStep(let detail):
            return detail.localizedCaseInsensitiveContains("unable to open database")
                || detail.localizedCaseInsensitiveContains("cannot open file")
        default:
            return false
        }
    }
}

enum HermesTranscriptParser {
    static func parse(_ data: Data) throws -> HermesTranscript {
        let decoder = JSONDecoder()
        let export = try decoder.decode(HermesSessionExport.self, from: data)
        return transcript(
            sessionID: export.id,
            source: export.source,
            title: export.title,
            messages: export.messages,
            externalIDPrefix: "hermes"
        )
    }

    static func parseSessionFile(_ data: Data, sessionID fallbackSessionID: String) throws -> HermesTranscript {
        let decoder = JSONDecoder()
        let sessionFile = try decoder.decode(HermesSessionFile.self, from: data)
        return transcript(
            sessionID: sessionFile.id ?? fallbackSessionID,
            source: sessionFile.source,
            title: sessionFile.title,
            messages: sessionFile.messages,
            externalIDPrefix: "hermes-live"
        )
    }

    private static func transcript(
        sessionID: String,
        source: String?,
        title: String?,
        messages exportedMessages: [HermesExportedMessage],
        externalIDPrefix: String
    ) -> HermesTranscript {
        let baseTimestamp = Date().timeIntervalSince1970 - Double(exportedMessages.count)
        let messages = exportedMessages.enumerated().compactMap { offset, exported -> HermesTranscriptMessage? in
            let sourceSessionID = exported.sessionID ?? sessionID
            let messageID = exported.flexibleID?.stringValue ?? "line-\(offset)"
            let externalID = "\(externalIDPrefix):\(sourceSessionID):\(messageID)"
            let content = exported.content?.displayText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let attachments = exported.content?.attachments(
                sourceSessionID: sourceSessionID,
                messageID: messageID
            ) ?? []
            guard let role = AIAssistantMessage.Role(rawValue: exported.role),
                  role == .user || role == .assistant,
                  !content.isEmpty || !attachments.isEmpty
            else {
                return nil
            }

            return HermesTranscriptMessage(
                externalID: externalID,
                sourceSessionID: sourceSessionID,
                role: role,
                content: content,
                attachments: attachments,
                timestamp: Date(timeIntervalSince1970: exported.timestamp ?? (baseTimestamp + Double(offset)))
            )
        }

        return HermesTranscript(
            sessionID: sessionID,
            source: source,
            title: title,
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
        var seenLiveExportFingerprints: [String: Set<HermesMessageSourceStyle>] = [:]
        var seenLineageCopyFingerprints = Set<String>()
        for message in existing {
            guard let fingerprint = liveExportFingerprint(for: message),
                  let style = HermesMessageSourceStyle(sourceID: message.sourceID)
            else {
                if let fingerprint = lineageCopyFingerprint(for: message) {
                    seenLineageCopyFingerprints.insert(fingerprint)
                }
                continue
            }
            seenLiveExportFingerprints[fingerprint, default: []].insert(style)
            if let fingerprint = lineageCopyFingerprint(for: message) {
                seenLineageCopyFingerprints.insert(fingerprint)
            }
        }
        var merged = existing

        for message in incoming.sorted(by: { $0.timestamp < $1.timestamp }) {
            guard !seen.contains(message.externalID) else { continue }
            let style = HermesMessageSourceStyle(sourceID: message.externalID)
            let fingerprint = liveExportFingerprint(for: message)
            if let style,
               let fingerprint,
               seenLiveExportFingerprints[fingerprint]?.contains(style.counterpart) == true {
                continue
            }
            let lineageCopyFingerprint = lineageCopyFingerprint(for: message)
            if let lineageCopyFingerprint,
               seenLineageCopyFingerprints.contains(lineageCopyFingerprint) {
                continue
            }

            merged.append(AIAssistantMessage(
                role: message.role,
                content: message.content,
                timestamp: message.timestamp,
                sourceID: message.externalID,
                sourceSessionID: message.sourceSessionID,
                sourceName: "Hermes",
                attachments: message.attachments
            ))
            seen.insert(message.externalID)
            if let style, let fingerprint {
                seenLiveExportFingerprints[fingerprint, default: []].insert(style)
            }
            if let lineageCopyFingerprint {
                seenLineageCopyFingerprints.insert(lineageCopyFingerprint)
            }
        }

        return merged
    }

    private static func lineageCopyFingerprint(for message: AIAssistantMessage) -> String? {
        lineageCopyFingerprint(
            sourceID: message.sourceID,
            role: message.role,
            content: message.content,
            attachmentCount: message.attachments.count
        )
    }

    private static func lineageCopyFingerprint(for message: HermesTranscriptMessage) -> String? {
        lineageCopyFingerprint(
            sourceID: message.externalID,
            role: message.role,
            content: message.content,
            attachmentCount: message.attachments.count
        )
    }

    private static func lineageCopyFingerprint(
        sourceID: String?,
        role: AIAssistantMessage.Role,
        content: String,
        attachmentCount: Int
    ) -> String? {
        guard HermesMessageSourceStyle(sourceID: sourceID) == .export,
              let messageID = hermesMessageID(sourceID: sourceID),
              !messageID.hasPrefix("line-")
        else { return nil }

        let normalizedContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return [
            messageID,
            role.rawValue,
            normalizedContent,
            String(attachmentCount)
        ].joined(separator: "|")
    }

    private static func hermesMessageID(sourceID: String?) -> String? {
        guard let sourceID,
              sourceID.hasPrefix("hermes:"),
              let separatorIndex = sourceID.lastIndex(of: ":")
        else { return nil }
        return String(sourceID[sourceID.index(after: separatorIndex)...])
    }

    private static func liveExportFingerprint(for message: AIAssistantMessage) -> String? {
        guard let sourceSessionID = message.sourceSessionID,
              HermesMessageSourceStyle(sourceID: message.sourceID) != nil
        else { return nil }
        return liveExportFingerprint(
            sourceSessionID: sourceSessionID,
            role: message.role,
            content: message.content,
            attachmentCount: message.attachments.count
        )
    }

    private static func liveExportFingerprint(for message: HermesTranscriptMessage) -> String? {
        guard HermesMessageSourceStyle(sourceID: message.externalID) != nil else { return nil }
        return liveExportFingerprint(
            sourceSessionID: message.sourceSessionID,
            role: message.role,
            content: message.content,
            attachmentCount: message.attachments.count
        )
    }

    private static func liveExportFingerprint(
        sourceSessionID: String,
        role: AIAssistantMessage.Role,
        content: String,
        attachmentCount: Int
    ) -> String {
        let normalizedContent = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return [
            sourceSessionID,
            role.rawValue,
            normalizedContent,
            String(attachmentCount)
        ].joined(separator: "|")
    }
}

private enum HermesMessageSourceStyle: Hashable {
    case export
    case live

    init?(sourceID: String?) {
        guard let sourceID else { return nil }
        if sourceID.hasPrefix("hermes-live:") {
            self = .live
        } else if sourceID.hasPrefix("hermes:") {
            self = .export
        } else {
            return nil
        }
    }

    var counterpart: HermesMessageSourceStyle {
        switch self {
        case .export:
            return .live
        case .live:
            return .export
        }
    }
}

final class HermesSessionService: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.cider.app", category: "HermesSessionService")
    private let resolver: HermesSessionContinuationResolver
    private let runner: HermesCommandRunning

    init(
        stateDatabaseURL: URL? = nil,
        runner: HermesCommandRunning? = nil
    ) {
        self.resolver = HermesSessionContinuationResolver(stateDatabaseURL: stateDatabaseURL)
        self.runner = runner ?? HermesProcessRunner()
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

    func attachConversation(
        sessionID: String,
        conversationID: UUID = UUID()
    ) async throws -> HermesSyncResult {
        let trimmedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSessionID.isEmpty else {
            throw HermesSessionClientError.sessionNotFound("empty session id")
        }
        let continuation = try resolver.resolveContinuation(from: trimmedSessionID)
        let state = HermesConversationState(
            conversationID: conversationID,
            activeRuntimeSessionID: continuation.activeSessionID,
            runtimeSessionLineage: continuation.lineage,
            title: continuation.title,
            source: continuation.source
        )
        return try await sync(state: state, existingMessages: [])
    }

    func sync(
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        let continuation = try resolver.resolveContinuation(from: state.activeRuntimeSessionID)
        let transcript = try await transcript(for: continuation)
        let merged = HermesTranscriptMerger.merge(existing: existingMessages, incoming: transcript.messages)

        var nextState = state
        nextState.activeRuntimeSessionID = continuation.activeSessionID
        nextState.runtimeSessionLineage = reconciledLineage(
            existing: state.runtimeSessionLineage,
            continuation: continuation.lineage
        )
        nextState.title = transcript.title ?? continuation.title ?? state.title
        nextState.source = transcript.source ?? continuation.source ?? state.source
        nextState.lastSyncedAt = Date()
        nextState.updateSyncCursor(from: transcript.messages, importedSessionID: continuation.activeSessionID)

        return HermesSyncResult(state: nextState, messages: merged)
    }

    func repairConversation(
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        let title = CiderAgentChatRegistry.sanitizedHermesTitle(state.title ?? "")
        guard !title.isEmpty else {
            throw HermesSessionClientError.sessionNotFound("Hermes session title for repair")
        }
        guard let continuation = try resolver.latestSession(title: title) else {
            throw HermesSessionClientError.sessionNotFound(title)
        }

        var repairedState = state
        repairedState.activeRuntimeSessionID = continuation.activeSessionID
        repairedState.runtimeSessionLineage = continuation.lineage
        repairedState.title = continuation.title ?? title
        repairedState.source = continuation.source ?? state.source
        return try await sync(state: repairedState, existingMessages: existingMessages)
    }

    func syncMainBrain(
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        var stateToSync = state
        if let latestTelegram = try resolver.latestSession(
            source: "telegram",
            newerThan: state.activeRuntimeSessionID
        ) {
            stateToSync.activeRuntimeSessionID = latestTelegram.activeSessionID
            stateToSync.runtimeSessionLineage = reconciledLineage(
                existing: state.runtimeSessionLineage,
                continuation: latestTelegram.lineage
            )
            stateToSync.title = latestTelegram.title ?? state.title
            stateToSync.source = latestTelegram.source ?? state.source
        }

        let synced = try await sync(state: stateToSync, existingMessages: existingMessages)
        let supplementalSessionIDs = try resolver.sessionIDs(
            source: "telegram",
            in: synced.state.runtimeSessionLineage
        ).filter { $0 != synced.state.activeRuntimeSessionID }

        guard !supplementalSessionIDs.isEmpty else { return synced }

        var nextState = synced.state
        var merged = synced.messages
        for sessionID in supplementalSessionIDs {
            let transcript = try await transcript(sessionID: sessionID)
            merged = HermesTranscriptMerger.merge(existing: merged, incoming: transcript.messages)
            nextState.updateSyncCursor(from: transcript.messages, importedSessionID: sessionID)
        }

        return HermesSyncResult(state: nextState, messages: merged)
    }

    func send(
        text: String,
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        let nextState = try await runSendCommand(text: text, state: state)
        return try await sync(state: nextState, existingMessages: existingMessages)
    }

    func runSendCommand(text: String, state: HermesConversationState) async throws -> HermesConversationState {
        if state.activeRuntimeSessionID.isEmpty {
            return try await runNewSessionCommand(text: text, state: state)
        }

        let continuation = try resolver.resolveContinuation(from: state.activeRuntimeSessionID)
        _ = try await runner.runHermes(arguments: [
            "chat",
            "--resume", continuation.activeSessionID,
            "--query", text,
            "--quiet"
        ], timeout: 180)

        var nextState = state
        nextState.activeRuntimeSessionID = continuation.activeSessionID
        nextState.runtimeSessionLineage = reconciledLineage(
            existing: state.runtimeSessionLineage,
            continuation: continuation.lineage
        )
        return nextState
    }

    func renameSession(sessionID: String, title: String) async throws {
        let trimmedSessionID = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = CiderAgentChatRegistry.sanitizedHermesTitle(title)
        guard !trimmedSessionID.isEmpty else {
            throw HermesSessionClientError.sessionNotFound("empty session id")
        }
        guard !trimmedTitle.isEmpty else {
            throw HermesSessionClientError.hermesCommandFailed("Hermes session title is empty")
        }

        _ = try await runner.runHermes(arguments: [
            "sessions",
            "rename",
            trimmedSessionID,
            trimmedTitle
        ])
    }

    private func runNewSessionCommand(text: String, state: HermesConversationState) async throws -> HermesConversationState {
        let source = state.source?.isEmpty == false ? state.source! : "cider"
        _ = try await runner.runHermes(arguments: [
            "chat",
            "--query", text,
            "--quiet",
            "--source", source
        ], timeout: 180)

        guard let continuation = try resolver.latestSession(source: source) else {
            throw HermesSessionClientError.sessionNotFound("new \(source) session")
        }

        var nextState = state
        nextState.activeRuntimeSessionID = continuation.activeSessionID
        nextState.runtimeSessionLineage = reconciledLineage(
            existing: state.runtimeSessionLineage,
            continuation: continuation.lineage
        )
        nextState.title = continuation.title ?? state.title
        nextState.source = continuation.source ?? state.source
        return nextState
    }

    func syncFromSessionFile(
        state: HermesConversationState,
        existingMessages: [AIAssistantMessage]
    ) async throws -> HermesSyncResult {
        let continuation = try resolver.resolveContinuation(from: state.activeRuntimeSessionID)
        let sessionFileURL = HermesPaths.sessionFileURL(sessionID: continuation.activeSessionID)
        let transcriptData = try Data(contentsOf: sessionFileURL)
        let transcript = try HermesTranscriptParser.parseSessionFile(
            transcriptData,
            sessionID: continuation.activeSessionID
        )
        let merged = HermesTranscriptMerger.merge(existing: existingMessages, incoming: transcript.messages)

        var nextState = state
        nextState.activeRuntimeSessionID = continuation.activeSessionID
        nextState.runtimeSessionLineage = reconciledLineage(
            existing: state.runtimeSessionLineage,
            continuation: continuation.lineage
        )
        nextState.title = transcript.title ?? continuation.title ?? state.title
        nextState.source = transcript.source ?? continuation.source ?? state.source
        nextState.lastSyncedAt = Date()
        nextState.updateSyncCursor(from: transcript.messages, importedSessionID: continuation.activeSessionID)

        return HermesSyncResult(state: nextState, messages: merged)
    }

    private func reconciledLineage(existing: [String], continuation: [String]) -> [String] {
        guard let continuationHead = continuation.first else { return [] }
        guard let overlap = existing.firstIndex(of: continuationHead) else {
            return continuation
        }
        return Array(existing.prefix(through: overlap)) + continuation.dropFirst()
    }

    private func transcript(for continuation: HermesSessionContinuation) async throws -> HermesTranscript {
        try await transcript(sessionID: continuation.activeSessionID)
    }

    private func transcript(sessionID: String) async throws -> HermesTranscript {
        let transcriptData = try await runner.runHermes(arguments: [
            "sessions", "export",
            "--session-id", sessionID,
            "-"
        ])
        let exported = try HermesTranscriptParser.parse(transcriptData)
        if !exported.messages.isEmpty {
            return exported
        }

        let sessionFileURL = HermesPaths.sessionFileURL(sessionID: sessionID)
        guard let sessionFileData = try? Data(contentsOf: sessionFileURL),
              let liveTranscript = try? HermesTranscriptParser.parseSessionFile(
                sessionFileData,
                sessionID: sessionID
              ),
              !liveTranscript.messages.isEmpty
        else {
            return exported
        }

        return liveTranscript
    }
}

struct HermesSyncResult: Sendable {
    let state: HermesConversationState
    let messages: [AIAssistantMessage]
}

private extension HermesConversationState {
    mutating func updateSyncCursor(
        from messages: [HermesTranscriptMessage],
        importedSessionID: String
    ) {
        lastImportedRuntimeSessionID = importedSessionID
        guard let newestHermesMessage = messages.max(by: { $0.timestamp < $1.timestamp })
        else { return }

        lastSyncedMessageID = newestHermesMessage.externalID
        lastSyncedTimestamp = newestHermesMessage.timestamp
    }
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
    let environment: [String: String]?
    let cliExecutionAllowed: Bool

    init(
        executablePath: String? = nil,
        workingDirectoryURL: URL? = nil,
        environment: [String: String]? = nil,
        cliExecutionAllowed: Bool? = nil,
        isolationConfiguration: IsolationConfiguration? = nil
    ) {
        IsolationRuntime.recordPathAccess("HermesProcessRunner.init")
        let isolation = isolationConfiguration ?? IsolationRuntime.configuration
        if isolation.isDogfood {
            self.executablePath = isolation.hermesExecutable!.path
            self.workingDirectoryURL = isolation.hermesWorkingDirectory!
            self.environment = environment ?? isolation.hermesChildEnvironment(apiKey: isolation.hermesAPIKey!)
            self.cliExecutionAllowed = cliExecutionAllowed ?? false
        } else {
            self.executablePath = executablePath ?? HermesPaths.resolveHermesExecutablePath()
            self.workingDirectoryURL = workingDirectoryURL ?? StoragePaths.cachedVaultDirectoryURL
            self.environment = environment
            self.cliExecutionAllowed = cliExecutionAllowed ?? true
        }
    }

    func runHermes(arguments: [String], timeout: TimeInterval) async throws -> Data {
        guard cliExecutionAllowed else {
            throw HermesSessionClientError.hermesCommandFailed("Hermes CLI fallback is disabled in isolation mode")
        }
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
            if let environment {
                process.environment = environment
            }
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
        IsolationRuntime.recordPathAccess("HermesPaths.defaultStateDatabaseURL")
        if let isolated = IsolationRuntime.configuration.hermesStateDatabaseURL {
            return isolated
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("state.db")
    }

    static func resolveHermesExecutablePath() -> String {
        IsolationRuntime.recordPathAccess("HermesPaths.resolveHermesExecutablePath")
        if let isolated = IsolationRuntime.configuration.hermesExecutable {
            return isolated.path
        }
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/hermes").path,
            "/opt/homebrew/bin/hermes",
            "/usr/local/bin/hermes"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "hermes"
    }

    static func sessionFileURL(sessionID: String) -> URL {
        IsolationRuntime.recordPathAccess("HermesPaths.sessionFileURL")
        if let isolated = IsolationRuntime.configuration.hermesSessionsRoot {
            return isolated.appendingPathComponent("session_\(sessionID).json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
            .appendingPathComponent("session_\(sessionID).json")
    }
}

private struct HermesSessionRecord {
    let id: String
    let source: String?
    let title: String?
    let startedAt: Double

    init(stmt: OpaquePointer?) {
        id = String(cString: sqlite3_column_text(stmt, 0))
        source = Self.optionalString(stmt, 1)
        title = Self.optionalString(stmt, 2)
        startedAt = sqlite3_column_double(stmt, 3)
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

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case source
        case title
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .id) {
            self.id = id
        } else {
            self.id = try container.decode(String.self, forKey: .sessionID)
        }
        source = try container.decodeIfPresent(String.self, forKey: .source)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        messages = try container.decode([HermesExportedMessage].self, forKey: .messages)
    }
}

private struct HermesSessionFile: Decodable {
    let id: String?
    let source: String?
    let title: String?
    let messages: [HermesExportedMessage]

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case source
        case title
        case messages
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .sessionID)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        messages = try container.decode([HermesExportedMessage].self, forKey: .messages)
    }
}

private struct HermesExportedMessage: Decodable {
    let flexibleID: FlexibleJSONID?
    let sessionID: String?
    let role: String
    let content: HermesMessageContent?
    let timestamp: Double?

    enum CodingKeys: String, CodingKey {
        case flexibleID = "id"
        case sessionID = "session_id"
        case role
        case content
        case timestamp
    }
}

private enum HermesMessageContent: Decodable {
    case string(String)
    case parts([HermesMessageContentPart])

    var displayText: String {
        switch self {
        case .string(let value):
            return value
        case .parts(let parts):
            let lines = parts.compactMap(\.displayText)
            return lines.joined(separator: "\n")
        }
    }

    func attachments(sourceSessionID: String, messageID: String) -> [AIAssistantAttachment] {
        guard case .parts(let parts) = self else { return [] }
        return parts.enumerated().compactMap { index, part in
            guard part.isImage, let url = part.imageURL?.url else { return nil }
            return HermesImageAttachmentCache.attachment(
                dataURLOrRemoteURL: url,
                sourceSessionID: sourceSessionID,
                messageID: messageID,
                partIndex: index
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        self = .parts(try container.decode([HermesMessageContentPart].self))
    }
}

private struct HermesMessageContentPart: Decodable {
    let type: String?
    let text: String?
    let imageURL: HermesImageURL?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    var displayText: String? {
        let trimmedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedText, !trimmedText.isEmpty {
            return trimmedText
        }

        return nil
    }

    var isImage: Bool {
        type == "image_url" || type == "input_image"
    }
}

private struct HermesImageURL: Decodable {
    let url: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            url = string
            return
        }

        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        url = try keyed.decode(String.self, forKey: .url)
    }

    private enum CodingKeys: String, CodingKey {
        case url
    }
}

private enum HermesImageAttachmentCache {
    static func attachment(
        dataURLOrRemoteURL url: String,
        sourceSessionID: String,
        messageID: String,
        partIndex: Int
    ) -> AIAssistantAttachment? {
        if url.hasPrefix("data:image/") {
            return cacheDataURL(url, sourceSessionID: sourceSessionID, messageID: messageID, partIndex: partIndex)
        }

        guard URL(string: url) != nil else { return nil }
        return AIAssistantAttachment(
            id: "hermes-image-\(sourceSessionID)-\(messageID)-\(partIndex)",
            kind: .image,
            remoteURL: url,
            altText: "Image attachment"
        )
    }

    private static func cacheDataURL(
        _ dataURL: String,
        sourceSessionID: String,
        messageID: String,
        partIndex: Int
    ) -> AIAssistantAttachment? {
        guard let commaIndex = dataURL.firstIndex(of: ",") else { return nil }
        let header = String(dataURL[..<commaIndex])
        let payload = String(dataURL[dataURL.index(after: commaIndex)...])
        guard header.contains(";base64"),
              let mimeType = header
                .dropFirst("data:".count)
                .split(separator: ";")
                .first
                .map(String.init),
              let imageData = Data(base64Encoded: payload)
        else {
            return nil
        }

        let fileURL = cacheDirectory()
            .appendingPathComponent(fileStem(sourceSessionID: sourceSessionID, messageID: messageID, partIndex: partIndex))
            .appendingPathExtension(fileExtension(for: mimeType))

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try imageData.write(to: fileURL, options: .atomic)
            }
            return AIAssistantAttachment(
                id: "hermes-image-\(sourceSessionID)-\(messageID)-\(partIndex)",
                kind: .image,
                mimeType: mimeType,
                localFilePath: fileURL.path,
                altText: "Image attachment"
            )
        } catch {
            return nil
        }
    }

    private static func cacheDirectory() -> URL {
        StoragePaths.cachedVaultDirectoryURL
            .appendingPathComponent(StoragePaths.ciderInternalDir, isDirectory: true)
            .appendingPathComponent("ai-attachments", isDirectory: true)
            .appendingPathComponent("hermes", isDirectory: true)
    }

    private static func fileStem(sourceSessionID: String, messageID: String, partIndex: Int) -> String {
        "\(safeFileComponent(sourceSessionID))-\(safeFileComponent(messageID))-\(partIndex)"
    }

    private static func safeFileComponent(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" ? character : "_"
        }
        .reduce(into: "") { $0.append($1) }
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/jpeg", "image/jpg":
            return "jpg"
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        default:
            return "img"
        }
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
