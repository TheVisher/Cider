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

    @Test("CLI media title base generates numbered photos and mixed explicit override wins")
    func mediaTitleBaseCLIContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-cli-title-base-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let files = try (1...3).map { index -> URL in
            let url = sources.appendingPathComponent("IMG_874\(index).jpeg")
            try Self.jpegData.write(to: url)
            return url
        }
        var args = [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "11:42",
            "--idempotency-key", "cli-title-base-1", "--media-title-base", "Reflection Lake", "--stdin", "--json",
        ]
        let overrides = ["", "Reflection Lake favorite", ""]
        for index in files.indices {
            args += [
                "--media", files[index].path,
                "--media-title", overrides[index],
                "--media-id", "cli-title-base-photo-\(index + 1)",
                "--media-kind", "photo",
            ]
        }
        let first = try runCLI(args: args, vault: vault, stdin: "Reflection Lake was glassy.")
        #expect(first.status == 0, "stderr: \(first.stderr) stdout: \(first.stdout)")
        let payload = try parseJSONObject(first.stdout)
        let receipt = try #require(payload["receipt"] as? [String: Any])
        let media = try #require(receipt["mediaSources"] as? [[String: Any]])
        #expect(media.compactMap { $0["displayTitle"] as? String } == [
            "Reflection Lake — Photo 1", "Reflection Lake favorite", "Reflection Lake — Photo 3",
        ])
        #expect(media.compactMap { $0["rawFilename"] as? String } == ["IMG_8741.jpeg", "IMG_8742.jpeg", "IMG_8743.jpeg"])

        let retry = try runCLI(args: args, vault: vault, stdin: "Reflection Lake was glassy.")
        #expect(retry.status == 0)
        let retryPayload = try parseJSONObject(retry.stdout)
        #expect((retryPayload["receipt"] as? [String: Any])?["wasReused"] as? Bool == true)

        let beforeDatabase = try databaseFingerprint(at: vault.appendingPathComponent(".cider/cider.db"))
        let beforeFiles = try vaultFileFingerprint(vault)
        var changedArgs = args
        let baseIndex = try #require(changedArgs.firstIndex(of: "Reflection Lake"))
        changedArgs[baseIndex] = "Narada Falls"
        let conflict = try runCLI(args: changedArgs, vault: vault, stdin: "Reflection Lake was glassy.")
        #expect(conflict.status != 0)
        #expect((try parseAnyJSONObject(conflict.stdout))["ok"] as? Bool == false)
        #expect(try databaseFingerprint(at: vault.appendingPathComponent(".cider/cider.db")) == beforeDatabase)
        #expect(try vaultFileFingerprint(vault) == beforeFiles)

        let invalidRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-cli-invalid-title-base-\(UUID().uuidString)", isDirectory: true)
        let invalidVault = invalidRoot.appendingPathComponent("vault", isDirectory: true)
        let invalidSources = invalidRoot.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: invalidVault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: invalidSources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: invalidRoot) }
        let invalidFile = invalidSources.appendingPathComponent("IMG_9999.jpeg")
        try Self.jpegData.write(to: invalidFile)
        let invalid = try runCLI(args: [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "12:00",
            "--idempotency-key", "invalid-base", "--media-title-base", "   ", "--stdin", "--json",
            "--media", invalidFile.path, "--media-id", "invalid-photo", "--media-kind", "photo",
        ], vault: invalidVault, stdin: "Invalid base should not mutate.")
        #expect(invalid.status != 0)
        let invalidDB = CiderDatabase()
        try invalidDB.open(at: invalidVault.appendingPathComponent(".cider/cider.db"))
        defer { invalidDB.close() }
        #expect(try count("items", database: invalidDB) == 0)
        #expect(try count("capture_events", database: invalidDB) == 0)
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

    @Test("vaultFile title update CLI is optimistic, durable, privacy-safe, and verifiable")
    func vaultFileTitleUpdateCLIContract() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-vaultfile-retitle-cli-\(UUID().uuidString)", isDirectory: true)
        let vault = root.appendingPathComponent("vault", isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sources.appendingPathComponent("IMG_8741.jpeg")
        try Self.jpegData.write(to: source)
        let capture = try runCLI(args: [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "13:00",
            "--idempotency-key", "cli-retitle-capture-1", "--media-title-base", "Reflection Lake", "--stdin", "--json",
            "--media", source.path, "--media-id", "cli-retitle-photo-1", "--media-kind", "photo",
        ], vault: vault, stdin: "Reflection Lake source-backed text.")
        #expect(capture.status == 0, "stderr: \(capture.stderr) stdout: \(capture.stdout)")
        let capturePayload = try parseJSONObject(capture.stdout)
        let journalID = try #require((capturePayload["item"] as? [String: Any])?["id"] as? String)
        let mediaSources = try #require((capturePayload["receipt"] as? [String: Any])?["mediaSources"] as? [[String: Any]])
        let mediaItem = try #require(mediaSources[0]["mediaItem"] as? [String: Any])
        let fileID = try #require(mediaItem["id"] as? String)

        let help = try runCLI(args: ["item", "update", "--help"], vault: vault)
        #expect(help.status == 0)
        #expect(help.stdout.contains("--expected-title"))
        #expect(help.stdout.contains("metadata-only"))

        let updateArgs = [
            "item", "update", "vaultFile", fileID,
            "--expected-title", "Reflection Lake — Photo 1",
            "--title", "Narada Falls",
            "--reason", "Repair filename-like Journal media title.",
            "--actor", "cid759-cli-test",
            "--source", "test.cid759.cli",
            "--json",
        ]
        let updated = try runCLI(args: updateArgs, vault: vault)
        #expect(updated.status == 0, "stderr: \(updated.stderr) stdout: \(updated.stdout)")
        let payload = parseJSONObjectCandidate(String(updated.stdout[updated.stdout.firstIndex(of: "{")!...]), expectedCommand: "item.update")!
        #expect(payload["changed"] as? Bool == true)
        #expect(payload["wasReused"] as? Bool == false)
        #expect((payload["after"] as? [String: Any])?["title"] as? String == "Narada Falls")
        let receipt = try #require(payload["receipt"] as? [String: Any])
        let receiptID = try #require(receipt["id"] as? String)
        let verificationCommand = try #require(payload["verificationCommand"] as? String)
        #expect(!updated.stdout.contains(source.path))
        #expect(!updated.stdout.localizedCaseInsensitiveContains("sha256"))
        #expect(!updated.stdout.contains("IMG_8741.jpeg"))

        let verificationArgs = verificationCommand.split(separator: " ").dropFirst().map(String.init)
        let verified = try runCLI(args: verificationArgs, vault: vault)
        #expect(verified.status == 0, "stderr: \(verified.stderr) stdout: \(verified.stdout)")
        #expect(verified.stdout.contains("Narada Falls"))

        let repeated = try runCLI(args: updateArgs, vault: vault)
        #expect(repeated.status == 0)
        let repeatedPayload = try #require(parseJSONObjectCandidate(
            String(repeated.stdout[repeated.stdout.firstIndex(of: "{")!...]), expectedCommand: "item.update"
        ))
        #expect(repeatedPayload["changed"] as? Bool == true)
        #expect(repeatedPayload["wasReused"] as? Bool == true)
        #expect((repeatedPayload["receipt"] as? [String: Any])?["id"] as? String == receiptID)

        let ledger = try runCLI(args: ["item", "action-ledger", "inspect", receiptID, "--json"], vault: vault)
        #expect(ledger.status == 0)
        #expect(ledger.stdout.contains("update_vault_file_display_title"))

        let rebuild = try runCLI(args: ["item", "rebuild-chunks", "vaultFile", fileID, "--json"], vault: vault)
        #expect(rebuild.status == 0, "stderr: \(rebuild.stderr) stdout: \(rebuild.stdout)")
        let search = try runCLI(args: ["item", "search", "Narada Falls", "--scope", "files", "--json"], vault: vault)
        #expect(search.status == 0)
        #expect(search.stdout.contains(fileID))

        let beforeFailure = try databaseFingerprint(at: vault.appendingPathComponent(".cider/cider.db"))
        let stale = try runCLI(args: [
            "item", "update", "vaultFile", fileID,
            "--expected-title", "Reflection Lake — Photo 1", "--title", "Narada Falls view",
            "--reason", "Stale attempt.", "--actor", "cid759-cli-test", "--source", "test.cid759.cli", "--json",
        ], vault: vault)
        #expect(stale.status != 0)
        #expect((try parseAnyJSONObject(stale.stdout))["errorCode"] as? String == "staleExpectedTitle")

        let invalid = try runCLI(args: [
            "item", "update", "vaultFile", fileID,
            "--expected-title", "Narada Falls", "--title", "   ",
            "--reason", "Invalid attempt.", "--actor", "cid759-cli-test", "--source", "test.cid759.cli", "--json",
        ], vault: vault)
        #expect(invalid.status != 0)
        #expect((try parseAnyJSONObject(invalid.stdout))["errorCode"] as? String == "invalidInput")

        let wrongType = try runCLI(args: [
            "item", "update", "vaultFile", journalID,
            "--expected-title", "Journal 07-15-2026", "--title", "Wrong type",
            "--reason", "Wrong type attempt.", "--actor", "cid759-cli-test", "--source", "test.cid759.cli", "--json",
        ], vault: vault)
        #expect(wrongType.status != 0)

        let missing = try runCLI(args: [
            "item", "update", "vaultFile", UUID().uuidString,
            "--expected-title", "Missing", "--title", "Still missing",
            "--reason", "Missing attempt.", "--actor", "cid759-cli-test", "--source", "test.cid759.cli", "--json",
        ], vault: vault)
        #expect(missing.status != 0)
        #expect(try databaseFingerprint(at: vault.appendingPathComponent(".cider/cider.db")) == beforeFailure)

        let second = sources.appendingPathComponent("IMG_8742.jpeg")
        try Self.jpegData.write(to: second)
        let duplicate = try runCLI(args: [
            "capture", "add", "--kind", "journal", "--date", "2026-07-15", "--time", "13:01",
            "--idempotency-key", "cli-retitle-capture-2", "--stdin", "--json",
            "--media", second.path, "--media-title", "Narada Falls", "--media-id", "cli-retitle-photo-2", "--media-kind", "photo",
        ], vault: vault, stdin: "A second canonical file may share a display title.")
        #expect(duplicate.status == 0)
        let ambiguous = try runCLI(args: [
            "item", "update", "vaultFile", "Narada Falls",
            "--expected-title", "Narada Falls", "--title", "Ambiguous target",
            "--reason", "Must resolve uniquely.", "--actor", "cid759-cli-test", "--source", "test.cid759.cli", "--json",
        ], vault: vault)
        #expect(ambiguous.status != 0)
        #expect((try parseAnyJSONObject(ambiguous.stdout))["errorCode"] as? String == "targetAmbiguous")
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
