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
