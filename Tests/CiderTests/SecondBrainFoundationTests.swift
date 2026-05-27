import Foundation
import Testing
@testable import Cider

@Suite("Second Brain Foundation Tests")
@MainActor
struct SecondBrainFoundationTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-second-brain-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private var packageRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var ciderCLIURL: URL {
        let candidates = [
            packageRootURL.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            packageRootURL.appendingPathComponent(".build/debug/cider-cli"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) } ?? candidates[0]
    }

    private func runCLI(_ args: [String], vaultURL: URL, stdin: String? = nil) throws -> String {
        let result = try runCLIResult(args, vaultURL: vaultURL, stdin: stdin)
        #expect(result.status == 0, "CLI failed: \(args.joined(separator: " "))\nstdout:\n\(result.stdout)\nstderr:\n\(result.stderr)")
        return result.stdout
    }

    private func runCLIResult(_ args: [String], vaultURL: URL, stdin: String? = nil) throws -> (stdout: String, stderr: String, status: Int32) {
        let process = Process()
        process.executableURL = ciderCLIURL
        process.currentDirectoryURL = packageRootURL
        process.arguments = ["--vault", vaultURL.path] + args

        let output = Pipe()
        let error = Pipe()
        let input = stdin.map { _ in Pipe() }
        process.standardOutput = output
        process.standardError = error
        if let input {
            process.standardInput = input
        }

        try process.run()
        if let stdin, let input {
            input.fileHandleForWriting.write(Data(stdin.utf8))
            input.fileHandleForWriting.closeFile()
        }
        process.waitUntilExit()

        let stdout = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let stderr = String(
            data: error.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return (stdout, stderr, process.terminationStatus)
    }

    private func jsonObject(from output: String) throws -> [String: Any] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [String: Any]) ?? [:]
    }

    private func jsonObjectArray(from output: String) throws -> [[String: Any]] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return (object as? [[String: Any]]) ?? []
    }

    private func requireCaptureAddWrapperContract(
        _ payload: [String: Any],
        command: String
    ) throws -> [String: Any] {
        #expect(payload["command"] as? String == command)
        #expect(payload["backendCommand"] as? String == "capture.add")
        let capture = try #require(payload["capture"] as? [String: Any])
        #expect(capture["command"] as? String == "capture.add")
        return capture
    }

    private func requireCaptureAddContract(_ payload: [String: Any]) throws -> [String: Any] {
        #expect(payload["command"] as? String == "capture.add")
        return payload
    }

    private func requireAgentFacingCaptureState(
        _ capture: [String: Any],
        expectedOriginalText: String? = nil
    ) throws {
        let item = try #require(capture["item"] as? [String: Any])
        #expect(item["id"] as? String != nil)
        #expect(item["type"] as? String != nil)
        #expect(item["relativePath"] as? String != nil)

        let duplicate = try #require(capture["duplicate"] as? [String: Any])
        #expect(duplicate["status"] as? String != nil)

        let routing = try #require(capture["routing"] as? [String: Any])
        #expect(routing["reviewNeeded"] as? Bool != nil)
        #expect(routing["reviewState"] as? String != nil)

        let provenance = try #require(capture["provenance"] as? [String: Any])
        #expect(provenance["status"] as? String != nil)

        let indexing = try #require(capture["indexing"] as? [String: Any])
        #expect(indexing["status"] as? String != nil)

        let safeNextCommands = try #require(capture["safeNextCommands"] as? [String])
        #expect(!safeNextCommands.isEmpty)
        #expect(capture["nextSafeAction"] as? String != nil)

        if let expectedOriginalText {
            let sourceContext = try #require(capture["sourceContext"] as? [String: Any])
            #expect(sourceContext["originalText"] as? String == expectedOriginalText)
        }
    }

    @Test("bookmark add records unified capture routing review metadata")
    func bookmarkAddRecordsUnifiedCaptureRoutingReviewMetadata() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-bookmark-add-cutover-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let output = try runCLI([
            "bookmark", "add", "https://example.com/cutover",
            "--no-wait",
            "--json",
        ], vaultURL: vault)
        let bookmark = try jsonObject(from: output)
        let idString = try #require(bookmark["id"] as? String)
        let itemID = try #require(UUID(uuidString: idString))

        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }

        let explanation = try CiderRoutingDecisionService(database: db).explain(itemID: itemID)
        #expect(explanation.latestDecision?.reviewState == "needs_review")
        #expect(explanation.latestDecision?.source == "capture.add")
        #expect(explanation.latestDecision?.actor == "agent")
        #expect(explanation.latestDecision?.target.relativePath == "Inbox/Bookmarks")
    }

    @Test("process CLI explains and approves routing decisions as JSON")
    func processCLIExplainsAndApprovesRoutingDecisionsAsJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-routing-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let captureOutput = try runCLI([
            "bookmark", "add", "https://example.com/routing-json",
            "--no-wait",
            "--json",
        ], vaultURL: vault)
        let bookmark = try jsonObject(from: captureOutput)
        let bookmarkID = try #require(bookmark["id"] as? String)

        let explainOutput = try runCLI([
            "routing", "explain", bookmarkID,
            "--json",
        ], vaultURL: vault)
        let explanation = try jsonObject(from: explainOutput)
        #expect(explanation["command"] as? String == "routing.explain")
        #expect(explanation["reviewNeeded"] as? Bool == true)
        #expect(explanation["nextSafeAction"] as? String == "approve_or_correct_route")
        let routing = try #require(explanation["routing"] as? [String: Any])
        #expect(routing["reviewState"] as? String == "needs_review")
        #expect(routing["actor"] as? String == "agent")
        #expect(routing["source"] as? String == "capture.add")

        let approvalOutput = try runCLI([
            "routing", "approve", bookmarkID,
            "--actor", "agent",
            "--json",
        ], vaultURL: vault)
        let approval = try jsonObject(from: approvalOutput)
        #expect(approval["command"] as? String == "routing.explain")
        #expect(approval["reviewNeeded"] as? Bool == false)
        #expect(approval["nextSafeAction"] as? String == "inspect_item")
        let approvedRouting = try #require(approval["routing"] as? [String: Any])
        #expect(approvedRouting["reviewState"] as? String == "accepted")
        #expect(approvedRouting["actor"] as? String == "agent")
        #expect(approvedRouting["source"] as? String == "routing.approve")
        #expect(approvedRouting["supersedesDecisionID"] as? String != nil)
        let history = try #require(approval["history"] as? [[String: Any]])
        #expect(history.count == 2)
    }

    @Test("bookmark add JSON reports capture backend shim metadata")
    func bookmarkAddJSONReportsCaptureBackendShimMetadata() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-bookmark-add-shim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let output = try runCLI([
            "bookmark", "add", "https://example.com/shim",
            "--no-wait",
            "--json",
        ], vaultURL: vault)
        let bookmark = try jsonObject(from: output)

        let capture = try requireCaptureAddWrapperContract(bookmark, command: "bookmark.add")
        let bookmarkID = try #require(bookmark["id"] as? String)

        let source = try #require(capture["source"] as? [String: Any])
        #expect(source["kind"] as? String == "url")
        let routing = try #require(capture["routing"] as? [String: Any])
        #expect(routing["reviewState"] as? String == "needs_review")
        #expect(routing["reviewNeeded"] as? Bool == true)

        let itemGet = try jsonObject(from: runCLI([
            "item", "get", "bookmark", bookmarkID,
            "--json",
        ], vaultURL: vault))
        #expect(itemGet["deprecated"] == nil)
        #expect(itemGet["legacyOwnerInspection"] == nil)
        let item = try #require(itemGet["item"] as? [String: Any])
        #expect(item["type"] as? String == "bookmark")
        #expect(item["id"] as? String == bookmarkID)
    }

    @Test("process CLI note todo and file creates emit capture provenance")
    func processCLINoteTodoAndFileCreateEmitCaptureProvenance() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-note-todo-file-capture-shim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let noteOutput = try runCLI([
            "note", "create", "Kitchen idea",
            "--content", "Ferment lemons with salt.",
            "--json",
        ], vaultURL: vault)
        let notePayload = try jsonObject(from: noteOutput)
        let noteCapture = try requireCaptureAddWrapperContract(notePayload, command: "note.create")
        let noteItem = try #require(noteCapture["item"] as? [String: Any])
        let noteRouting = try #require(noteCapture["routing"] as? [String: Any])
        #expect(noteItem["type"] as? String == "note")
        #expect(noteItem["title"] as? String == "Kitchen idea")
        #expect(noteRouting["reviewState"] as? String == "needs_review")

        let todoOutput = try runCLI([
            "todo", "create", "Call dentist",
            "--due", "2026-05-18",
            "--priority", "high",
            "--json",
        ], vaultURL: vault)
        let todoPayload = try jsonObject(from: todoOutput)
        let todoCapture = try requireCaptureAddWrapperContract(todoPayload, command: "todo.create")
        let todoItem = try #require(todoCapture["item"] as? [String: Any])
        let todoRouting = try #require(todoCapture["routing"] as? [String: Any])
        #expect(todoItem["type"] as? String == "todo")
        #expect(todoItem["title"] as? String == "Call dentist")
        #expect(todoRouting["reviewState"] as? String == "needs_review")

        let sourceURL = vault.appendingPathComponent("receipt.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
        let fileOutput = try runCLI([
            "file", "import", sourceURL.path,
            "--title", "Receipt photo",
            "--json",
        ], vaultURL: vault)
        let filePayload = try jsonObject(from: fileOutput)
        let fileCapture = try requireCaptureAddWrapperContract(filePayload, command: "file.import")
        let fileItem = try #require(fileCapture["item"] as? [String: Any])
        let fileRouting = try #require(fileCapture["routing"] as? [String: Any])
        #expect(fileItem["type"] as? String == "vaultFile")
        #expect(fileItem["title"] as? String == "Receipt photo")
        #expect(fileRouting["reviewState"] as? String == "needs_review")

        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }

        let routing = CiderRoutingDecisionService(database: db)
        let noteIDString = try #require(notePayload["id"] as? String)
        let todoIDString = try #require(todoPayload["id"] as? String)
        let fileIDString = try #require(filePayload["id"] as? String)
        let noteID = try #require(UUID(uuidString: noteIDString))
        let todoID = try #require(UUID(uuidString: todoIDString))
        let fileID = try #require(UUID(uuidString: fileIDString))
        #expect(try routing.explain(itemID: noteID).latestDecision?.source == "capture.add")
        #expect(try routing.explain(itemID: todoID).latestDecision?.source == "capture.add")
        #expect(try routing.explain(itemID: fileID).latestDecision?.source == "capture.add")
    }

    @Test("capture add stdin note preserves shell sensitive multiline text")
    func captureAddStdinNotePreservesShellSensitiveMultilineText() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-stdin-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let raw = """
        Budget is $500; say "yes", don't trim it.
        Run `echo hello`; visit https://example.com/path?a=1&b=two.
        File path: /tmp/Cider Path/with spaces.txt
        Emoji: 🍎
        """

        let payload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "note",
            "--stdin",
            "--json",
        ], vaultURL: vault, stdin: raw))
        let capture = try requireCaptureAddContract(payload)
        let source = try #require(capture["source"] as? [String: Any])
        let item = try #require(capture["item"] as? [String: Any])

        #expect(source["kind"] as? String == "text")
        #expect(source["text"] as? String == raw)
        #expect(item["type"] as? String == "note")
        try requireAgentFacingCaptureState(capture, expectedOriginalText: raw)
    }

    @Test("capture add text file note preserves shell sensitive multiline text")
    func captureAddTextFileNotePreservesShellSensitiveMultilineText() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-text-file-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let raw = """
        Budget is $500; say "yes", don't trim it.
        Run `echo hello`; visit https://example.com/path?a=1&b=two.
        File path: /tmp/Cider Path/with spaces.txt
        Emoji: 🍎
        """
        let inputURL = vault.appendingPathComponent("raw capture.txt")
        try raw.write(to: inputURL, atomically: true, encoding: .utf8)

        let payload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "note",
            "--text-file", inputURL.path,
            "--json",
        ], vaultURL: vault))
        let capture = try requireCaptureAddContract(payload)
        let source = try #require(capture["source"] as? [String: Any])
        let item = try #require(capture["item"] as? [String: Any])

        #expect(source["text"] as? String == raw)
        #expect(item["type"] as? String == "note")
        try requireAgentFacingCaptureState(capture, expectedOriginalText: raw)
    }

    @Test("capture add explicit kind avoids inference for raw text")
    func captureAddExplicitKindAvoidsInferenceForRawText() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-explicit-kind-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let todoText = "todo: Preserve exact todo text with $500 and `ticks`."
        let todoPayload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "todo",
            "--stdin",
            "--json",
        ], vaultURL: vault, stdin: todoText))
        let todoItem = try #require(todoPayload["item"] as? [String: Any])
        let todoSource = try #require(todoPayload["source"] as? [String: Any])
        #expect(todoPayload["command"] as? String == "capture.add")
        #expect(todoItem["type"] as? String == "todo")
        #expect(todoSource["text"] as? String == todoText)
        try requireAgentFacingCaptureState(todoPayload, expectedOriginalText: todoText)

        let urlLookingText = "https://example.com/looks-like-bookmark?cost=$500&quoted=yes"
        let noteURLPayload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "note",
            "--stdin",
            "--json",
        ], vaultURL: vault, stdin: urlLookingText))
        let noteURLItem = try #require(noteURLPayload["item"] as? [String: Any])
        let noteURLSource = try #require(noteURLPayload["source"] as? [String: Any])
        #expect(noteURLItem["type"] as? String == "note")
        #expect(noteURLSource["text"] as? String == urlLookingText)
        try requireAgentFacingCaptureState(noteURLPayload, expectedOriginalText: urlLookingText)

        let sourceFile = vault.appendingPathComponent("looks like file.txt")
        try "real file contents".write(to: sourceFile, atomically: true, encoding: .utf8)
        let noteFilePayload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "note",
            "--stdin",
            "--json",
        ], vaultURL: vault, stdin: sourceFile.path))
        let noteFileItem = try #require(noteFilePayload["item"] as? [String: Any])
        let noteFileSource = try #require(noteFilePayload["source"] as? [String: Any])
        #expect(noteFileItem["type"] as? String == "note")
        #expect(noteFileSource["text"] as? String == sourceFile.path)
        try requireAgentFacingCaptureState(noteFilePayload, expectedOriginalText: sourceFile.path)
    }

    @Test("capture add positional note joins shell split text exactly")
    func captureAddPositionalNoteJoinsShellSplitTextExactly() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-positional-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let parts = [
            "Dinner",
            "costs",
            "$500;",
            "say",
            "\"yes\",",
            "don't",
            "run",
            "`rm -rf /`.",
            "URL:",
            "https://example.com/path?a=1&b=two",
        ]
        let raw = parts.joined(separator: " ")
        let payload = try jsonObject(from: runCLI(
            ["capture", "add", "--kind", "note"] + parts + ["--json"],
            vaultURL: vault
        ))
        let capture = try requireCaptureAddContract(payload)
        let source = try #require(capture["source"] as? [String: Any])
        let item = try #require(capture["item"] as? [String: Any])

        #expect(source["kind"] as? String == "text")
        #expect(source["text"] as? String == raw)
        #expect(item["type"] as? String == "note")
        try requireAgentFacingCaptureState(capture, expectedOriginalText: raw)
    }

    @Test("capture add explicit bookmark url and file path use canonical JSON")
    func captureAddExplicitBookmarkURLAndFilePathUseCanonicalJSON() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-url-file-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let bookmarkPayload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "bookmark",
            "--url", "https://example.com/capture?x=1&price=$500",
            "--no-wait",
            "--json",
        ], vaultURL: vault))
        let bookmarkSource = try #require(bookmarkPayload["source"] as? [String: Any])
        let bookmarkItem = try #require(bookmarkPayload["item"] as? [String: Any])
        #expect(bookmarkPayload["command"] as? String == "capture.add")
        #expect(bookmarkSource["kind"] as? String == "url")
        #expect(bookmarkSource["url"] as? String == "https://example.com/capture?x=1&price=$500")
        #expect(bookmarkItem["type"] as? String == "bookmark")
        try requireAgentFacingCaptureState(bookmarkPayload, expectedOriginalText: "https://example.com/capture?x=1&price=$500")

        let sourceURL = vault.appendingPathComponent("path with spaces.txt")
        try "file body".write(to: sourceURL, atomically: true, encoding: .utf8)
        let filePayload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "file",
            "--path", sourceURL.path,
            "--json",
        ], vaultURL: vault))
        let fileSource = try #require(filePayload["source"] as? [String: Any])
        let fileItem = try #require(filePayload["item"] as? [String: Any])
        #expect(filePayload["command"] as? String == "capture.add")
        #expect(fileSource["kind"] as? String == "file")
        #expect(fileSource["file"] as? String == sourceURL.path)
        #expect(fileItem["type"] as? String == "vaultFile")
        #expect(fileItem["relativePath"] as? String == "Inbox/Files/path with spaces.txt")
        try requireAgentFacingCaptureState(filePayload, expectedOriginalText: sourceURL.path)
    }

    @Test("capture add event supports structured flags and stdin source text")
    func captureAddEventSupportsStructuredFlagsAndStdinSourceText() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-event-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let raw = """
        Meet Avery about Cider v1.
        Bring $500 budget notes and `demo.sh`.
        """

        let payload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "event",
            "--title", "Cider v1 review",
            "--date", "2026-05-22",
            "--time", "10:30 AM",
            "--location", "Studio",
            "--stdin",
            "--json",
        ], vaultURL: vault, stdin: raw))
        let capture = try requireCaptureAddContract(payload)
        let source = try #require(capture["source"] as? [String: Any])
        let item = try #require(capture["item"] as? [String: Any])
        let routing = try #require(capture["routing"] as? [String: Any])

        #expect(source["text"] as? String == raw)
        #expect(source["itemType"] as? String == "event")
        #expect(item["type"] as? String == "event")
        #expect(item["title"] as? String == "Cider v1 review")
        #expect(routing["reviewState"] as? String == "needs_review")
        #expect(capture["nextSafeAction"] as? String == "review_route")
        #expect(capture["safeNextCommands"] as? [String] != nil)
        try requireAgentFacingCaptureState(capture, expectedOriginalText: raw)
    }

    @Test("capture add contact supports structured flags and text file source text")
    func captureAddContactSupportsStructuredFlagsAndTextFileSourceText() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-contact-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let raw = """
        Avery's notes include "design systems"; owes follow-up on $500 quote.
        URL: https://example.com/contact?ref=cider
        """
        let textFile = vault.appendingPathComponent("contact source.txt")
        try raw.write(to: textFile, atomically: true, encoding: .utf8)

        let payload = try jsonObject(from: runCLI([
            "capture", "add",
            "--kind", "contact",
            "--name", "Avery Stone",
            "--relationship", "Designer",
            "--email", "avery@example.com",
            "--phone", "555-0100",
            "--text-file", textFile.path,
            "--json",
        ], vaultURL: vault))
        let capture = try requireCaptureAddContract(payload)
        let source = try #require(capture["source"] as? [String: Any])
        let item = try #require(capture["item"] as? [String: Any])
        let routing = try #require(capture["routing"] as? [String: Any])

        #expect(source["text"] as? String == raw)
        #expect(source["itemType"] as? String == "contact")
        #expect(item["type"] as? String == "contact")
        #expect(item["title"] as? String == "Avery Stone")
        #expect(routing["reviewState"] as? String == "needs_review")
        #expect(capture["nextSafeAction"] as? String == "review_route")
        #expect(capture["safeNextCommands"] as? [String] != nil)
        try requireAgentFacingCaptureState(capture, expectedOriginalText: raw)
    }

    @Test("capture archive artifacts summarizes generated audit directory and trashes only after capture")
    func captureArchiveArtifactsSummarizesGeneratedAuditDirectoryAndTrashesOnlyAfterCapture() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-artifact-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let artifactDir = vault.appendingPathComponent("audit-reports", isDirectory: true)
        try FileManager.default.createDirectory(
            at: artifactDir.appendingPathComponent("logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "Summary: capture path is healthy.".write(
            to: artifactDir.appendingPathComponent("summary.md"),
            atomically: true,
            encoding: .utf8
        )
        try String(repeating: "large-log-line\n", count: 8).write(
            to: artifactDir.appendingPathComponent("logs/full.log"),
            atomically: true,
            encoding: .utf8
        )

        let payload = try jsonObject(from: runCLI([
            "capture", "archive-artifacts",
            artifactDir.path,
            "--title", "Backend audit artifact archive",
            "--card", "2ad7b4",
            "--commit", "abc1234",
            "--large-threshold-bytes", "40",
            "--cleanup", "trash",
            "--json",
        ], vaultURL: vault))

        #expect(payload["command"] as? String == "capture.archive-artifacts")
        #expect(payload["summaryOnly"] as? Bool == true)
        #expect(payload["sourcePath"] as? String == artifactDir.path)
        #expect(payload["fileCount"] as? Int == 2)
        #expect(payload["omittedArtifactCount"] as? Int == 1)
        #expect((payload["omittedBytes"] as? Int ?? 0) > 40)
        #expect((payload["relatedCards"] as? [String]) == ["2ad7b4"])
        #expect((payload["commits"] as? [String]) == ["abc1234"])

        let representativeFiles = try #require(payload["representativeFiles"] as? [[String: Any]])
        #expect(representativeFiles.contains { $0["path"] as? String == "logs/full.log" })
        #expect(representativeFiles.contains { $0["omitted"] as? Bool == true })

        let capture = try #require(payload["capture"] as? [String: Any])
        let item = try #require(capture["item"] as? [String: Any])
        #expect(capture["command"] as? String == "capture.add")
        #expect(item["type"] as? String == "note")

        let cleanup = try #require(payload["cleanup"] as? [String: Any])
        #expect(cleanup["mode"] as? String == "trash")
        #expect(cleanup["performed"] as? Bool == true)
        let trashPath = try #require(cleanup["trashPath"] as? String)
        #expect(!FileManager.default.fileExists(atPath: artifactDir.path))
        #expect(FileManager.default.fileExists(atPath: trashPath))
    }

    @Test("process CLI event and contact legacy creates are removed")
    func processCLIEventAndContactLegacyCreatesAreRemoved() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-event-contact-provenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let eventResult = try runCLIResult([
            "event", "create", "Passport appointment",
            "--date", "2026-05-20",
            "--time", "10:30 AM",
            "--location", "City Hall",
            "--json",
        ], vaultURL: vault)
        let eventPayload = try jsonObject(from: eventResult.stdout)
        #expect(eventResult.status != 0)
        #expect(eventPayload["ok"] as? Bool == false)
        #expect(eventPayload["legacyRemoved"] as? Bool == true)
        #expect(eventPayload["command"] as? String == "event create")
        #expect(eventPayload["replacement"] as? String == "cider-cli capture add --kind event --title \"<title>\" --date yyyy-MM-dd --stdin --json")

        let contactResult = try runCLIResult([
            "contact", "create", "Avery Example",
            "--email", "avery@example.com",
            "--birthday", "2016-06-15",
            "--json",
        ], vaultURL: vault)
        let contactPayload = try jsonObject(from: contactResult.stdout)
        #expect(contactResult.status != 0)
        #expect(contactPayload["ok"] as? Bool == false)
        #expect(contactPayload["legacyRemoved"] as? Bool == true)
        #expect(contactPayload["command"] as? String == "contact create")
        #expect(contactPayload["replacement"] as? String == "cider-cli capture add --kind contact --name \"<name>\" --stdin --json")
    }

    @Test("legacy bookmark move is removed with item move replacement")
    func legacyBookmarkMoveIsRemovedWithItemMoveReplacement() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-bookmark-move-provenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let output = try runCLI([
            "bookmark", "add", "https://example.com/manual-move",
            "--no-wait",
            "--json",
        ], vaultURL: vault)
        let bookmark = try jsonObject(from: output)
        let idString = try #require(bookmark["id"] as? String)
        let itemID = try #require(UUID(uuidString: idString))

        let moveResult = try runCLIResult([
            "bookmark", "move", String(idString.prefix(8)),
            "--folder", "Research",
            "--json",
        ], vaultURL: vault)
        let move = try jsonObject(from: moveResult.stdout)
        #expect(moveResult.status != 0)
        #expect(move["ok"] as? Bool == false)
        #expect(move["legacyRemoved"] as? Bool == true)
        #expect(move["command"] as? String == "bookmark move")
        #expect(move["replacement"] as? String == "cider-cli item move bookmark <id> --folder <name|path> --json")
        _ = itemID
    }

    @Test("review correct labels folder assignment as routing correction")
    func reviewCorrectLabelsFolderAssignmentAsRoutingCorrection() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-correct-provenance-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let output = try runCLI([
            "bookmark", "add", "https://example.com/review-correct",
            "--no-wait",
            "--json",
        ], vaultURL: vault)
        let bookmark = try jsonObject(from: output)
        let idString = try #require(bookmark["id"] as? String)
        let itemID = try #require(UUID(uuidString: idString))

        let correctionOutput = try runCLI([
            "review", "correct", idString,
            "--path", "Research",
            "--reason", "Corrected during review.",
            "--actor", "agent",
            "--json",
        ], vaultURL: vault)
        let correction = try jsonObject(from: correctionOutput)
        #expect(correction["action"] as? String == "review.routing.correct")
        #expect(correction["itemID"] as? String == idString)
        #expect(correction["status"] as? String == "corrected")
        #expect(correction["reviewState"] as? String == "corrected")
        #expect(correction["actor"] as? String == "agent")
        #expect(correction["remainingActiveRoutingReviewCount"] as? Int == 0)

        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }

        let explanation = try CiderRoutingDecisionService(database: db).explain(itemID: itemID)
        #expect(explanation.latestDecision?.source == "routing.correct")
        #expect(explanation.latestDecision?.reviewState == "corrected")

        let assignment = MutationAuditService(database: db)
            .loadEntries()
            .first { $0.itemID == itemID && $0.action == "reassign_folder" }
        #expect(assignment?.metadata["classification"] == "routing_correction")
        #expect(assignment?.metadata["routingSource"] == "routing.correct")
        #expect(assignment?.metadata["targetRelativePath"] == "Research")

        let reviewCorrection = MutationAuditService(database: db)
            .loadEntries()
            .first { $0.itemID == itemID && $0.action == "review.routing.correct" }
        #expect(reviewCorrection?.source == .agent)
        #expect(reviewCorrection?.afterState["reviewState"] == "corrected")
        #expect(reviewCorrection?.metadata["targetRelativePath"] == "Research")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    @Test("schema creates second brain tables and FTS index")
    func schemaCreatesSecondBrainTablesAndFTSIndex() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        #expect(DatabaseMigrations.latestVersion >= 9)
        let expectedTables = [
            "item_sections",
            "content_chunks",
            "content_chunks_fts",
            "routing_decisions",
            "agent_actions",
            "owner_relations",
            "projects",
            "capture_events",
            "capture_attachments",
            "enrichment_outputs",
            "similarity_candidates",
        ]

        for table in expectedTables {
            let stmt = try db.prepare(
                "SELECT count(*) FROM sqlite_master WHERE name = ?;"
            )
            stmt.bind(table, at: 1)
            try stmt.step()
            #expect(stmt.int(at: 0) == 1, "Expected \(table) to exist")
        }
    }

    @Test("sections and chunks persist and search through FTS")
    func sectionsAndChunksPersistAndSearchThroughFTS() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        let section = SecondBrainSection(
            owner: owner,
            sectionKey: "problem",
            title: "Problem",
            body: "Walls of Markdown hide the current state.",
            source: "kanban_notes",
            sortOrder: 0
        )

        try store.upsertSection(section)
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: section.id,
                    source: "kanban_notes",
                    title: "Problem",
                    body: "The Stonewards card needs exact keyword recall and structured evidence.",
                    chunkIndex: 0
                )
            ]
        )

        let sections = try store.sections(for: owner)
        #expect(sections.map(\.sectionKey) == ["problem"])

        let results = try store.searchChunks(query: "Stonewards evidence", limit: 5)
        #expect(results.count == 1)
        #expect(results[0].owner == owner)
        #expect(results[0].title == "Problem")
        #expect(results[0].snippet.localizedCaseInsensitiveContains("Stonewards"))
    }

    @Test("FTS search treats hyphenated terms as literal content")
    func ftsSearchTreatsHyphenatedTermsAsLiteralContent() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    source: "kanban_notes",
                    title: "Hyphen Search",
                    body: "The second-brain card-a reference should be searchable.",
                    chunkIndex: 0
                )
            ]
        )

        #expect(try store.searchChunks(query: "second-brain", limit: 5).first?.owner == owner)
        #expect(try store.searchChunks(query: "card-a", limit: 5).first?.owner == owner)
    }

    @Test("replacing chunks removes stale FTS hits")
    func replacingChunksRemovesStaleFTSHits() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    source: "kanban_notes",
                    title: "Old",
                    body: "obsolete-token",
                    chunkIndex: 0
                )
            ]
        )
        try store.replaceChunks(
            owner: owner,
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    source: "kanban_notes",
                    title: "New",
                    body: "fresh-token",
                    chunkIndex: 0
                )
            ]
        )

        #expect(try store.searchChunks(query: "obsolete-token", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "fresh-token", limit: 5).first?.owner == owner)
    }

    @Test("routing decisions and agent actions are durable provenance")
    func routingDecisionsAndAgentActionsAreDurableProvenance() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: UUID().uuidString)

        let routing = SecondBrainRoutingDecision(
            owner: owner,
            targetType: "space",
            targetID: "recipes",
            targetPath: "Spaces/Recipes",
            confidence: 0.94,
            reason: "Recipe extraction matched ingredients and instructions.",
            status: "accepted",
            actor: "hermes",
            source: "agent"
        )
        try store.recordRoutingDecision(routing)

        let action = SecondBrainAgentAction(
            owner: owner,
            toolName: "item.route",
            actionType: "route",
            source: "agent",
            status: "succeeded",
            summary: "Routed bookmark to Recipes Space."
        )
        try store.recordAgentAction(action)

        #expect(try store.routingDecisions(for: owner).map(\.reason) == [routing.reason])
        #expect(try store.agentActions(for: owner).map(\.toolName) == ["item.route"])
    }

    @Test("routing service decisions bridge into item context for active item types")
    func routingServiceDecisionsBridgeIntoItemContextForActiveItemTypes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let routing = CiderRoutingDecisionService(database: db)
        let context = CiderItemContextService(database: db)
        let types: [LibraryEntityType] = [.bookmark, .note, .todo, .dateCard, .contact, .vaultFile]

        for type in types {
            let itemID = UUID()
            try db.runSQL("""
                INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
                VALUES ('\(itemID.uuidString)', '\(type.rawValue)', '\(type.rawValue) route', 1, 1, 'Inbox/\(type.rawValue)');
                """)

            let decision = try routing.recordDecision(
                itemID: itemID,
                itemType: type.rawValue,
                target: .init(kind: "inbox", name: "Inbox", relativePath: "Inbox", folderID: nil),
                confidence: 0,
                reason: "Needs second-brain review.",
                actor: "agent",
                source: "capture.add",
                reviewState: "needs_review"
            )

            let bundle = try context.context(for: LibraryEntityRef(type: type, entityID: itemID))
            #expect(bundle.routingDecisions.map(\.id) == [decision.id.uuidString])
            #expect(bundle.routingDecisions.first?.status == "needs_review")
            #expect(bundle.routingDecisions.first?.source == "capture.add")
            #expect(bundle.routingDecisions.first?.targetPath == "Inbox")
        }
    }

    @Test("review approvals append one provenance trail visible through item context")
    func reviewApprovalsAppendOneProvenanceTrailVisibleThroughItemContext() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let itemID = UUID()
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
            VALUES ('\(itemID.uuidString)', 'bookmark', 'Route me', 1, 1, 'Inbox/Bookmarks/Route me.webloc');
            """)

        let routing = CiderRoutingDecisionService(database: db)
        let original = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0,
            reason: "Needs a human route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let approved = try routing.approve(itemID: itemID, actor: "user").latestDecision

        let bundle = try CiderItemContextService(database: db)
            .context(for: LibraryEntityRef(type: .bookmark, entityID: itemID))
        #expect(bundle.routingDecisions.map(\.id) == [original.id.uuidString, approved?.id.uuidString])
        #expect(bundle.routingDecisions.map(\.status) == ["needs_review", "accepted"])
        #expect(bundle.routingDecisions.last?.source == "routing.approve")
    }

    @Test("process CLI item route rejects unresolved owners without durable provenance")
    func processCLIItemRouteRejectsUnresolvedOwnersWithoutDurableProvenance() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-route-phantom-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLIResult([
            "item", "route", "bookmark", "missing-bookmark",
            "--target-type", "space",
            "--target-id", "projects",
            "--reason", "Should not write for a phantom owner.",
            "--json",
        ], vaultURL: vault)
        let payload = try jsonObject(from: result.stdout)
        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect((payload["error"] as? String)?.contains("No bookmark found") == true)

        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }

        let secondBrain = try db.prepare("SELECT count(*) FROM second_brain_routing_decisions;")
        try secondBrain.step()
        #expect(secondBrain.int(at: 0) == 0)

        let legacy = try db.prepare("SELECT count(*) FROM routing_decisions;")
        try legacy.step()
        #expect(legacy.int(at: 0) == 0)
    }

    @Test("routing and agent provenance survive item deletion")
    func routingAndAgentProvenanceSurviveItemDeletion() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let itemID = UUID().uuidString
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at)
            VALUES ('\(itemID)', 'note', 'Deleted source item', 1, 1);
            """)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: itemID)
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: itemID,
                targetType: "space",
                targetID: "projects",
                targetPath: nil,
                confidence: 1,
                reason: "Keep routing audit after delete.",
                status: "accepted",
                actor: "test",
                source: "test"
            )
        )
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: itemID,
                toolName: "item.route",
                actionType: "route",
                source: "test",
                status: "succeeded",
                summary: "Audit retained."
            )
        )

        try db.runSQL("DELETE FROM items WHERE id = '\(itemID)';")

        #expect(try store.routingDecisions(for: owner).first?.itemID == nil)
        #expect(try store.agentActions(for: owner).first?.itemID == nil)
    }

    @Test("Kanban card notes parse into stable dashboard sections")
    func kanbanCardNotesParseIntoStableDashboardSections() {
        let notes = """
        One line before structured sections.

        ## Problem
        Walls of Markdown hide state.

        ## Acceptance Criteria
        - Agents can inspect the card.
        - Cider can render focused sections.
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["notes", "problem", "acceptance_criteria"])
        #expect(sections[1].title == "Problem")
        #expect(sections[1].body == "Walls of Markdown hide state.")
        #expect(sections[2].body.contains("Agents can inspect"))
    }

    @Test("Kanban parser merges duplicate headings and ignores fenced headings")
    func kanbanParserMergesDuplicateHeadingsAndIgnoresFencedHeadings() {
        let notes = """
        ## Evidence
        First proof.

        ```swift
        ## Not a real section
        let value = 1
        ```

        ## Evidence
        Second proof.

        ##NoSpace
        Plain text.
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["evidence"])
        #expect(sections[0].body.contains("First proof."))
        #expect(sections[0].body.contains("## Not a real section"))
        #expect(sections[0].body.contains("Second proof."))
        #expect(sections[0].body.contains("##NoSpace"))
    }

    @Test("Kanban parser promotes common plain labels into dashboard sections")
    func kanbanParserPromotesCommonPlainLabelsIntoDashboardSections() {
        let notes = """
        ## Second-Brain Foundation Program

        Problem:
        Agents infer too much from scattered prose.

        Research conclusion:
        SQLite stays the source of truth.

        Created: 2026-05-14
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["problem", "research_conclusion", "created"])
        #expect(sections[0].body == "Agents infer too much from scattered prose.")
        #expect(sections[1].body == "SQLite stays the source of truth.")
        #expect(sections[2].body == "2026-05-14")
    }

    @Test("Kanban parser normalizes escaped newline sequences from legacy card notes")
    func kanbanParserNormalizesEscapedNewlineSequencesFromLegacyCardNotes() {
        let notes = #"Problem:\nMilestones should render as readable text.\n\nGoal:\nDo not show literal escape characters."#

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.map(\.key) == ["problem", "goal"])
        #expect(sections[0].body == "Milestones should render as readable text.")
        #expect(sections[1].body == "Do not show literal escape characters.")
    }

    @Test("Kanban parser keeps explicit handoff heading when body starts with status")
    func kanbanParserKeepsExplicitHandoffHeadingWhenBodyStartsWithStatus() {
        let notes = """
        ## Agent Handoff
        Status: Dashboard v2 is verification-ready.

        Start here:
        - Run board card inspect.
        """

        let sections = KanbanCardSectionParser.sections(from: notes)

        #expect(sections.count == 1)
        #expect(sections[0].key == "agent_handoff")
        #expect(sections[0].body.contains("Status: Dashboard v2 is verification-ready."))
        #expect(sections[0].body.contains("Start here:"))
    }

    @Test("Kanban card section updates preserve sibling sections")
    func kanbanCardSectionUpdatesPreserveSiblingSections() {
        let notes = """
        ## Problem
        Old problem.

        ## Evidence
        - Existing proof.
        """

        let updated = KanbanCardSectionParser.updatingSection(
            in: notes,
            title: "Problem",
            body: "New problem."
        )

        #expect(updated.contains("## Problem\nNew problem."))
        #expect(updated.contains("## Evidence\n- Existing proof."))
    }

    @Test("Kanban section updates preserve unrelated Markdown shape")
    func kanbanSectionUpdatesPreserveUnrelatedMarkdownShape() {
        let notes = """
        Intro prose stays outside structured sections.

        ### Problem
        Old problem.

        #### Evidence
        - Existing proof.

        Goal: Keep this inline label intact.
        """

        let updated = KanbanCardSectionParser.updatingSection(
            in: notes,
            title: "Problem",
            body: "New problem."
        )

        #expect(updated.contains("Intro prose stays outside structured sections."))
        #expect(updated.contains("### Problem\nNew problem."))
        #expect(updated.contains("#### Evidence\n- Existing proof."))
        #expect(updated.contains("Goal: Keep this inline label intact."))
    }

    @Test("Kanban evidence appends to a durable section")
    func kanbanEvidenceAppendsToDurableSection() {
        let date = Date(timeIntervalSince1970: 1_778_700_000)
        let updated = KanbanCardSectionParser.appendingEvidence(
            to: "## Problem\nNeeds proof.",
            text: "Second-brain tests passed.",
            source: "swift test",
            at: date
        )

        #expect(updated.contains("## Test Evidence"))
        #expect(updated.contains("- 2026-05-13 19:20 - Second-brain tests passed. (source: swift test)"))
    }

    @Test("Kanban history appends typed timeline entries")
    func kanbanHistoryAppendsTypedTimelineEntries() {
        let date = Date(timeIntervalSince1970: 1_778_700_000)

        let updated = KanbanCardSectionParser.appendingHistory(
            to: "## Problem\nNeeds history.",
            type: "implementation",
            text: "Added the agent-readable history command.",
            source: "swift test",
            at: date
        )

        #expect(updated?.contains("## Implementation History") == true)
        #expect(updated?.contains("- 2026-05-13 19:20 - Added the agent-readable history command. (source: swift test)") == true)
    }

    @Test("Kanban commit history appends to the card history lane")
    func kanbanCommitHistoryAppendsToCardHistoryLane() {
        let date = Date(timeIntervalSince1970: 1_778_700_000)
        let updated = KanbanCardSectionParser.appendingHistory(
            to: "## Problem\nNeeds repo traceability.",
            type: "commit",
            text: "abc1234 touched Sources/CiderCLI/CiderCLI.swift.",
            source: "git",
            at: date
        )

        #expect(updated?.contains("## Commits") == true)

        let model = KanbanCardDashboardModel(title: "Repo traceability", notes: updated)
        #expect(model.historyEntries.contains {
            $0.title == "Commits"
                && $0.body.contains("abc1234")
                && $0.source == "git"
        })
    }

    @Test("Kanban card projection populates sections and searchable chunks")
    func kanbanCardProjectionPopulatesSectionsAndSearchableChunks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let card = KanbanCard(
            id: "card-a",
            title: "Build Stonewards dashboard",
            notes: """
            ## Problem
            Stonewards needs visible blockers.

            ## Test Evidence
            - Parser tests pass.
            """
        )

        try projector.refreshCard(boardID: "board-a", card: card)

        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        #expect(try store.sections(for: owner).map(\.sectionKey) == ["problem", "test_evidence"])
        #expect(try store.searchChunks(query: "Stonewards blockers", limit: 5).first?.owner == owner)
    }

    @Test("Kanban dashboard model builds second brain cockpit surfaces")
    func kanbanDashboardModelBuildsSecondBrainCockpitSurfaces() {
        let model = KanbanCardDashboardModel(
            title: "Second-brain foundation program",
            notes: """
            ## Second-Brain Foundation Program

            Problem:
            Agents still need to infer too much from YAML, Markdown, folders, and prose.

            Research conclusion:
            Keep SQLite as the canonical local memory/query layer. Use embeddings later as optional semantics.

            Phased implementation plan:
            1. Add additive SQLite v9 schema.
            2. Add agent-safe CLI/API commands.
            3. Add native Kanban Card Dashboard MVP.

            Non-goals for this branch:
            - No full rewrite.
            - No destructive cleanup of live vault data.

            Created: 2026-05-14

            ## Test Evidence
            - 2026-05-14 01:13 - Second-brain foundation pass 1 verified. (source: swift test)
            """
        )

        #expect(model.hasStructuredContent)
        #expect(model.problem?.contains("infer too much") == true)
        #expect(model.decisions.map(\.title) == ["Research conclusion"])
        #expect(model.openLoops.contains { $0.body.contains("Add agent-safe CLI/API commands") })
        #expect(model.evidenceEntries.first?.dateLabel == "2026-05-14 01:13")
        #expect(model.evidenceEntries.first?.source == "swift test")
        #expect(model.missingCoreSections.contains("Current State"))
        #expect(model.agentContext.updateTargets.contains("Test Evidence"))
    }

    @Test("Kanban dashboard model extracts related items and agent handoff labels")
    func kanbanDashboardModelExtractsRelatedItemsAndAgentHandoffLabels() {
        let model = KanbanCardDashboardModel(
            title: "Dashboard resurfacing engine V1",
            notes: """
            Goal: Make dashboard resurfacing explainable.

            Related existing cards:
            - eb3626 Second-brain Dashboard command center MVP
            - a71bc6 Dashboard command center: docs health and actionable cards

            Agent handoff:
            Future agents should append verification to Test Evidence and implementation notes to Implementation Evidence.

            ## Implementation History
            - 2026-05-14 03:00 - Added history support. (source: codex)
            """
        )

        #expect(model.goal == "Make dashboard resurfacing explainable.")
        #expect(model.relatedItems.count == 2)
        #expect(model.relatedItems[0].body.contains("eb3626"))
        #expect(model.historyEntries.first?.body == "Added history support.")
        #expect(model.historyEntries.first?.source == "codex")
        #expect(model.agentContext.notes.contains("Future agents should append verification"))
        #expect(model.agentContext.commands(board: "Cider", cardID: "abc123").contains {
            $0.contains("board comment add Cider --card abc123")
        })
        #expect(model.agentContext.commands(board: "Cider", cardID: "abc123").contains {
            $0.contains("board evidence add Cider --card abc123")
        })
        #expect(model.agentContext.commands(board: "Cider", cardID: "abc123").contains {
            $0.contains("board history add Cider --card abc123")
        })
    }

    @Test("Kanban dashboard model does not treat completed plan tasks as open loops")
    func kanbanDashboardModelDoesNotTreatCompletedPlanTasksAsOpenLoops() {
        let model = KanbanCardDashboardModel(
            title: "Finished foundation",
            notes: """
            Phased implementation plan:
            - [x] Add the schema.
            - [X] Verify the app.

            Next Step:
            User review.
            """
        )

        #expect(model.openLoops.isEmpty)
        #expect(model.nextStep == "User review.")
    }

    @Test("Kanban dashboard model promotes manual QA guidance")
    func kanbanDashboardModelPromotesManualQAGuidance() {
        let model = KanbanCardDashboardModel(
            title: "Readable long card sections",
            notes: """
            ## Problem
            Details are hard to scan.

            ## Manual QA Guidance
            - Open a Kanban card whose notes have headings.
            - Confirm a readable sections preview appears above the raw editor.
            - Edit raw notes and confirm the preview updates.
            """
        )

        #expect(model.testingGuidanceEntries.map(\.body) == [
            "Open a Kanban card whose notes have headings.",
            "Confirm a readable sections preview appears above the raw editor.",
            "Edit raw notes and confirm the preview updates.",
        ])
    }

    @Test("Kanban dashboard model promotes QA findings as agent-visible failed QA")
    func kanbanDashboardModelPromotesQAFindingsAsAgentVisibleFailedQA() {
        let model = KanbanCardDashboardModel(
            title: "QA companion failed notes",
            notes: """
            ## QA Findings
            Failed steps:
            - Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.

            Overall QA notes:
            The companion lost the summary after relaunch.
            """
        )

        #expect(model.hasFailedQA)
        #expect(model.qaFindingsEntries.map(\.body) == [
            "Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.",
            "The companion lost the summary after relaunch.",
        ])
        #expect(model.agentContext.updateTargets.contains("QA Findings"))
    }

    @Test("Kanban dashboard model falls back to acceptance criteria for testing guidance")
    func kanbanDashboardModelFallsBackToAcceptanceCriteriaForTestingGuidance() {
        let model = KanbanCardDashboardModel(
            title: "History section",
            notes: """
            ## Problem
            History is invisible.

            ## Acceptance criteria
            - Existing history entries are visible in card detail.
            - Users can add a typed history entry.
            """
        )

        #expect(model.testingGuidanceEntries.map(\.body) == [
            "Existing history entries are visible in card detail.",
            "Users can add a typed history entry.",
        ])
    }

    @Test("Kanban projection prunes stale sections")
    func kanbanProjectionPrunesStaleSections() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let original = KanbanCard(
            id: "card-a",
            title: "Refresh dashboard",
            notes: """
            ## Problem
            Needs structure.

            ## Evidence
            Old proof.
            """
        )
        let updated = KanbanCard(
            id: "card-a",
            title: "Refresh dashboard",
            notes: """
            ## Problem
            Needs structure.
            """
        )

        try projector.refreshCard(boardID: "board-a", card: original)
        try projector.refreshCard(boardID: "board-a", card: updated)

        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        #expect(try store.sections(for: owner).map(\.sectionKey) == ["problem"])
    }

    @Test("projection replacement rolls back sections and chunks together")
    func projectionReplacementRollsBackSectionsAndChunksTogether() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board-a/card-a")
        let original = SecondBrainSection(
            id: "original-section",
            owner: owner,
            sectionKey: "problem",
            title: "Problem",
            body: "old-token remains after rollback",
            source: "test",
            sortOrder: 0
        )
        try store.replaceProjection(
            owner: owner,
            sections: [original],
            keeping: ["problem"],
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: original.id,
                    source: "test",
                    title: "Problem",
                    body: "old-token remains after rollback",
                    chunkIndex: 0
                ),
            ]
        )

        let replacement = SecondBrainSection(
            id: "replacement-section",
            owner: owner,
            sectionKey: "decision",
            title: "Decision",
            body: "new-token should roll back",
            source: "test",
            sortOrder: 0
        )

        var didRollback = false
        do {
            try store.replaceProjection(
                owner: owner,
                sections: [replacement],
                keeping: ["decision"],
                chunks: [
                    SecondBrainChunkDraft(
                        sectionID: "missing-section",
                        source: "test",
                        title: "Decision",
                        body: "new-token should roll back",
                        chunkIndex: 0
                    ),
                ]
            )
            Issue.record("Expected invalid chunk section reference to roll back projection replacement")
        } catch {
            didRollback = true
        }

        #expect(didRollback)
        #expect(try store.sections(for: owner).map(\.sectionKey) == ["problem"])
        #expect(try store.searchChunks(query: "old-token", limit: 5).first?.owner == owner)
        #expect(try store.searchChunks(query: "new-token", limit: 5).isEmpty)
    }

    @Test("deleted Kanban card projection removes searchable chunks")
    func deletedKanbanCardProjectionRemovesSearchableChunks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        let card = KanbanCard(
            id: "card-a",
            title: "Ghost projection",
            notes: "## Problem\nphantom-token should disappear after delete."
        )
        let owner = SecondBrainKanbanProjectionService.owner(boardID: "board-a", cardID: card.id)

        try projector.refreshCard(boardID: "board-a", card: card)
        #expect(try store.searchChunks(query: "phantom-token", limit: 5).first?.owner == owner)

        try store.deleteProjection(for: owner)

        #expect(try store.sections(for: owner).isEmpty)
        #expect(try store.searchChunks(query: "phantom-token", limit: 5).isEmpty)
    }

    @Test("deleted Kanban board projection removes all projected cards")
    func deletedKanbanBoardProjectionRemovesAllProjectedCards() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let store = SecondBrainStore(database: db)
        let projector = SecondBrainKanbanProjectionService(store: store)
        try projector.refreshCard(
            boardID: "board-a",
            card: KanbanCard(id: "card-a", title: "A", notes: "## Problem\nboard-ghost-a")
        )
        try projector.refreshCard(
            boardID: "board-a",
            card: KanbanCard(id: "card-b", title: "B", notes: "## Problem\nboard-ghost-b")
        )
        try projector.refreshCard(
            boardID: "board-b",
            card: KanbanCard(id: "card-c", title: "C", notes: "## Problem\nsurviving-card")
        )

        try store.deleteProjections(ownerType: "kanban_card", ownerIDPrefix: "board-a/")

        #expect(try store.searchChunks(query: "board-ghost-a", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "board-ghost-b", limit: 5).isEmpty)
        #expect(try store.searchChunks(query: "surviving-card", limit: 5).count == 1)
    }

    @Test("v8 database migrates to current second brain tables")
    func v8DatabaseMigratesToCurrentSecondBrainTables() throws {
        let url = makeTempDBURL()
        defer { cleanup(url) }

        do {
            let db = CiderDatabase()
            try db.open(at: url)
            try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ai;")
            try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_ad;")
            try db.runSQL("DROP TRIGGER IF EXISTS content_chunks_au;")
            try db.runSQL("DROP TABLE IF EXISTS content_chunks_fts;")
            try db.runSQL("DROP TABLE IF EXISTS content_chunks;")
            try db.runSQL("DROP TABLE IF EXISTS item_sections;")
            try db.runSQL("DROP TABLE IF EXISTS routing_decisions;")
            try db.runSQL("DROP TABLE IF EXISTS agent_actions;")
            try db.runSQL("DELETE FROM schema_version;")
            try db.runSQL("INSERT INTO schema_version (version) VALUES (8);")
            db.close()
        }

        let migrated = CiderDatabase()
        try migrated.open(at: url)
        defer { migrated.close() }

        let version = try migrated.prepare("SELECT MAX(version) FROM schema_version;")
        try version.step()
        #expect(version.int(at: 0) == DatabaseMigrations.latestVersion)

        for table in ["item_sections", "content_chunks", "content_chunks_fts", "routing_decisions", "second_brain_routing_decisions", "agent_actions"] {
            let stmt = try migrated.prepare("SELECT count(*) FROM sqlite_master WHERE name = ?;")
            stmt.bind(table, at: 1)
            try stmt.step()
            #expect(stmt.int(at: 0) == 1, "Expected migrated database to include \(table)")
        }
    }

    @Test("process CLI supports normal agent card workflow")
    func processCLISupportsNormalAgentCardWorkflow() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-agent-workflow-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let itemHelp = try runCLI(["item", "--help"], vaultURL: vaultURL)
        #expect(itemHelp.contains("item get <type> <id-or-ref>"))
        #expect(itemHelp.contains("item owner-get <owner-type> <owner-id-or-ref>"))

        _ = try runCLI(["board", "create", "Agent Workflow Smoke"], vaultURL: vaultURL)
        let addOutput = try runCLI([
            "board", "add-card", "Agent Workflow Smoke",
            "--column", "Backlog",
            "--title", "Agent contract smoke",
            "--notes", """
            ## Problem
            Agents need structured Cider card context.

            ## Current State
            Created through process-level CLI smoke.

            ## Next Step
            Update state and add evidence through the CLI.
            """,
        ], vaultURL: vaultURL)

        let cardID = try #require(addOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1)
        let cardRef = String(cardID)
        let childOutput = try runCLI([
            "board", "add-card", "Agent Workflow Smoke",
            "--column", "Backlog",
            "--title", "Child context card",
            "--parent", cardRef,
        ], vaultURL: vaultURL)
        let childCardID = String(try #require(childOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let inspected = try jsonObject(from: runCLI([
            "board", "card", "inspect", "Agent Workflow Smoke",
            "--card", cardRef,
            "--json",
        ], vaultURL: vaultURL))
        let dashboard = try #require(inspected["dashboard"] as? [String: Any])
        #expect(dashboard["currentState"] as? String == "Created through process-level CLI smoke.")

        let updated = try jsonObject(from: runCLI([
            "board", "section", "update", "Agent Workflow Smoke",
            "--card", cardRef,
            "--section", "Current State",
            "--value", "Updated through board section update.",
            "--json",
        ], vaultURL: vaultURL))
        let updatedDashboard = try #require(updated["dashboard"] as? [String: Any])
        #expect(updatedDashboard["currentState"] as? String == "Updated through board section update.")

        let evidence = try jsonObject(from: runCLI([
            "board", "evidence", "add", "Agent Workflow Smoke",
            "--card", cardRef,
            "--text", "Process-level CLI evidence smoke passed.",
            "--source", "swift test process",
            "--json",
        ], vaultURL: vaultURL))
        let evidenceDashboard = try #require(evidence["dashboard"] as? [String: Any])
        let evidenceEntries = try #require(evidenceDashboard["evidenceEntries"] as? [[String: Any]])
        #expect(evidenceEntries.contains {
            ($0["body"] as? String)?.contains("Process-level CLI evidence smoke passed.") == true
        })

        let implementation = try jsonObject(from: runCLI([
            "board", "history", "add", "Agent Workflow Smoke",
            "--card", cardRef,
            "--type", "implementation",
            "--text", "Implemented agent-readable card history smoke.",
            "--source", "swift test process",
            "--json",
        ], vaultURL: vaultURL))
        let implementationSections = try #require(implementation["sections"] as? [[String: Any]])
        #expect(implementationSections.contains {
            $0["key"] as? String == "implementation_history"
                && ($0["body"] as? String)?.contains("Implemented agent-readable card history smoke.") == true
        })

        let failedAttempt = try jsonObject(from: runCLI([
            "board", "history", "add", "Agent Workflow Smoke",
            "--card", cardRef,
            "--type", "failed-attempt",
            "--text", "Tried raw YAML scraping and rejected it.",
            "--source", "swift test process",
            "--json",
        ], vaultURL: vaultURL))
        let failedAttemptSections = try #require(failedAttempt["sections"] as? [[String: Any]])
        #expect(failedAttemptSections.contains {
            $0["key"] as? String == "failed_attempts"
                && ($0["body"] as? String)?.contains("Tried raw YAML scraping and rejected it.") == true
        })

        let commit = try jsonObject(from: runCLI([
            "board", "history", "add", "Agent Workflow Smoke",
            "--card", cardRef,
            "--type", "commit",
            "--text", "abc1234 touched Sources/CiderCLI/CiderCLI.swift and Tests/CiderTests/SecondBrainFoundationTests.swift.",
            "--source", "git",
            "--json",
        ], vaultURL: vaultURL))
        let commitSections = try #require(commit["sections"] as? [[String: Any]])
        #expect(commitSections.contains {
            $0["key"] as? String == "commits"
                && ($0["body"] as? String)?.contains("abc1234 touched Sources/CiderCLI/CiderCLI.swift") == true
        })

        _ = try runCLI([
            "item", "backfill-kanban",
            "--board", "Agent Workflow Smoke",
            "--json",
        ], vaultURL: vaultURL)

        let item = try jsonObject(from: runCLI([
            "item", "owner-get", "card", cardRef,
            "--json",
        ], vaultURL: vaultURL))
        #expect(item["command"] as? String == "item.owner-get")
        #expect(item["legacyOwnerInspection"] as? Bool == true)
        let sections = try #require(item["sections"] as? [[String: Any]])
        #expect(sections.contains { $0["sectionKey"] as? String == "current_state" })
        #expect(sections.contains {
            ($0["body"] as? String)?.contains("Process-level CLI evidence smoke passed.") == true
        })
        #expect(sections.contains { $0["sectionKey"] as? String == "implementation_history" })
        #expect(sections.contains { $0["sectionKey"] as? String == "failed_attempts" })
        #expect(sections.contains { $0["sectionKey"] as? String == "commits" })

        let searchResults = try jsonObjectArray(from: runCLI([
            "item", "search", "raw YAML scraping rejected",
            "--json",
        ], vaultURL: vaultURL))
        #expect(searchResults.contains {
            guard let owner = $0["owner"] as? [String: Any],
                  owner["ownerType"] as? String == "kanban_card",
                  let ownerID = owner["ownerID"] as? String else {
                return false
            }
            return ownerID.hasSuffix("/\(cardRef)")
        })

        let unifiedCard = try jsonObject(from: runCLI([
            "item", "get", "card", cardRef,
            "--json",
        ], vaultURL: vaultURL))
        #expect(unifiedCard["ok"] as? Bool == true)
        #expect(unifiedCard["deprecated"] == nil)
        let unifiedItem = try #require(unifiedCard["item"] as? [String: Any])
        #expect(unifiedItem["id"] as? String == cardRef)
        #expect(unifiedItem["type"] as? String == "kanban_card")
        #expect(unifiedItem["title"] as? String == "Agent contract smoke")
        #expect(unifiedItem["boardID"] as? String != nil)
        #expect(unifiedItem["boardName"] as? String == "Agent Workflow Smoke")
        #expect(unifiedItem["columnName"] as? String == "Backlog")
        #expect(unifiedItem["relativePath"] as? String == "Agent Workflow Smoke/\(cardRef)")

        let unifiedSections = try #require(unifiedCard["sections"] as? [[String: Any]])
        #expect(unifiedSections.contains { $0["sectionKey"] as? String == "current_state" })
        #expect(unifiedSections.contains { $0["sectionKey"] as? String == "implementation_history" })

        let relatedCards = try jsonObjectArray(from: runCLI([
            "item", "related", "card", cardRef,
            "--json",
        ], vaultURL: vaultURL))
        #expect(relatedCards.contains {
            $0["id"] as? String == childCardID
                && $0["type"] as? String == "kanban_card"
                && $0["relationship"] as? String == "child"
        })

        let cardContext = try jsonObject(from: runCLI([
            "item", "context", "card", cardRef,
            "--max-sections", "2",
            "--max-history", "5",
            "--json",
        ], vaultURL: vaultURL))
        #expect(cardContext["ok"] as? Bool == true)
        let contextItem = try #require(cardContext["item"] as? [String: Any])
        #expect(contextItem["id"] as? String == cardRef)
        #expect(contextItem["type"] as? String == "kanban_card")
        #expect(cardContext["summary"] as? String == "Updated through board section update.")
        let contentBlocks = try #require(cardContext["contentBlocks"] as? [[String: Any]])
        #expect(contentBlocks.contains {
            $0["kind"] as? String == "section"
                && $0["title"] as? String == "Current State"
                && $0["body"] as? String == "Updated through board section update."
        })
        let contextHistory = try #require(cardContext["recentHistory"] as? [[String: Any]])
        #expect(contextHistory.contains {
            $0["kind"] as? String == "commit"
                && ($0["summary"] as? String)?.contains("abc1234") == true
        })
        #expect(contextHistory.contains {
            $0["kind"] as? String == "failed_attempt"
                && ($0["summary"] as? String)?.contains("raw YAML scraping") == true
        })
        let safeCommands = try #require(cardContext["safeCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item get card \(cardRef) --json"))
        #expect(safeCommands.contains("cider-cli board card inspect Agent Workflow Smoke --card \(cardRef) --json"))

        let whySurfaced = try jsonObject(from: runCLI([
            "item", "why-surfaced", "card", cardRef,
            "--json",
        ], vaultURL: vaultURL))
        #expect(whySurfaced["ok"] as? Bool == true)
        let contextSurfacing = try #require(cardContext["surfacing"] as? [String: Any])
        let whySurfacing = try #require(whySurfaced["surfacing"] as? [String: Any])
        #expect(whySurfacing["reason"] as? String == contextSurfacing["reason"] as? String)
        #expect(whySurfacing["sourceSignal"] as? String == "kanban_context")
        #expect(whySurfacing["suggestedAction"] as? String == contextSurfacing["suggestedAction"] as? String)
    }

    @Test("process CLI exposes parent child rollup on card inspect")
    func processCLIExposesParentChildRollupOnCardInspect() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-child-rollup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Rollup Smoke"], vaultURL: vaultURL)
        _ = try runCLI(["board", "add-column", "Rollup Smoke", "--name", "Queued"], vaultURL: vaultURL)
        _ = try runCLI(["board", "add-column", "Rollup Smoke", "--name", "Testing"], vaultURL: vaultURL)

        let parentOutput = try runCLI([
            "board", "add-card", "Rollup Smoke",
            "--column", "Backlog",
            "--title", "Parent roadmap",
        ], vaultURL: vaultURL)
        let parentID = String(try #require(parentOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Rollup Smoke",
            "--column", "Queued",
            "--title", "Queued child",
            "--parent", parentID,
        ], vaultURL: vaultURL)
        _ = try runCLI([
            "board", "add-card", "Rollup Smoke",
            "--column", "Testing",
            "--title", "Failed QA child",
            "--notes", """
            ## QA Results
            - Step 1 failed: Expected status copy was missing.
            """,
            "--parent", parentID,
        ], vaultURL: vaultURL)

        let inspected = try jsonObject(from: runCLI([
            "board", "card", "inspect", "Rollup Smoke",
            "--card", parentID,
            "--json",
        ], vaultURL: vaultURL))
        let rollup = try #require(inspected["childRollup"] as? [String: Any])
        let counts = try #require(rollup["counts"] as? [String: Any])
        let failedQAChild = try #require(rollup["failedQAChild"] as? [String: Any])
        let nextActionableChild = try #require(rollup["nextActionableChild"] as? [String: Any])

        #expect(rollup["totalChildCount"] as? Int == 2)
        #expect(counts["queued"] as? Int == 1)
        #expect(counts["testing"] as? Int == 1)
        #expect(failedQAChild["title"] as? String == "Failed QA child")
        #expect(nextActionableChild["title"] as? String == "Failed QA child")
        #expect(rollup["nextActionLine"] as? String == "Fix failed QA on Failed QA child.")
    }

    @Test("process CLI exposes second brain capability map for agents")
    func processCLIExposesSecondBrainCapabilityMapForAgents() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-capability-map-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let map = try jsonObject(from: runCLI([
            "item", "capability-map",
            "--json",
        ], vaultURL: vaultURL))

        #expect(map["ok"] as? Bool == true)
        #expect(map["purpose"] as? String == "second_brain_agent_capability_map")
        let areas = try #require(map["areas"] as? [[String: Any]])
        #expect(areas.count >= 8)
        #expect(areas.contains {
            $0["id"] as? String == "retrieve"
                && $0["status"] as? String == "usable"
                && (($0["affordanceTargets"] as? [String]) ?? []).contains("item get/search/related/context/why-surfaced")
        })
        #expect(areas.contains {
            $0["id"] as? String == "reduce_adhd_burden"
                && (($0["agentGuidance"] as? String)?.contains("smallest safe next action") == true)
        })
        let nextActions = try #require(map["nextActions"] as? [String])
        #expect(nextActions.contains("Use item search/get/context/why-surfaced before reading files or scraping folders."))
    }

    @Test("process CLI exposes roadmap next up on parent card inspect")
    func processCLIExposesRoadmapNextUpOnParentCardInspect() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-next-up-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Next Up Smoke"], vaultURL: vaultURL)
        _ = try runCLI(["board", "add-column", "Next Up Smoke", "--name", "Queued"], vaultURL: vaultURL)

        let parentOutput = try runCLI([
            "board", "add-card", "Next Up Smoke",
            "--column", "Backlog",
            "--title", "Parent roadmap",
        ], vaultURL: vaultURL)
        let parentID = String(try #require(parentOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Next Up Smoke",
            "--column", "Backlog",
            "--title", "Backlog child",
            "--parent", parentID,
        ], vaultURL: vaultURL)
        _ = try runCLI([
            "board", "add-card", "Next Up Smoke",
            "--column", "Queued",
            "--title", "Queued child",
            "--parent", parentID,
        ], vaultURL: vaultURL)

        let inspected = try jsonObject(from: runCLI([
            "board", "card", "inspect", "Next Up Smoke",
            "--card", parentID,
            "--json",
        ], vaultURL: vaultURL))
        let nextUp = try #require(inspected["roadmapNextUp"] as? [String: Any])
        let sequence = try #require(nextUp["sequence"] as? [[String: Any]])
        let currentGate = try #require(nextUp["currentGate"] as? [String: Any])
        let suggestedInsertion = try #require(nextUp["suggestedInsertion"] as? [String: Any])

        #expect(nextUp["nextActionLine"] as? String == "Start Queued child.")
        #expect(sequence.map { $0["stepNumber"] as? Int } == [1, 2])
        #expect(sequence.map { $0["title"] as? String } == ["Backlog child", "Queued child"])
        #expect(sequence[1]["isCurrentGate"] as? Bool == true)
        #expect(sequence[1]["isNextActionable"] as? Bool == true)
        #expect(currentGate["title"] as? String == "Queued child")
        #expect(suggestedInsertion["columnName"] as? String == "Queued")
        #expect(suggestedInsertion["command"] as? String == "cider-cli board add-card \"Next Up Smoke\" --column \"Queued\" --title \"<title>\" --parent \(parentID) --after \(sequence[1]["id"] as? String ?? "")")
    }

    @Test("process CLI inserts roadmap child after sibling")
    func processCLIInsertsRoadmapChildAfterSibling() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-insert-child-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Insert Child Smoke"], vaultURL: vaultURL)
        let parentOutput = try runCLI([
            "board", "add-card", "Insert Child Smoke",
            "--column", "Backlog",
            "--title", "Parent roadmap",
        ], vaultURL: vaultURL)
        let parentID = String(try #require(parentOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let firstOutput = try runCLI([
            "board", "add-card", "Insert Child Smoke",
            "--column", "Backlog",
            "--title", "First child",
            "--parent", parentID,
        ], vaultURL: vaultURL)
        let firstID = String(try #require(firstOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Insert Child Smoke",
            "--column", "Backlog",
            "--title", "Third child",
            "--parent", parentID,
        ], vaultURL: vaultURL)

        _ = try runCLI([
            "board", "add-card", "Insert Child Smoke",
            "--column", "Backlog",
            "--title", "Second child",
            "--parent", parentID,
            "--after", firstID,
        ], vaultURL: vaultURL)

        let inspected = try jsonObject(from: runCLI([
            "board", "card", "inspect", "Insert Child Smoke",
            "--card", parentID,
            "--json",
        ], vaultURL: vaultURL))
        let nextUp = try #require(inspected["roadmapNextUp"] as? [String: Any])
        let sequence = try #require(nextUp["sequence"] as? [[String: Any]])

        #expect(sequence.map { $0["title"] as? String } == ["First child", "Second child", "Third child"])
    }

    @Test("process CLI summarizes parent rollup and refreshes stale parent sections")
    func processCLISummarizesParentRollupAndRefreshesStaleParentSections() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-parent-summary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Parent Summary Smoke"], vaultURL: vaultURL)
        _ = try runCLI(["board", "add-column", "Parent Summary Smoke", "--name", "Queued"], vaultURL: vaultURL)
        _ = try runCLI(["board", "add-column", "Parent Summary Smoke", "--name", "Done", "--done"], vaultURL: vaultURL)

        let parentOutput = try runCLI([
            "board", "add-card", "Parent Summary Smoke",
            "--column", "Backlog",
            "--title", "Parent roadmap",
            "--notes", """
            ## Current State
            Waiting on Done child.

            ## Next Step
            Finish Done child.
            """,
        ], vaultURL: vaultURL)
        let parentID = String(try #require(parentOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Parent Summary Smoke",
            "--column", "Backlog",
            "--title", "Open child",
            "--parent", parentID,
        ], vaultURL: vaultURL)
        _ = try runCLI([
            "board", "add-card", "Parent Summary Smoke",
            "--column", "Done",
            "--title", "Done child",
            "--parent", parentID,
        ], vaultURL: vaultURL)

        let dryRun = try jsonObject(from: runCLI([
            "board", "parent-summary", "Parent Summary Smoke",
            "--card", parentID,
            "--refresh",
            "--dry-run",
            "--json",
        ], vaultURL: vaultURL))

        #expect(dryRun["applied"] as? Bool == false)
        let stale = try #require(dryRun["staleParentText"] as? [String: Any])
        let findings = try #require(stale["findings"] as? [[String: Any]])
        #expect(findings.contains {
            $0["section"] as? String == "Next Step"
                && ($0["referencedDoneChildID"] as? String) != nil
        })
        let proposed = try #require(dryRun["proposedSections"] as? [String: String])
        #expect(proposed["Next Step"] == "Queue Open child.")

        let applied = try jsonObject(from: runCLI([
            "board", "parent-summary", "Parent Summary Smoke",
            "--card", parentID,
            "--refresh",
            "--confirm",
            "--json",
        ], vaultURL: vaultURL))
        #expect(applied["applied"] as? Bool == true)

        let inspected = try jsonObject(from: runCLI([
            "board", "card", "inspect", "Parent Summary Smoke",
            "--card", parentID,
            "--json",
        ], vaultURL: vaultURL))
        let dashboard = try #require(inspected["dashboard"] as? [String: Any])
        #expect(dashboard["nextStep"] as? String == "Queue Open child.")
        #expect((dashboard["currentState"] as? String)?.contains("2 children: 1 backlog, 1 done.") == true)
    }

    @Test("process CLI lists recent Kanban cards with agent context")
    func processCLIListsRecentKanbanCardsWithAgentContext() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-board-recent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Recent Smoke"], vaultURL: vaultURL)
        let parentOutput = try runCLI([
            "board", "add-card", "Recent Smoke",
            "--column", "Backlog",
            "--title", "Parent roadmap",
        ], vaultURL: vaultURL)
        let parentID = String(try #require(parentOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Recent Smoke",
            "--column", "Backlog",
            "--title", "Older child",
            "--parent", parentID,
        ], vaultURL: vaultURL)
        let latestOutput = try runCLI([
            "board", "add-card", "Recent Smoke",
            "--column", "Backlog",
            "--title", "Latest child",
            "--notes", """
            ## Current State
            Ready for recent-card discovery.

            ## Next Step
            Pick this card without knowing its ID.
            """,
            "--priority", "high",
            "--parent", parentID,
        ], vaultURL: vaultURL)
        let latestID = String(try #require(latestOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let recent = try jsonObject(from: runCLI([
            "board", "recent", "Recent Smoke",
            "--limit", "1",
            "--json",
        ], vaultURL: vaultURL))

        let cards = try #require(recent["cards"] as? [[String: Any]])
        #expect(cards.count == 1)
        let first = try #require(cards.first)
        #expect(first["id"] as? String == latestID)
        #expect(first["title"] as? String == "Latest child")
        #expect(first["priority"] as? String == "high")
        #expect(first["parentCardID"] as? String == parentID)
        #expect(first["activityKind"] as? String == "created")
        #expect(first["summary"] as? String == "Ready for recent-card discovery.")

        let column = try #require(first["column"] as? [String: Any])
        #expect(column["name"] as? String == "Backlog")

        let parent = try #require(first["parent"] as? [String: Any])
        #expect(parent["id"] as? String == parentID)
        #expect(parent["title"] as? String == "Parent roadmap")
    }

    @Test("process CLI ranks edited cards first in recent Kanban activity")
    func processCLIRanksEditedCardsFirstInRecentKanbanActivity() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-board-activity-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Activity Smoke"], vaultURL: vaultURL)
        let olderOutput = try runCLI([
            "board", "add-card", "Activity Smoke",
            "--column", "Backlog",
            "--title", "Older but edited",
            "--notes", """
            ## Current State
            Waiting.
            """,
        ], vaultURL: vaultURL)
        let olderID = String(try #require(olderOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Activity Smoke",
            "--column", "Backlog",
            "--title", "Newer untouched",
        ], vaultURL: vaultURL)

        _ = try runCLI([
            "board", "section", "update", "Activity Smoke",
            "--card", olderID,
            "--section", "Current State",
            "--value", "Edited after the newer card was created.",
            "--json",
        ], vaultURL: vaultURL)

        let recent = try jsonObject(from: runCLI([
            "board", "recent", "Activity Smoke",
            "--limit", "1",
            "--json",
        ], vaultURL: vaultURL))
        let cards = try #require(recent["cards"] as? [[String: Any]])
        let first = try #require(cards.first)
        #expect(first["id"] as? String == olderID)
        #expect(first["title"] as? String == "Older but edited")
        #expect(first["activityKind"] as? String == "updated")
        #expect(first["updatedAt"] as? String != nil)
    }

    @Test("process CLI summarizes testing queue by owner")
    func processCLISummarizesTestingQueueByOwner() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-testing-summary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Testing Summary Smoke"], vaultURL: vaultURL)
        _ = try runCLI([
            "board", "add-column", "Testing Summary Smoke",
            "--name", "Testing",
        ], vaultURL: vaultURL)

        let manualOutput = try runCLI([
            "board", "add-card", "Testing Summary Smoke",
            "--column", "Testing",
            "--title", "Manual card detail QA",
            "--notes", """
            ## Current State
            Manual QA needed: open the card detail UI and confirm history is readable.

            ## Next Step
            Erik should inspect the visible card detail flow.
            """,
        ], vaultURL: vaultURL)
        let manualID = String(try #require(manualOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let agentOutput = try runCLI([
            "board", "add-card", "Testing Summary Smoke",
            "--column", "Testing",
            "--title", "CLI JSON contract QA",
            "--notes", """
            ## Current State
            Agent can verify through CLI JSON smoke coverage.

            ## Next Step
            Run board recent --json and inspect the response.
            """,
        ], vaultURL: vaultURL)
        let agentID = String(try #require(agentOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        _ = try runCLI([
            "board", "add-card", "Testing Summary Smoke",
            "--column", "Testing",
            "--title", "Passed QA wording smoke",
            "--notes", """
            ## Test Evidence
            - swift test --filter KanbanAgentWorkflowTests passed.

            ## QA Results
            - Step 1 passed: Confirm failed rows can be cleared.
            - Step 2 passed: After recording a failed step, inspect testing summary.
            """,
        ], vaultURL: vaultURL)

        let summary = try jsonObject(from: runCLI([
            "board", "testing-summary", "Testing Summary Smoke",
            "--json",
        ], vaultURL: vaultURL))

        let counts = try #require(summary["counts"] as? [String: Any])
        #expect(counts["total"] as? Int == 3)
        #expect(counts["needsErik"] as? Int == 1)
        #expect(counts["agentCanVerify"] as? Int == 1)
        #expect(counts["mixed"] as? Int == 1)

        let needsErik = try #require(summary["needsErik"] as? [[String: Any]])
        let manual = try #require(needsErik.first { $0["id"] as? String == manualID })
        #expect(manual["owner"] as? String == "needs_erik")

        let agentCanVerify = try #require(summary["agentCanVerify"] as? [[String: Any]])
        let agentIDs = agentCanVerify.compactMap { $0["id"] as? String }
        #expect(agentIDs.contains(agentID))
        let mixed = try #require(summary["mixed"] as? [[String: Any]])
        let allTestingCards = needsErik + agentCanVerify + mixed
        let passedQA = try #require(allTestingCards.first { $0["title"] as? String == "Passed QA wording smoke" })
        #expect((passedQA["failedQASteps"] as? [String])?.isEmpty == true)
    }

    @Test("process CLI exposes QA findings on card inspect")
    func processCLIExposesQAFindingsOnCardInspect() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-qa-findings-inspect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "QA Findings Inspect Smoke"], vaultURL: vaultURL)
        _ = try runCLI([
            "board", "add-column", "QA Findings Inspect Smoke",
            "--name", "Testing",
        ], vaultURL: vaultURL)
        let addOutput = try runCLI([
            "board", "add-card", "QA Findings Inspect Smoke",
            "--column", "Testing",
            "--title", "Failed QA finding",
            "--notes", """
            ## QA Findings
            Failed steps:
            - Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.

            Overall QA notes:
            The companion lost the summary after relaunch.
            """,
        ], vaultURL: vaultURL)
        let cardID = String(try #require(addOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let inspected = try jsonObject(from: runCLI([
            "board", "card", "inspect", "QA Findings Inspect Smoke",
            "--card", cardID,
            "--json",
        ], vaultURL: vaultURL))

        #expect(inspected["hasFailedQA"] as? Bool == true)
        #expect((inspected["failedQASteps"] as? [String]) == [
            "Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.",
        ])
        let dashboard = try #require(inspected["dashboard"] as? [String: Any])
        #expect(dashboard["hasFailedQA"] as? Bool == true)
        let findings = try #require(dashboard["qaFindingsEntries"] as? [[String: Any]])
        #expect(findings.compactMap { $0["body"] as? String } == [
            "Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.",
            "The companion lost the summary after relaunch.",
        ])
    }

    @Test("process CLI creates and attaches milestone cards safely")
    func processCLICreatesAndAttachesMilestoneCardsSafely() throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-milestone-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        _ = try runCLI(["board", "create", "Milestone CLI Smoke"], vaultURL: vaultURL)

        let created = try jsonObject(from: runCLI([
            "board", "milestone", "create", "Milestone CLI Smoke",
            "--title", "Project Board UX MVP",
            "--description", "Make Cider's project board calm, filterable, and controllable.",
            "--json",
        ], vaultURL: vaultURL))
        #expect(created["ok"] as? Bool == true)
        let milestone = try #require(created["milestone"] as? [String: Any])
        let milestoneID = try #require(milestone["id"] as? String)
        #expect(milestone["title"] as? String == "Milestone: Project Board UX MVP")
        #expect((milestone["tags"] as? [String])?.contains("milestone") == true)
        #expect((milestone["tags"] as? [String])?.contains("milestone-object") == true)
        #expect(milestone["childCount"] as? Int == 0)

        let list = try jsonObject(from: runCLI([
            "board", "milestone", "list", "Milestone CLI Smoke",
            "--json",
        ], vaultURL: vaultURL))
        let milestones = try #require(list["milestones"] as? [[String: Any]])
        #expect(milestones.map { $0["id"] as? String }.contains(milestoneID))

        let childOutput = try runCLI([
            "board", "add-card", "Milestone CLI Smoke",
            "--column", "Backlog",
            "--title", "Add global Kanban display options popover",
        ], vaultURL: vaultURL)
        let childID = String(try #require(childOutput.firstMatch(of: /\[([A-Za-z0-9]+)\]/)?.1))

        let attached = try jsonObject(from: runCLI([
            "board", "milestone", "attach-card", "Milestone CLI Smoke",
            "--milestone", milestoneID,
            "--card", childID,
            "--json",
        ], vaultURL: vaultURL))
        #expect(attached["ok"] as? Bool == true)
        let attachedCard = try #require(attached["card"] as? [String: Any])
        #expect(attachedCard["parentCardID"] as? String == milestoneID)
        #expect((attachedCard["notes"] as? String)?.contains("Attached to milestone") == true)

        let inspected = try jsonObject(from: runCLI([
            "board", "milestone", "inspect", "Milestone CLI Smoke",
            "--milestone", milestoneID,
            "--json",
        ], vaultURL: vaultURL))
        let inspectedMilestone = try #require(inspected["milestone"] as? [String: Any])
        #expect(inspectedMilestone["childCount"] as? Int == 1)
        let children = try #require(inspected["children"] as? [[String: Any]])
        #expect(children.map { $0["id"] as? String } == [childID])
    }

    @Test("Kanban testing guide panel payload keeps QA steps portable")
    func kanbanTestingGuidePanelPayloadKeepsQAStepsPortable() {
        let dashboard = KanbanCardDashboardModel(
            title: "Ready to test card",
            notes: """
            ## Manual QA Guidance
            1. Open the Media Space.
            2. Confirm the dashboard stays visible while the QA companion is open.
            """
        )

        let model = KanbanTestingGuidePanelModel(
            boardID: "2afee0",
            boardName: "Cider",
            cardID: "abc123",
            cardTitle: "Ready to test card",
            entries: dashboard.testingGuidanceEntries
        )
        let payload = model.payload

        #expect(payload.id == "2afee0:abc123")
        #expect(payload.cardTitle == "Ready to test card")
        #expect(payload.steps.map(\.text) == [
            "Open the Media Space.",
            "Confirm the dashboard stays visible while the QA companion is open.",
        ])
    }

    @MainActor
    @Test("Kanban testing guide progress persists per card guide")
    func kanbanTestingGuideProgressPersistsPerCardGuide() throws {
        let suiteName = "KanbanTestingGuideProgressStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let step = KanbanTestingGuideStep(id: "manual_qa_guidance-0", text: "Open the QA companion.")
        let store = KanbanTestingGuideProgressStore(defaults: defaults)
        store.setCompleted(true, guideID: "2afee0:abc123", stepID: step.id)

        let restoredStore = KanbanTestingGuideProgressStore(defaults: defaults)
        #expect(restoredStore.isCompleted(guideID: "2afee0:abc123", stepID: step.id))
        #expect(restoredStore.completedCount(guideID: "2afee0:abc123", steps: [step]) == 1)

        restoredStore.toggle(guideID: "2afee0:abc123", stepID: step.id)
        #expect(!restoredStore.isCompleted(guideID: "2afee0:abc123", stepID: step.id))
    }

    @MainActor
    @Test("Kanban testing guide persists failed step notes")
    func kanbanTestingGuidePersistsFailedStepNotes() throws {
        let suiteName = "KanbanTestingGuideResultStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let step = KanbanTestingGuideStep(id: "manual_qa_guidance-0", text: "Click approve.")
        let store = KanbanTestingGuideProgressStore(defaults: defaults)
        store.setResult(.failed, note: "Approve opened the slideout instead.", guideID: "2afee0:abc123", stepID: step.id)

        let restoredStore = KanbanTestingGuideProgressStore(defaults: defaults)
        let result = try #require(restoredStore.result(guideID: "2afee0:abc123", stepID: step.id))
        #expect(result.status == .failed)
        #expect(result.note == "Approve opened the slideout instead.")
        #expect(restoredStore.failedCount(guideID: "2afee0:abc123", steps: [step]) == 1)
    }

    @MainActor
    @Test("Kanban testing guide persists overall QA notes per guide")
    func kanbanTestingGuidePersistsOverallQANotesPerGuide() throws {
        let suiteName = "KanbanTestingGuideOverallNotesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = KanbanTestingGuideProgressStore(defaults: defaults)
        store.setOverallNote("  Retest after relaunch; summary disappeared.  ", guideID: "2afee0:abc123")

        let restoredStore = KanbanTestingGuideProgressStore(defaults: defaults)
        #expect(restoredStore.overallNote(guideID: "2afee0:abc123") == "Retest after relaunch; summary disappeared.")

        restoredStore.setOverallNote("   ", guideID: "2afee0:abc123")
        #expect(restoredStore.overallNote(guideID: "2afee0:abc123") == nil)
    }

    @Test("Kanban testing guide sync applies the clicked step result")
    func kanbanTestingGuideSyncAppliesClickedStepResult() {
        let firstStep = KanbanTestingGuideStep(id: "manual_qa_guidance-0", text: "Open the QA companion.")
        let secondStep = KanbanTestingGuideStep(id: "manual_qa_guidance-1", text: "Confirm failed steps show notes.")
        let steps = [firstStep, secondStep]

        let passedResults = KanbanTestingGuideCardResultSync.resultsByApplying(
            [:],
            step: firstStep,
            status: .passed,
            note: nil
        )
        let failedResults = KanbanTestingGuideCardResultSync.resultsByApplying(
            passedResults,
            step: secondStep,
            status: .failed,
            note: "The note did not sync."
        )

        #expect(KanbanTestingGuideCardResultSync.qaResultsBody(steps: steps, results: failedResults) == """
        - Step 1 passed: Open the QA companion.
        - Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.
        """)

        let clearedResults = KanbanTestingGuideCardResultSync.resultsByApplying(
            failedResults,
            step: secondStep,
            status: nil,
            note: nil
        )
        #expect(KanbanTestingGuideCardResultSync.qaResultsBody(steps: steps, results: clearedResults) == "- Step 1 passed: Open the QA companion.")
    }

    @Test("Kanban testing guide sync builds structured QA findings")
    func kanbanTestingGuideSyncBuildsStructuredQAFindings() {
        let firstStep = KanbanTestingGuideStep(id: "manual_qa_guidance-0", text: "Open the QA companion.")
        let secondStep = KanbanTestingGuideStep(id: "manual_qa_guidance-1", text: "Confirm failed steps show notes.")
        let steps = [firstStep, secondStep]
        let results = KanbanTestingGuideCardResultSync.resultsByApplying(
            [
                firstStep.id: KanbanTestingGuideStepResult(status: .passed, note: nil, updatedAt: Date()),
            ],
            step: secondStep,
            status: .failed,
            note: "The note did not sync."
        )

        #expect(KanbanTestingGuideCardResultSync.qaFindingsBody(
            steps: steps,
            results: results,
            overallNote: "The companion lost the summary after relaunch."
        ) == """
        Failed steps:
        - Step 2 failed: Confirm failed steps show notes. Note: The note did not sync.

        Overall QA notes:
        The companion lost the summary after relaunch.
        """)

        #expect(KanbanTestingGuideCardResultSync.qaFindingsBody(
            steps: steps,
            results: [firstStep.id: KanbanTestingGuideStepResult(status: .passed, note: nil, updatedAt: Date())],
            overallNote: "   "
        ) == "")
    }
}
