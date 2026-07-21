import Foundation
import Testing
@testable import CiderCLI

@Suite("Board CLI process contracts", .serialized)
struct BoardCLIProcessTests {
    @Test("nested board help exits zero without bootstrapping the vault")
    func nestedBoardHelpIsEarlyAndReadOnly() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try runCLI(args: ["board", "comment", "add", "--help"] , vault: vault)

        #expect(result.reason == .exit)
        #expect(result.status == 0)
        #expect(result.stdout.contains("cider-cli board comment add"))
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent(".cider/cider.db").path))
    }

    @Test("large-board query emits bounded valid JSON")
    func largeBoardQueryIsBounded() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try writeLargeBoardFixture(in: vault, cardCount: 1_000)

        let result = try runCLI(args: ["board", "show", "fixture", "--query", "needle", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.reason == .exit)
        #expect(result.status == 0)
        #expect(result.stdout.utf8.count < 64_000)
        #expect(payload["command"] as? String == "board.show")
        let detail = try #require(payload["boardDetail"] as? [String: Any])
        let columns = try #require(detail["columns"] as? [[String: Any]])
        let cards = columns.flatMap { ($0["cards"] as? [[String: Any]]) ?? [] }
        #expect(cards.count == 1)
        #expect(cards.first?["id"] as? String == "needle")
    }

    @Test("board write receipt survives follow-up inspection")
    func boardWriteReceiptIsStable() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try writeLargeBoardFixture(in: vault, cardCount: 1)

        let add = try runCLI(
            args: ["board", "add-card", "fixture", "--column", "Backlog", "--title", "Receipt probe", "--json"],
            vault: vault
        )
        let receipt = try parseJSONObject(add.stdout)
        #expect(add.reason == .exit)
        #expect(add.status == 0)
        #expect(receipt["ok"] as? Bool == true)
        #expect(receipt["changed"] as? Bool == true)
        let card = try #require(receipt["card"] as? [String: Any])
        let cardID = try #require(card["id"] as? String)

        let inspect = try runCLI(
            args: ["board", "card", "inspect", "fixture", "--card", cardID, "--json"],
            vault: vault
        )
        let inspected = try parseJSONObject(inspect.stdout)
        #expect(inspect.reason == .exit)
        #expect(inspect.status == 0)
        #expect(inspected["command"] as? String == "board.card.inspect")
        #expect((inspected["card"] as? [String: Any])?["id"] as? String == cardID)
    }

    @Test("missing board is a truthful ordinary process failure")
    func missingBoardDoesNotCrash() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try writeLargeBoardFixture(in: vault, cardCount: 1)

        let result = try runCLI(args: ["board", "show", "missing", "--json"], vault: vault)
        let payload = try parseJSONObject(result.stdout)

        #expect(result.reason == .exit)
        #expect(result.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["command"] as? String == "board.show")
    }

    @Test("canonical Kanban item get uses the bounded board read path")
    func canonicalKanbanItemGetIsBounded() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try writeLargeBoardFixture(in: vault, cardCount: 1)

        let result = try runCLI(
            args: ["item", "get", "kanban_card", "fixture/needle", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)

        #expect(result.reason == .exit)
        #expect(result.status == 0)
        #expect(payload["ok"] as? Bool == true)
        #expect(payload["exists"] as? Bool == true)
        #expect((payload["owner"] as? [String: Any])?["ref"] as? String == "kanban_card:fixture/needle")
    }

    @Test("comment attachment write returns a stable mutation receipt")
    func commentAttachmentWriteReturnsStableReceipt() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        try writeLargeBoardFixture(in: vault, cardCount: 1)
        let evidence = vault.appendingPathComponent("evidence.txt")
        try "synthetic evidence".write(to: evidence, atomically: true, encoding: .utf8)

        let add = try runCLI(
            args: [
                "board", "comment", "add", "fixture",
                "--card", "needle",
                "--kind", "evidence",
                "--text", "Synthetic attachment receipt",
                "--attachment-type", "evidence",
                "--attachment-title", "Synthetic evidence",
                "--attachment-file", evidence.path,
                "--json",
            ],
            vault: vault
        )
        let receipt = try parseJSONObject(add.stdout)
        #expect(add.reason == .exit)
        #expect(add.status == 0)
        #expect(receipt["command"] as? String == "board.comment.add")
        #expect(receipt["readOnly"] as? Bool == false)
        #expect(receipt["changed"] as? Bool == true)
        let comment = try #require(receipt["comment"] as? [String: Any])
        let commentID = try #require(comment["id"] as? String)
        #expect(!(comment["attachments"] as? [[String: Any]] ?? []).isEmpty)

        let list = try runCLI(
            args: ["board", "comment", "list", "fixture", "--card", "needle", "--limit", "1", "--json"],
            vault: vault
        )
        let listed = try parseJSONObject(list.stdout)
        #expect(list.reason == .exit)
        #expect(list.status == 0)
        let comments = try #require(listed["comments"] as? [[String: Any]])
        #expect(comments.first?["id"] as? String == commentID)
    }

    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-board-cli-process-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func writeLargeBoardFixture(in vault: URL, cardCount: Int) throws {
        let boards = vault.appendingPathComponent(".cider/boards", isDirectory: true)
        try FileManager.default.createDirectory(at: boards, withIntermediateDirectories: true)
        var yaml = """
        id: fixture
        board: Fixture Board
        created: '2026-07-20'
        columns:
        - id: backlog
          name: Backlog
          cards:
        """
        for index in 0..<cardCount {
            let id = index == cardCount - 1 ? "needle" : String(format: "%06x", index)
            let title = index == cardCount - 1 ? "Unique needle" : "Synthetic card \(index)"
            yaml += """

              - id: \(id)
                title: \(title)
                created: '2026-07-20'
            """
        }
        yaml += """

          is_done_column: false
        - id: done
          name: Done
          cards: []
          is_done_column: true
        """
        try yaml.write(to: boards.appendingPathComponent("fixture.yaml"), atomically: true, encoding: .utf8)
    }

    private func runCLI(
        args: [String],
        vault: URL
    ) throws -> (stdout: String, stderr: String, status: Int32, reason: Process.TerminationReason) {
        let process = Process()
        process.executableURL = try cliURL()
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
            process.terminationStatus,
            process.terminationReason
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

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }
}
