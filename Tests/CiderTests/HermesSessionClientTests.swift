import Foundation
import SQLite3
import Testing
@testable import Cider

struct HermesSessionClientTests {
    @Test("continuation resolver follows newest child sessions")
    func continuationResolverFollowsNewestChildSessions() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)

        try insertSession(
            id: "20260501_100416_ebff7f",
            parent: "20260501_045533_cce0d1c1",
            source: "telegram",
            title: "Cider Vault Agent #2",
            startedAt: 100,
            dbURL: dbURL
        )
        try insertSession(
            id: "20260501_114444_443f9e",
            parent: "20260501_100416_ebff7f",
            source: "telegram",
            title: "Cider Vault Agent #3",
            startedAt: 200,
            dbURL: dbURL
        )
        try insertSession(
            id: "20260501_120144_e3d994",
            parent: "20260501_114444_443f9e",
            source: "telegram",
            title: "Cider Vault Agent #4",
            startedAt: 300,
            dbURL: dbURL
        )

        let resolver = HermesSessionContinuationResolver(stateDatabaseURL: dbURL)
        let continuation = try resolver.resolveContinuation(from: "20260501_100416_ebff7f")

        #expect(continuation.activeSessionID == "20260501_120144_e3d994")
        #expect(continuation.lineage == [
            "20260501_100416_ebff7f",
            "20260501_114444_443f9e",
            "20260501_120144_e3d994"
        ])
        #expect(continuation.title == "Cider Vault Agent #4")
        #expect(continuation.source == "telegram")
    }

    @Test("continuation resolver reads WAL-mode state database without sidecars")
    func continuationResolverReadsWALModeStateDatabaseWithoutSidecars() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)
        try insertSession(
            id: "wal-session",
            parent: nil,
            source: "cider",
            title: "WAL Session",
            startedAt: 100,
            dbURL: dbURL
        )
        try markDatabaseAsWALModeAndRemoveSidecars(dbURL)

        let resolver = HermesSessionContinuationResolver(stateDatabaseURL: dbURL)
        let continuation = try resolver.resolveContinuation(from: "wal-session")

        #expect(continuation.activeSessionID == "wal-session")
        #expect(continuation.lineage == ["wal-session"])
        #expect(continuation.title == "WAL Session")
    }

    @Test("service attaches explicitly chosen session")
    func serviceAttachesExplicitlyChosenSession() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)
        try insertSession(
            id: "session-a",
            parent: nil,
            source: "telegram",
            title: "Chosen Session",
            startedAt: 100,
            dbURL: dbURL
        )
        try insertSession(
            id: "session-b",
            parent: "session-a",
            source: "telegram",
            title: "Chosen Session Continued",
            startedAt: 200,
            dbURL: dbURL
        )

        let runner = StubHermesRunner(data: Data("""
        {
          "id": "session-b",
          "source": "telegram",
          "title": "Chosen Session Continued",
          "messages": [
            {
              "id": 1,
              "session_id": "session-b",
              "role": "assistant",
              "content": "attached",
              "timestamp": 1777662106.25
            }
          ]
        }
        """.utf8))
        let service = HermesSessionService(stateDatabaseURL: dbURL, runner: runner)
        let conversationID = UUID()

        let result = try await service.attachConversation(sessionID: "session-a", conversationID: conversationID)

        #expect(result.state.conversationID == conversationID)
        #expect(result.state.activeRuntimeSessionID == "session-b")
        #expect(result.state.runtimeSessionLineage == ["session-a", "session-b"])
        #expect(result.messages.map(\.content) == ["attached"])
    }

    @Test("fresh Cider session starts a new Hermes CLI session")
    func freshCiderSessionStartsNewHermesCLISession() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)

        let runner = StubHermesRunner(data: Data("""
        {
          "id": "fresh-cider-session",
          "source": "cider",
          "title": "Fresh Cider",
          "messages": [
            {
              "id": 1,
              "session_id": "fresh-cider-session",
              "role": "user",
              "content": "hello",
              "timestamp": 1777662105.25
            },
            {
              "id": 2,
              "session_id": "fresh-cider-session",
              "role": "assistant",
              "content": "fresh response",
              "timestamp": 1777662106.25
            }
          ]
        }
        """.utf8)) { arguments in
            if arguments.first == "chat" {
                #expect(arguments == [
                    "chat",
                    "--query", "hello",
                    "--quiet",
                    "--source", "cider"
                ])
                try insertSession(
                    id: "fresh-cider-session",
                    parent: nil,
                    source: "cider",
                    title: "Fresh Cider",
                    startedAt: 400,
                    dbURL: dbURL
                )
            }
        }
        let service = HermesSessionService(stateDatabaseURL: dbURL, runner: runner)
        let state = HermesConversationState(
            activeRuntimeSessionID: "",
            runtimeSessionLineage: [],
            title: "Main Brain",
            source: "cider"
        )

        let result = try await service.send(text: "hello", state: state, existingMessages: [])

        #expect(result.state.activeRuntimeSessionID == "fresh-cider-session")
        #expect(result.state.runtimeSessionLineage == ["fresh-cider-session"])
        #expect(result.messages.map(\.content) == ["hello", "fresh response"])
    }

    @Test("service renames Hermes session with sanitized title")
    func serviceRenamesHermesSessionWithSanitizedTitle() async throws {
        let runner = StubHermesRunner(data: Data()) { arguments in
            #expect(arguments == [
                "sessions",
                "rename",
                "session-a",
                "Cider Dashboard Worktree"
            ])
        }
        let service = HermesSessionService(runner: runner)

        try await service.renameSession(sessionID: " session-a ", title: " Cider   Dashboard Worktree ")
    }

    @Test("service repairs stale session by Hermes title")
    func serviceRepairsStaleSessionByHermesTitle() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)
        try insertSession(
            id: "old-unrelated",
            parent: nil,
            source: "telegram",
            title: "Cider Scratchpad",
            startedAt: 100,
            dbURL: dbURL
        )
        try insertSession(
            id: "recovered-root",
            parent: nil,
            source: "cider",
            title: "Cider Scratchpad",
            startedAt: 200,
            dbURL: dbURL
        )
        try insertSession(
            id: "recovered-child",
            parent: "recovered-root",
            source: "cider",
            title: "Cider Scratchpad",
            startedAt: 300,
            dbURL: dbURL
        )

        let runner = StubHermesRunner(data: Data("""
        {
          "id": "recovered-child",
          "source": "cider",
          "title": "Cider Scratchpad",
          "messages": [
            {
              "id": 7,
              "session_id": "recovered-child",
              "role": "assistant",
              "content": "recovered",
              "timestamp": 1777662106.25
            }
          ]
        }
        """.utf8)) { arguments in
            #expect(arguments == [
                "sessions", "export",
                "--session-id", "recovered-child",
                "-"
            ])
        }
        let service = HermesSessionService(stateDatabaseURL: dbURL, runner: runner)
        let conversationID = UUID()
        let state = HermesConversationState(
            conversationID: conversationID,
            activeRuntimeSessionID: "missing-session",
            runtimeSessionLineage: ["missing-session"],
            title: " Cider Scratchpad ",
            source: "cider"
        )

        let result = try await service.repairConversation(
            state: state,
            existingMessages: []
        )

        #expect(result.state.conversationID == conversationID)
        #expect(result.state.activeRuntimeSessionID == "recovered-child")
        #expect(result.state.runtimeSessionLineage == ["recovered-root", "recovered-child"])
        #expect(result.state.title == "Cider Scratchpad")
        #expect(result.state.source == "cider")
        #expect(result.state.lastSyncedMessageID == "hermes:recovered-child:7")
        #expect(result.state.lastImportedRuntimeSessionID == "recovered-child")
        #expect(result.messages.map(\.content) == ["recovered"])
    }

    @Test("main brain sync follows newer Telegram branch")
    func mainBrainSyncFollowsNewerTelegramBranch() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)
        try insertSession(
            id: "telegram-root",
            parent: nil,
            source: "telegram",
            title: "Main Brain",
            startedAt: 100,
            dbURL: dbURL
        )
        try insertSession(
            id: "cli-current",
            parent: "telegram-root",
            source: "cli",
            title: "Main Brain CLI",
            startedAt: 200,
            dbURL: dbURL
        )
        try insertSession(
            id: "telegram-new",
            parent: "telegram-root",
            source: "telegram",
            title: "Main Brain Telegram",
            startedAt: 300,
            dbURL: dbURL
        )

        let runner = StubHermesRunner(data: Data("""
        {
          "id": "telegram-new",
          "source": "telegram",
          "title": "Main Brain Telegram",
          "messages": [
            {
              "id": 1,
              "session_id": "telegram-new",
              "role": "user",
              "content": "sent from telegram",
              "timestamp": 1777662105.25
            }
          ]
        }
        """.utf8)) { arguments in
            #expect(arguments == [
                "sessions", "export",
                "--session-id", "telegram-new",
                "-"
            ])
        }
        let service = HermesSessionService(stateDatabaseURL: dbURL, runner: runner)
        let state = HermesConversationState(
            activeRuntimeSessionID: "cli-current",
            runtimeSessionLineage: ["telegram-root", "cli-current"],
            title: "Main Brain",
            source: "cli"
        )

        let result = try await service.syncMainBrain(state: state, existingMessages: [])

        #expect(result.state.activeRuntimeSessionID == "telegram-new")
        #expect(result.state.runtimeSessionLineage == ["telegram-new"])
        #expect(result.state.source == "telegram")
        #expect(result.messages.map(\.content) == ["sent from telegram"])
    }

    @Test("main brain sync imports updated Telegram lineage without leaving active Cider child")
    func mainBrainSyncImportsUpdatedTelegramLineageWithoutLeavingActiveCiderChild() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("state.db")
        try makeHermesStateDB(at: dbURL)
        try insertSession(
            id: "telegram-parent",
            parent: nil,
            source: "telegram",
            title: "Main Brain Telegram",
            startedAt: 100,
            dbURL: dbURL
        )
        try insertSession(
            id: "cider-child",
            parent: "telegram-parent",
            source: "cli",
            title: "Main Brain Cider",
            startedAt: 200,
            dbURL: dbURL
        )

        let runner = MappingHermesRunner(exports: [
            "cider-child": Data("""
            {
              "id": "cider-child",
              "source": "cli",
              "title": "Main Brain Cider",
              "messages": [
                {
                  "id": 1,
                  "session_id": "cider-child",
                  "role": "assistant",
                  "content": "copied parent answer",
                  "timestamp": 1777662105.25
                }
              ]
            }
            """.utf8),
            "telegram-parent": Data("""
            {
              "id": "telegram-parent",
              "source": "telegram",
              "title": "Main Brain Telegram",
              "messages": [
                {
                  "id": 1,
                  "session_id": "telegram-parent",
                  "role": "assistant",
                  "content": "copied parent answer",
                  "timestamp": 1777662105.25
                },
                {
                  "id": 2,
                  "session_id": "telegram-parent",
                  "role": "user",
                  "content": "new telegram question",
                  "timestamp": 1777662205.25
                },
                {
                  "id": 3,
                  "session_id": "telegram-parent",
                  "role": "assistant",
                  "content": "new telegram answer",
                  "timestamp": 1777662206.25
                }
              ]
            }
            """.utf8)
        ])
        let service = HermesSessionService(stateDatabaseURL: dbURL, runner: runner)
        let state = HermesConversationState(
            activeRuntimeSessionID: "cider-child",
            runtimeSessionLineage: ["telegram-parent", "cider-child"],
            title: "Main Brain",
            source: "cli"
        )
        let existing = [
            AIAssistantMessage(
                role: .assistant,
                content: "copied parent answer",
                sourceID: "hermes:cider-child:1",
                sourceSessionID: "cider-child",
                sourceName: "Hermes"
            )
        ]

        let result = try await service.syncMainBrain(state: state, existingMessages: existing)

        #expect(result.state.activeRuntimeSessionID == "cider-child")
        #expect(result.state.runtimeSessionLineage == ["telegram-parent", "cider-child"])
        #expect(result.messages.map(\.content) == [
            "copied parent answer",
            "new telegram question",
            "new telegram answer"
        ])
        #expect(result.messages.map(\.sourceSessionID) == [
            "cider-child",
            "telegram-parent",
            "telegram-parent"
        ])
        #expect(result.state.lastSyncedMessageID == "hermes:telegram-parent:3")
        #expect(result.state.lastSyncedTimestamp == Date(timeIntervalSince1970: 1_777_662_206.25))
        #expect(result.state.lastImportedRuntimeSessionID == "telegram-parent")
    }

    @Test("transcript parser imports chat messages and skips tool rows")
    func transcriptParserImportsChatMessagesAndSkipsToolRows() throws {
        let json = """
        {
          "id": "20260501_120144_e3d994",
          "source": "telegram",
          "title": "Cider Vault Agent #4",
          "messages": [
            {
              "id": 1,
              "session_id": "20260501_120144_e3d994",
              "role": "user",
              "content": "hello hermes",
              "timestamp": 1777662104.5
            },
            {
              "id": 2,
              "session_id": "20260501_120144_e3d994",
              "role": "tool",
              "content": "internal tool result",
              "timestamp": 1777662105.0
            },
            {
              "id": 3,
              "session_id": "20260501_120144_e3d994",
              "role": "assistant",
              "content": "hello from hermes",
              "timestamp": 1777662106.25
            }
          ]
        }
        """

        let transcript = try HermesTranscriptParser.parse(Data(json.utf8))

        #expect(transcript.sessionID == "20260501_120144_e3d994")
        #expect(transcript.messages.map(\.role) == [.user, .assistant])
        #expect(transcript.messages.map(\.content) == ["hello hermes", "hello from hermes"])
        #expect(transcript.messages.map(\.externalID) == [
            "hermes:20260501_120144_e3d994:1",
            "hermes:20260501_120144_e3d994:3"
        ])
    }

    @Test("transcript parser imports multimodal message content")
    func transcriptParserImportsMultimodalMessageContent() throws {
        let json = """
        {
          "id": "20260501_153629_cdd4b7",
          "source": "telegram",
          "title": "Cider Vault Agent #5",
          "messages": [
            {
              "id": 1197,
              "session_id": "20260501_153629_cdd4b7",
              "role": "user",
              "content": [
                {
                  "type": "text",
                  "text": "Here is the screenshot from Cider."
                },
                {
                  "type": "image_url",
                  "image_url": {
                    "url": "data:image/jpeg;base64,aGVsbG8="
                  }
                }
              ],
              "timestamp": 1777674271.0
            }
          ]
        }
        """

        let transcript = try HermesTranscriptParser.parse(Data(json.utf8))

        #expect(transcript.messages.count == 1)
        #expect(transcript.messages[0].content == "Here is the screenshot from Cider.")
        #expect(transcript.messages[0].attachments.count == 1)
        #expect(transcript.messages[0].attachments[0].kind == .image)
        #expect(transcript.messages[0].externalID == "hermes:20260501_153629_cdd4b7:1197")
    }

    @Test("session file parser imports messages without exported ids")
    func sessionFileParserImportsMessagesWithoutExportedIDs() throws {
        let json = """
        {
          "session_id": "20260501_212131_069f94",
          "messages": [
            {
              "role": "user",
              "content": "hello from local file"
            },
            {
              "role": "tool",
              "content": "internal tool result"
            },
            {
              "role": "assistant",
              "content": "hello from live Hermes"
            }
          ]
        }
        """

        let transcript = try HermesTranscriptParser.parseSessionFile(
            Data(json.utf8),
            sessionID: "fallback-session"
        )

        #expect(transcript.sessionID == "20260501_212131_069f94")
        #expect(transcript.messages.map(\.role) == [.user, .assistant])
        #expect(transcript.messages.map(\.content) == ["hello from local file", "hello from live Hermes"])
        #expect(transcript.messages.map(\.externalID) == [
            "hermes-live:20260501_212131_069f94:line-0",
            "hermes-live:20260501_212131_069f94:line-2"
        ])
    }

    @Test("message merge deduplicates by Hermes message id")
    func messageMergeDeduplicatesByHermesMessageID() {
        let existing = [
            AIAssistantMessage(
                role: .user,
                content: "hello hermes",
                sourceID: "hermes:session-a:1",
                sourceSessionID: "session-a",
                sourceName: "Hermes"
            )
        ]
        let incoming = [
            HermesTranscriptMessage(
                externalID: "hermes:session-a:1",
                sourceSessionID: "session-a",
                role: .user,
                content: "hello hermes",
                attachments: [],
                timestamp: Date(timeIntervalSince1970: 1)
            ),
            HermesTranscriptMessage(
                externalID: "hermes:session-b:2",
                sourceSessionID: "session-b",
                role: .assistant,
                content: "hello from newer session",
                attachments: [],
                timestamp: Date(timeIntervalSince1970: 2)
            )
        ]

        let merged = HermesTranscriptMerger.merge(existing: existing, incoming: incoming)

        #expect(merged.count == 2)
        #expect(merged.map(\.content) == ["hello hermes", "hello from newer session"])
        #expect(merged[1].sourceID == "hermes:session-b:2")
    }

    @Test("message merge deduplicates live session rows already imported from export")
    func messageMergeDeduplicatesLiveRowsAlreadyImportedFromExport() {
        let existing = [
            AIAssistantMessage(
                role: .assistant,
                content: "Hermes is already here",
                timestamp: Date(timeIntervalSince1970: 10),
                sourceID: "hermes:session-a:42",
                sourceSessionID: "session-a",
                sourceName: "Hermes"
            )
        ]
        let incoming = [
            HermesTranscriptMessage(
                externalID: "hermes-live:session-a:line-2",
                sourceSessionID: "session-a",
                role: .assistant,
                content: "  Hermes   is already here  ",
                attachments: [],
                timestamp: Date(timeIntervalSince1970: 99)
            )
        ]

        let merged = HermesTranscriptMerger.merge(existing: existing, incoming: incoming)

        #expect(merged.count == 1)
        #expect(merged[0].sourceID == "hermes:session-a:42")
    }

    @Test("message merge preserves repeated exported Hermes messages")
    func messageMergePreservesRepeatedExportedHermesMessages() {
        let existing = [
            AIAssistantMessage(
                role: .assistant,
                content: "Saved.",
                sourceID: "hermes:session-a:41",
                sourceSessionID: "session-a",
                sourceName: "Hermes"
            )
        ]
        let incoming = [
            HermesTranscriptMessage(
                externalID: "hermes:session-a:42",
                sourceSessionID: "session-a",
                role: .assistant,
                content: "Saved.",
                attachments: [],
                timestamp: Date(timeIntervalSince1970: 11)
            )
        ]

        let merged = HermesTranscriptMerger.merge(existing: existing, incoming: incoming)

        #expect(merged.count == 2)
        #expect(merged.map(\.sourceID) == ["hermes:session-a:41", "hermes:session-a:42"])
    }

    @Test("message merge deduplicates copied Hermes rows across lineage sessions")
    func messageMergeDeduplicatesCopiedHermesRowsAcrossLineageSessions() {
        let existing = [
            AIAssistantMessage(
                role: .assistant,
                content: "same copied answer",
                sourceID: "hermes:cider-child:42",
                sourceSessionID: "cider-child",
                sourceName: "Hermes"
            )
        ]
        let incoming = [
            HermesTranscriptMessage(
                externalID: "hermes:telegram-parent:42",
                sourceSessionID: "telegram-parent",
                role: .assistant,
                content: "same copied answer",
                attachments: [],
                timestamp: Date(timeIntervalSince1970: 11)
            ),
            HermesTranscriptMessage(
                externalID: "hermes:telegram-parent:43",
                sourceSessionID: "telegram-parent",
                role: .assistant,
                content: "same copied answer",
                attachments: [],
                timestamp: Date(timeIntervalSince1970: 12)
            )
        ]

        let merged = HermesTranscriptMerger.merge(existing: existing, incoming: incoming)

        #expect(merged.count == 2)
        #expect(merged.map(\.sourceID) == [
            "hermes:cider-child:42",
            "hermes:telegram-parent:43"
        ])
    }

    private func makeHermesStateDB(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            throw TestSQLiteError.open
        }
        defer { sqlite3_close(db) }

        let sql = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            source TEXT NOT NULL,
            parent_session_id TEXT,
            started_at REAL NOT NULL,
            ended_at REAL,
            title TEXT
        );
        CREATE INDEX idx_sessions_parent ON sessions(parent_session_id);
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw TestSQLiteError.exec
        }
    }

    private func markDatabaseAsWALModeAndRemoveSidecars(_ dbURL: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw TestSQLiteError.open
        }
        defer { sqlite3_close(db) }

        guard sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil) == SQLITE_OK else {
            throw TestSQLiteError.exec
        }

        let sidecarPaths = [
            dbURL.path + "-wal",
            dbURL.path + "-shm"
        ]
        for path in sidecarPaths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private func insertSession(
        id: String,
        parent: String?,
        source: String,
        title: String,
        startedAt: Double,
        dbURL: URL
    ) throws {
        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            throw TestSQLiteError.open
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(
            db,
            "INSERT INTO sessions (id, source, parent_session_id, started_at, title) VALUES (?, ?, ?, ?, ?);",
            -1,
            &stmt,
            nil
        ) == SQLITE_OK else {
            throw TestSQLiteError.prepare
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_text(stmt, 2, source, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        if let parent {
            sqlite3_bind_text(stmt, 3, parent, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, 3)
        }
        sqlite3_bind_double(stmt, 4, startedAt)
        sqlite3_bind_text(stmt, 5, title, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw TestSQLiteError.step
        }
    }
}

private enum TestSQLiteError: Error {
    case open
    case exec
    case prepare
    case step
}

private struct StubHermesRunner: HermesCommandRunning {
    let data: Data
    var onRun: (@Sendable ([String]) async throws -> Void)?

    init(
        data: Data,
        onRun: (@Sendable ([String]) async throws -> Void)? = nil
    ) {
        self.data = data
        self.onRun = onRun
    }

    func runHermes(arguments: [String], timeout: TimeInterval) async throws -> Data {
        try await onRun?(arguments)
        return data
    }
}

private struct MappingHermesRunner: HermesCommandRunning {
    let exports: [String: Data]

    func runHermes(arguments: [String], timeout: TimeInterval) async throws -> Data {
        #expect(arguments.count == 5)
        #expect(arguments[0] == "sessions")
        #expect(arguments[1] == "export")
        #expect(arguments[2] == "--session-id")
        #expect(arguments[4] == "-")

        guard let data = exports[arguments[3]] else {
            throw HermesSessionClientError.sessionNotFound(arguments[3])
        }
        return data
    }
}
