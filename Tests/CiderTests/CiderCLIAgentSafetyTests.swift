import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider CLI Agent Safety Tests")
@MainActor
struct CiderCLIAgentSafetyTests {
    @Test("reminder validation errors honor json output")
    func reminderValidationErrorsHonorJSONOutput() throws {
        let result = try runCLI(args: ["reminder", "complete", "todo", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli reminder complete") == true)
    }

    @Test("bookmark date suggestion validation errors honor json output")
    func bookmarkDateSuggestionValidationErrorsHonorJSONOutput() throws {
        let result = try runCLI(args: ["bookmark", "date-suggestions", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli bookmark date-suggestions") == true)
    }

    @Test("bookmark date suggestion approval validation errors honor json output")
    func bookmarkDateSuggestionApprovalValidationErrorsHonorJSONOutput() throws {
        let result = try runCLI(args: ["bookmark", "date-suggestions", "approve", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("Usage: cider-cli bookmark date-suggestions approve") == true)
    }

    @Test("review batch enrichment requires explicit confirmation")
    func reviewBatchEnrichmentRequiresExplicitConfirmation() throws {
        let result = try runCLI(args: ["review", "enrich-batch", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect((dict["error"] as? String)?.contains("--confirm") == true)
    }

    @Test("legacy bookmark batch enrichment is removed")
    func legacyBookmarkBatchEnrichmentIsRemoved() throws {
        let result = try runCLI(args: ["bookmark", "enrich", "--all", "--json"])

        let dict = try parseJSONObject(result.stdout)
        #expect(dict["ok"] as? Bool == false)
        #expect(dict["legacyRemoved"] as? Bool == true)
        #expect((dict["command"] as? String) == "bookmark enrich --all")
        #expect((dict["replacement"] as? String)?.contains("review enrich-batch") == true)
    }

    @Test("legacy CLI commands are removed with replacements")
    func legacyCLICommandsAreRemovedWithReplacements() throws {
        let commands = [
            ["memory", "show", "user", "--json"],
            ["embeddings", "backfill", "--json"],
            ["search", "anything", "--json"],
            ["query", "anything", "--json"],
            ["recent", "--json"],
            ["snapshot", "--json"],
            ["status", "--json"],
            ["folder", "kanban", "Inbox", "--json"],
        ]

        for command in commands {
            let result = try runCLI(args: command)
            let dict = try parseJSONObject(result.stdout)
            #expect(dict["ok"] as? Bool == false)
            #expect(dict["legacyRemoved"] as? Bool == true)
            #expect((dict["replacement"] as? String)?.isEmpty == false)
        }
    }

    @Test("top level help hides removed legacy commands")
    func topLevelHelpHidesRemovedLegacyCommands() throws {
        let result = try runCLI(args: ["help"])
        let output = result.stdout

        #expect(output.contains("cider-cli capture add"))
        #expect(output.contains("cider-cli item search"))
        #expect(output.contains("cider-cli storage audit"))
        #expect(output.contains("cider-cli db integrity"))
        #expect(!output.contains("cider-cli memory"))
        #expect(!output.contains("cider-cli embeddings"))
        #expect(!output.contains("cider-cli query"))
        #expect(!output.contains("cider-cli search <query>"))
        #expect(!output.contains("cider-cli recent"))
        #expect(!output.contains("cider-cli snapshot"))
        #expect(!output.contains("cider-cli status"))
        #expect(!output.contains("cider-cli folder kanban"))
    }

    @Test("read-only folder filters do not adopt untracked disk folders")
    func readOnlyFolderFiltersDoNotAdoptUntrackedDiskFolders() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-read-filter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["folder", "create", "Tracked"], vault: vault)
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("LooseDiskFolder", isDirectory: true),
            withIntermediateDirectories: true
        )

        let listResult = try runCLI(args: ["bookmark", "list", "--folder", "LooseDiskFolder", "--json"], vault: vault)
        #expect(listResult.status == 0)

        let folders = try runCLI(args: ["folder", "list", "--json"], vault: vault)
        let folderPayload = try parseJSONArray(folders.stdout)
        #expect(folderPayload.compactMap { $0["relativePath"] as? String }.contains("LooseDiskFolder") == false)
    }

    @Test("item mutations fail closed when canonical database cannot open")
    func itemMutationsFailClosedWhenCanonicalDatabaseCannotOpen() throws {
        let fileVault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-file-vault-\(UUID().uuidString)")
        try "not a directory".write(to: fileVault, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileVault) }

        let commands = [
            ["bookmark", "add", "https://example.com/fail-closed", "--json"],
            ["note", "create", "Fail closed note", "--json"],
            ["todo", "create", "Fail closed todo", "--json"],
            ["contact", "create", "Fail Closed", "--json"],
            ["file", "add", "/tmp/missing.txt", "--json"],
            ["folder", "create", "FailClosed", "--json"]
        ]

        for command in commands {
            let result = try runCLI(args: command, vault: fileVault)
            let payload = try parseJSONObject(result.stdout)
            #expect(payload["ok"] as? Bool == false, "Expected \(command.joined(separator: " ")) to fail closed")
            #expect((payload["error"] as? String)?.contains("canonical SQLite database") == true)
        }
    }

    @Test("item move and unfile use confirmed second-brain mutation result shape")
    func itemMoveAndUnfileUseConfirmedMutationResultShape() throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-item-mutation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try runCLI(args: ["folder", "create", "Projects"], vault: vault)
        let noteResult = try runCLI(args: ["note", "create", "Move via item door", "--json"], vault: vault)
        let note = try parseJSONObject(noteResult.stdout)
        let noteID = try #require(note["id"] as? String)

        let moveResult = try runCLI(args: ["item", "move", "note", noteID, "--folder", "Projects", "--json"], vault: vault)
        let move = try parseJSONObject(moveResult.stdout)
        #expect(move["ok"] as? Bool == true)
        #expect(move["command"] as? String == "item.move")
        #expect(move["mutationAuditEntryID"] as? String != nil)
        #expect(move["routingDecisionID"] as? String != nil)
        #expect(move["agentActionID"] as? String != nil)
        let movedAfter = try #require(move["after"] as? [String: Any])
        #expect(movedAfter["folderID"] as? String != nil)

        let unfileResult = try runCLI(args: ["item", "unfile", "note", noteID, "--json"], vault: vault)
        let unfile = try parseJSONObject(unfileResult.stdout)
        #expect(unfile["ok"] as? Bool == true)
        #expect(unfile["command"] as? String == "item.unfile")
        #expect(unfile["mutationAuditEntryID"] as? String != nil)
        #expect(unfile["routingDecisionID"] as? String != nil)
        #expect(unfile["agentActionID"] as? String != nil)
        let unfiledAfter = try #require(unfile["after"] as? [String: Any])
        #expect(unfiledAfter["folderID"] == nil)
    }

    @Test("reminder mutation ID resolution rejects ambiguous prefixes")
    func reminderMutationIDResolutionRejectsAmbiguousPrefixes() throws {
        let first = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
        let second = UUID(uuidString: "aaaaaaaa-2222-2222-2222-222222222222")!

        let result = CiderCLI.resolveUniqueReminderID(
            prefix: "aaaaaaaa",
            candidates: [
                CiderCLI.CiderReminderIDCandidate(id: first, title: "First"),
                CiderCLI.CiderReminderIDCandidate(id: second, title: "Second"),
            ]
        )

        guard case .ambiguous(let matches) = result else {
            Issue.record("Expected ambiguous result, got \(result)")
            return
        }
        #expect(matches.map(\.id) == [first, second])
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }

    private func parseJSONArray(_ output: String) throws -> [[String: Any]] {
        let data = Data(output.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [[String: Any]])
    }

    private func runCLI(args: [String]) throws -> (stdout: String, stderr: String, status: Int32) {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-cli-agent-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }

        return try runCLI(args: args, vault: vault)
    }

    private func runCLI(args: [String], vault: URL) throws -> (stdout: String, stderr: String, status: Int32) {
        let cli = try cliURL()
        let process = Process()
        process.executableURL = cli
        process.arguments = ["--vault", vault.path] + args

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
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
}
