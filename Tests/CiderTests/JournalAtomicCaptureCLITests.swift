import AppKit
import Foundation
import Testing
@testable import Cider

@Suite("Journal Atomic Capture CLI Tests", .serialized)
@MainActor
struct JournalAtomicCaptureCLITests {
    @Test("legacy disposable-vault flow requires four captures and drifts file titles to raw filenames")
    func legacyFlowReproducesFriction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-legacy-friction-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let journal = try runCLI(
            args: ["capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "11:42", "--stdin", "--json"],
            vault: vault,
            stdin: "Reflection Lake was glassy this morning."
        )
        #expect(journal.status == 0)
        for index in 1...3 {
            let url = sources.appendingPathComponent("IMG_874\(index).jpeg")
            try Self.jpegData.write(to: url)
            let result = try runCLI(
                args: ["capture", "add", "--kind", "file", "--path", url.path, "--json"],
                vault: vault
            )
            #expect(result.status == 0)
        }

        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        #expect(try count("capture_events", database: database) == 4)
        #expect(try count("vault_files", database: database) == 3)
        #expect(try countRelations("journal_source_for", database: database) == 0)
        let titles = try database.prepare("SELECT title FROM items WHERE type = 'vaultFile' ORDER BY title ASC;")
        var storedTitles: [String] = []
        while try titles.step() { storedTitles.append(titles.string(at: 0)) }
        #expect(storedTitles == ["IMG_8741", "IMG_8742", "IMG_8743"])
    }

    @Test("disposable-vault CLI captures Reflection Lake text plus three JPEGs and reuses receipt")
    func reflectionLakeSmoke() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-cli-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let titles = ["Reflection Lake overlook", "Reflection Lake trail", "Reflection Lake shoreline"]
        let files = try titles.indices.map { index -> URL in
            let url = sources.appendingPathComponent("IMG_874\(index + 1).jpeg")
            try Self.jpegData.write(to: url)
            return url
        }
        var args = [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "11:42",
            "--channel", "discord", "--message-id", "1527021398508310640",
            "--idempotency-key", "discord:message:1527021398508310640", "--stdin", "--json",
        ]
        for index in files.indices {
            args += [
                "--media", files[index].path,
                "--media-title", titles[index],
                "--media-id", "discord:1527021398508310640:photo:\(index + 1)",
                "--media-kind", "photo",
            ]
        }
        let text = "Reflection Lake was glassy this morning."
        let first = try runCLI(args: args, vault: vault, stdin: text)
        #expect(first.status == 0, "stderr: \(first.stderr) stdout: \(first.stdout)")
        #expect(first.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
        let firstJSON = try parseJSONObject(first.stdout)
        #expect(firstJSON["ok"] as? Bool == true)
        #expect(firstJSON["atomic"] as? Bool == true)
        let firstReceipt = try #require(firstJSON["receipt"] as? [String: Any])
        #expect((firstReceipt["mediaSources"] as? [[String: Any]])?.count == 3)
        #expect((firstReceipt["mediaSources"] as? [[String: Any]])?.compactMap { $0["displayTitle"] as? String } == titles)

        let retry = try runCLI(args: args, vault: vault, stdin: text)
        #expect(retry.status == 0, "stderr: \(retry.stderr) stdout: \(retry.stdout)")
        #expect(retry.stdout.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{"))
        let retryJSON = try parseJSONObject(retry.stdout)
        let retryReceipt = try #require(retryJSON["receipt"] as? [String: Any], "stdout: \(retry.stdout) stderr: \(retry.stderr)")
        #expect(retryReceipt["id"] as? String == firstReceipt["id"] as? String)
        #expect(retryReceipt["wasReused"] as? Bool == true)
        #expect(retryJSON["changed"] as? Bool == false)

