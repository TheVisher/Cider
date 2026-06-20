import Foundation
import Testing
@testable import Cider

@Suite("Note Item Update CLI Tests", .serialized)
@MainActor
struct NoteItemUpdateCLITests {
    @Test("item update note append keeps file database chunks search and read model coherent")
    func itemUpdateNoteAppendKeepsProjectionsCoherent() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let created = try createNote(title: "CID383 Blessed", content: "Original CID383 body", vault: vault)
        let noteID = try #require(created["id"] as? String)
        let relativePath = try #require(created["relativePath"] as? String)
        let appendedText = "Appended CID383 body via blessed path"

        let updated = try assertJSON(
            runCLI(
                args: ["item", "update", "note", noteID, "--append", "--stdin", "--json"],
                vault: vault,
                stdin: appendedText
            ),
            command: "item.update"
        )

        #expect(updated["readOnly"] as? Bool == false)
        #expect(updated["changed"] as? Bool == true)
        #expect(updated["action"] as? String == "append_note_content")
        let after = try #require(updated["after"] as? [String: Any])
        #expect(after["title"] as? String == "CID383 Blessed")

        let expectedBody = "Original CID383 body\n\nAppended CID383 body via blessed path"
        let fileBody = try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8)
        #expect(fileBody == expectedBody)

        let db = try openDB(in: vault)
        defer { db.close() }
        let dbNote = try noteRow(db, id: noteID)
        #expect(dbNote.title == "CID383 Blessed")
        #expect(dbNote.content == expectedBody)
        let chunks = try chunkBodies(db, ownerID: noteID)
        #expect(chunks.contains { $0.contains(appendedText) })

        let readModel = NotesStorage(database: db)
        readModel.loadNotesFromDatabase(db)
        let loaded = try #require(readModel.notes.first { $0.id.uuidString == noteID })
        #expect(loaded.title == "CID383 Blessed")
        #expect(loaded.content == expectedBody)

        let get = try assertJSON(
            runCLI(args: ["item", "get", "note", noteID, "--json"], vault: vault),
            command: "item.get"
        )
        let getChunks = try #require(get["chunks"] as? [[String: Any]])
        #expect(getChunks.contains { ($0["body"] as? String)?.contains(appendedText) == true })

        let search = try parseJSONArray(
            runCLI(args: ["item", "search", appendedText, "--json"], vault: vault).stdout
        )
        #expect(search.contains { result in
            ((result["item"] as? [String: Any])?["id"] as? String) == noteID
        })
    }

    @Test("item update note replace can rename and replace content together")
    func itemUpdateNoteReplaceCanRenameAndReplaceContentTogether() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let created = try createNote(title: "CID383 Rename Source", content: "Old body", vault: vault)
        let noteID = try #require(created["id"] as? String)

        let updated = try assertJSON(
            runCLI(
                args: [
                    "item", "update", "note", noteID,
                    "--title", "CID383 Renamed",
                    "--content", "Replacement CID383 body",
                    "--json",
                ],
                vault: vault
            ),
            command: "item.update"
        )

        #expect(updated["action"] as? String == "update_note")
        #expect(updated["changed"] as? Bool == true)
        let after = try #require(updated["after"] as? [String: Any])
        #expect(after["title"] as? String == "CID383 Renamed")
        let relativePath = try #require(after["relativePath"] as? String)
        #expect(relativePath.hasSuffix("CID383 Renamed.md"))
        #expect(try String(contentsOf: vault.appendingPathComponent(relativePath), encoding: .utf8) == "Replacement CID383 body")

        let db = try openDB(in: vault)
        defer { db.close() }
        let dbNote = try noteRow(db, id: noteID)
        #expect(dbNote.title == "CID383 Renamed")
        #expect(dbNote.content == "Replacement CID383 body")
        #expect(dbNote.relativePath == relativePath)
        #expect(try chunkBodies(db, ownerID: noteID).contains { $0.contains("Replacement CID383 body") })
    }

    @Test("external markdown edit plus rescan treats disk as source of truth")
    func externalMarkdownEditPlusRescanTreatsDiskAsSourceOfTruth() throws {
        let dbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid383-rescan-\(UUID().uuidString).db")
        let vault = try makeTempVault()
        let previousVault = StoragePaths.vaultOverride
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        defer {
            StoragePaths.vaultOverride = previousVault
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
            cleanupDB(at: dbURL)
        }

        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }

        let storage = NotesStorage(database: db)
        let noteID = UUID()
        storage.addFromSync(
            id: noteID,
            title: "CID383 External",
            content: "SQLite body before external edit",
            folderID: nil,
            isPinned: false,
            tags: [],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        let note = try #require(storage.notes.first { $0.id == noteID })
        let fileURL = storage.noteFileURL(for: note)

        try "Disk body wins after rescan".write(to: fileURL, atomically: true, encoding: .utf8)
        storage.rescan()

        let dbNote = try noteRow(db, id: noteID.uuidString)
        #expect(dbNote.content == "Disk body wins after rescan")
        #expect(try chunkBodies(db, ownerID: noteID.uuidString).contains { $0.contains("Disk body wins after rescan") })
        let readModelNote = try #require(storage.notes.first { $0.id == noteID })
        #expect(readModelNote.content == "Disk body wins after rescan")
    }

    private func createNote(title: String, content: String, vault: URL) throws -> [String: Any] {
        try assertJSON(
            runCLI(args: ["note", "create", title, "--content", content, "--json"], vault: vault),
            command: "note.create"
        )
    }

    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cid383-note-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func openDB(in vault: URL) throws -> CiderDatabase {
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return db
    }

    private func noteRow(_ db: CiderDatabase, id: String) throws -> (title: String, content: String, relativePath: String) {
        let stmt = try db.prepare("""
            SELECT i.title, n.content, i.relative_path
            FROM items i
            JOIN notes n ON n.item_id = i.id
            WHERE i.id = ? AND i.type = 'note';
            """)
        stmt.bind(id, at: 1)
        let found = try stmt.step()
        try #require(found)
        return (stmt.string(at: 0), stmt.string(at: 1), stmt.string(at: 2))
    }

    private func chunkBodies(_ db: CiderDatabase, ownerID: String) throws -> [String] {
        let stmt = try db.prepare("""
            SELECT body
            FROM content_chunks
            WHERE owner_type = 'note' AND owner_id = ?
            ORDER BY chunk_index ASC;
            """)
        stmt.bind(ownerID, at: 1)
        var bodies: [String] = []
        while try stmt.step() {
            bodies.append(stmt.string(at: 0))
        }
        return bodies
    }

    private func runCLI(args: [String], vault: URL, stdin: String? = nil) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = try cliURL()
        process.arguments = ["--vault", vault.path] + args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin {
            let input = Pipe()
            process.standardInput = input
            try process.run()
            input.fileHandleForWriting.write(Data(stdin.utf8))
            try input.fileHandleForWriting.close()
        } else {
            try process.run()
        }
        process.waitUntilExit()

        return (
            String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            process.terminationStatus
        )
    }

    private func cliURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ]
        if let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return url
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func assertJSON(
        _ result: (stdout: String, stderr: String, status: Int32),
        command: String
    ) throws -> [String: Any] {
        #expect(result.status == 0, "Expected \(command) to exit 0; stderr: \(result.stderr); stdout: \(result.stdout)")
        let payload = try parseJSONObject(result.stdout)
        #expect(payload["command"] as? String == command)
        #expect(payload["legacyRemoved"] == nil)
        return payload
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func parseJSONArray(_ output: String) throws -> [[String: Any]] {
        let json = output.drop { $0 != "[" }
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [[String: Any]])
    }

    private func cleanupDB(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }
}