        let item = try #require(firstJSON["item"] as? [String: Any])
        let noteID = try #require(item["id"] as? String)

        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        #expect(try count("capture_events", database: database) == 1)
        #expect(try count("capture_attachments", database: database) == 3)
        #expect(try count("vault_files", database: database) == 3)
        #expect(try count("notes", database: database) == 1)
        let readback = try database.prepare("SELECT content FROM notes WHERE item_id = ?;")
        readback.bind(noteID, at: 1)
        #expect(try readback.step())
        #expect(readback.string(at: 0).contains(text))
    }

    @Test("changed JPEG bytes conflict across disposable CLI process reopen without mutation")
    func changedMediaContentConflictsAcrossProcessReopen() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-cli-content-conflict-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let media = sources.appendingPathComponent("IMG_8741.jpeg")
        try Self.jpegData.write(to: media)
        let args = [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "11:42",
            "--channel", "discord", "--message-id", "1527021398508310640",
            "--idempotency-key", "discord:message:1527021398508310640", "--stdin", "--json",
            "--media", media.path,
            "--media-title", "Reflection Lake overlook",
            "--media-id", "discord:1527021398508310640:photo:1",
            "--media-kind", "photo",
        ]
        let text = "Reflection Lake was glassy this morning."
        let first = try runCLI(args: args, vault: vault, stdin: text)
        #expect(first.status == 0, "stderr: \(first.stderr) stdout: \(first.stdout)")
        let firstJSON = try parseJSONObject(first.stdout)
        let firstReceipt = try #require(firstJSON["receipt"] as? [String: Any])
        let receiptID = try #require(firstReceipt["id"] as? String)
        let unchangedRetry = try runCLI(args: args, vault: vault, stdin: text)
        #expect(unchangedRetry.status == 0, "stderr: \(unchangedRetry.stderr) stdout: \(unchangedRetry.stdout)")
        let unchangedJSON = try parseJSONObject(unchangedRetry.stdout)
        let unchangedReceipt = try #require(unchangedJSON["receipt"] as? [String: Any])
        #expect(unchangedReceipt["id"] as? String == receiptID)
        #expect(unchangedReceipt["wasReused"] as? Bool == true)
        let beforeDatabase = try databaseFingerprint(at: vault.appendingPathComponent(".cider/cider.db"))
        let beforeFiles = try vaultFileFingerprint(vault)
        let durableDigestBefore = try journalRequestDigest(
            at: vault.appendingPathComponent(".cider/cider.db"),
            receiptID: receiptID
        )

        try Self.changedJPEGData.write(to: media, options: .atomic)
        let retry = try runCLI(args: args, vault: vault, stdin: text)
        #expect(retry.status != 0, "stderr: \(retry.stderr) stdout: \(retry.stdout)")
        let retryJSON = try parseAnyJSONObject(retry.stdout)
        #expect(retryJSON["ok"] as? Bool == false)
        let error = try #require(retryJSON["error"] as? String)
        #expect(error.contains("different logical capture"))
        #expect(!error.contains(media.path))
        #expect(!error.localizedCaseInsensitiveContains("sha256"))
        let afterDatabase = try databaseFingerprint(at: vault.appendingPathComponent(".cider/cider.db"))
        #expect(afterDatabase == beforeDatabase)
        #expect(try vaultFileFingerprint(vault) == beforeFiles)
        #expect(try journalRequestDigest(
            at: vault.appendingPathComponent(".cider/cider.db"),
            receiptID: receiptID
        ) == durableDigestBefore)
    }

    @Test("stored voice CLI uses capture add and fails closed for unsupported or misconfigured explicit providers")
    func storedVoiceProviderFailuresDoNotMutateDisposableVault() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-cli-voice-failure-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = sources.appendingPathComponent("generated-fixture.m4a")
        try Data("generated disposable audio bytes".utf8).write(to: audio, options: .atomic)
        let base = [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "18:24",
            "--media", audio.path, "--media-id", "cli:voice:fixture:1", "--media-kind", "audio",
            "--idempotency-key", "cli:voice:retry:1", "--json",
        ]

        let unsupported = try runCLI(
            args: base + ["--transcription-provider", "unsupported-provider"],
            vault: vault
        )
        #expect(unsupported.status != 0)
        let unsupportedJSON = try parseAnyJSONObject(unsupported.stdout)
        #expect(unsupportedJSON["ok"] as? Bool == false)
        #expect(!(unsupportedJSON["error"] as? String ?? "").contains(audio.path))

        let misconfigured = try runCLI(
            args: base + ["--transcription-provider", "local-faster-whisper"],
            vault: vault
        )
        #expect(misconfigured.status != 0)
        let misconfiguredJSON = try parseAnyJSONObject(misconfigured.stdout)
        #expect(misconfiguredJSON["ok"] as? Bool == false)
        #expect(!(misconfiguredJSON["error"] as? String ?? "").contains(audio.path))

        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        #expect(try count("items", database: database) == 0)
        #expect(try count("capture_events", database: database) == 0)
        #expect(try count("capture_attachments", database: database) == 0)
        #expect(FileManager.default.fileExists(atPath: audio.path))
    }

    private func runCLI(
        args: [String],
        vault: URL,
        stdin: String? = nil
    ) throws -> (stdout: String, stderr: String, status: Int32) {
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
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        for start in output.indices where output[start] == "{" {
            if let object = parseJSONObjectCandidate(String(output[start...])) {
                return object
            }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private func parseAnyJSONObject(_ output: String) throws -> [String: Any] {
        for start in output.indices where output[start] == "{" {
            if let object = parseJSONObjectCandidate(String(output[start...]), expectedCommand: nil) {
                return object
            }
        }
        throw CocoaError(.fileReadCorruptFile)
    }

    private func parseJSONObjectCandidate(
        _ candidate: String,
        expectedCommand: String? = "capture.add"
    ) -> [String: Any]? {
        var depth = 0
        var isInString = false
        var isEscaped = false
        var endIndex: String.Index?
        for index in candidate.indices {
            let character = candidate[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if isInString, character == "\\" {
                isEscaped = true
                continue
            }
            if character == "\"" {
                isInString.toggle()
                continue
            }
            guard !isInString else { continue }
            if character == "{" { depth += 1 }
            if character == "}" {
                depth -= 1
                if depth == 0 {
                    endIndex = candidate.index(after: index)
                    break
                }
            }
        }
        guard let end = endIndex else { return nil }
        let json = String(candidate[..<end])
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return nil }
        if let expectedCommand, object["command"] as? String != expectedCommand { return nil }
        return object
    }

    @MainActor
    private func databaseFingerprint(at databaseURL: URL) throws -> String {
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        defer { database.close() }
        let tableNames = [
            "capture_attachments", "capture_events", "content_chunks", "content_chunks_fts",
            "item_sections", "items", "notes", "owner_relations", "vault_files",
        ]
        var rows: [String] = []
        for table in tableNames {
            let quotedTable = quotedIdentifier(table)
            let columnsStatement = try database.prepare("PRAGMA table_info(\(quotedTable));")
            var columns: [String] = []
            while try columnsStatement.step() { columns.append(columnsStatement.string(at: 1)) }
            guard !columns.isEmpty else { continue }
            let expression = columns.map { "quote(\(quotedIdentifier($0)))" }.joined(separator: " || char(31) || ")
            let rowStatement = try database.prepare("SELECT \(expression) FROM \(quotedTable);")
            var tableRows: [String] = []
            while try rowStatement.step() { tableRows.append(rowStatement.string(at: 0)) }
            rows.append("\(table):\(tableRows.sorted().joined(separator: "\u{1e}"))")
        }
        return LocalFileIntakeValidator.sha256(Data(rows.joined(separator: "\u{1d}").utf8))
    }

    @MainActor
    private func journalRequestDigest(at databaseURL: URL, receiptID: String) throws -> String {
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        defer { database.close() }
        let statement = try database.prepare("SELECT metadata FROM capture_events WHERE id = ? LIMIT 1;")
        statement.bind(receiptID, at: 1)
        guard try statement.step() else { throw CocoaError(.fileReadUnknown) }
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: statement.optionalString(at: 0)) ?? [:]
        return try #require(metadata["journal_request_digest"])
    }

    private func vaultFileFingerprint(_ vault: URL) throws -> String {
        let files = try FileManager.default.subpathsOfDirectory(atPath: vault.path).sorted().compactMap { path -> String? in
            // CLI startup owns operational state under .cider (for example usage
            // audit timestamps). The capture transaction owns canonical user
            // files outside it, which must remain byte-for-byte stable here.
            if path == ".cider" || path.hasPrefix(".cider/") { return nil }
            let url = vault.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            if isDirectory.boolValue { return "\(path)/" }
            return "\(path):\(LocalFileIntakeValidator.sha256(try Data(contentsOf: url)))"
        }
        return LocalFileIntakeValidator.sha256(Data(files.joined(separator: "\u{1e}").utf8))
    }

    private func quotedIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    @MainActor
    private func count(_ table: String, database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
        try statement.step()
        return statement.int(at: 0)
    }

    @MainActor
    private func countRelations(_ relationType: String, database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM owner_relations WHERE relation_type = ?;")
        statement.bind(relationType, at: 1)
        try statement.step()
        return statement.int(at: 0)
    }

    private static let jpegData: Data = {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemGreen.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
            .representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    }()

    private static let changedJPEGData: Data = {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
        image.unlockFocus()
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
            .representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    }()
}
