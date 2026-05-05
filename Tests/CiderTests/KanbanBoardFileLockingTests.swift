import Foundation
import Testing
@testable import Cider

struct KanbanBoardFileLockingTests {
    @Test("stale whole-card updates merge changed fields")
    @MainActor
    func staleWholeCardUpdatesMergeChangedFields() throws {
        let vault = try Self.makeTemporaryVault()
        defer {
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let storage = KanbanStorage()
        let board = storage.createBoard(name: "Merge Smoke")
        let card = try #require(storage.addCard(boardID: board.id, columnID: "backlog", title: "Race card"))
        let secondWriterStorage = KanbanStorage()

        var notesEdit = card
        notesEdit.notes = "Notes from first writer"
        var priorityEdit = card
        priorityEdit.priority = .high

        storage.updateCard(boardID: board.id, card: notesEdit)
        secondWriterStorage.updateCard(boardID: board.id, card: priorityEdit)

        let refreshedStorage = KanbanStorage()
        let refreshed = try #require(refreshedStorage.findCard(id: card.id)?.card)
        #expect(refreshed.notes == "Notes from first writer")
        #expect(refreshed.priority == .high)
    }

    @Test("parallel CLI add-card operations preserve every card")
    func parallelCLIAddCardOperationsPreserveEveryCard() throws {
        let cli = try #require(Self.ciderCLIURL())
        let vault = try Self.makeTemporaryVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        try Self.runCLI(cli, vault: vault, args: ["board", "create", "Locking Smoke"])

        let cardCount = 12
        let processes = try (0..<cardCount).map { index in
            try Self.startCLI(
                cli,
                vault: vault,
                args: [
                    "board", "add-card", "Locking Smoke",
                    "--column", "Backlog",
                    "--title", "Concurrent card \(index)",
                ]
            )
        }

        for process in processes {
            process.process.waitUntilExit()
            #expect(process.process.terminationStatus == 0)
            _ = String(data: process.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            _ = String(data: process.error.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        }

        let jsonData = try Self.runCLIData(cli, vault: vault, args: ["board", "show", "Locking Smoke", "--json"])
        let root = try #require(try JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        let columns = try #require(root["columns"] as? [[String: Any]])
        let backlog = try #require(columns.first { ($0["id"] as? String) == "backlog" })
        let cards = try #require(backlog["cards"] as? [[String: Any]])
        let titles = Set(cards.compactMap { $0["title"] as? String })

        #expect(titles.count == cardCount)
        for index in 0..<cardCount {
            #expect(titles.contains("Concurrent card \(index)"))
        }
    }

    private static func ciderCLIURL() -> URL? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func makeTemporaryVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-kanban-locking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    @discardableResult
    private static func runCLI(_ cli: URL, vault: URL, args: [String]) throws -> String {
        let data = try runCLIData(cli, vault: vault, args: args)
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runCLIData(_ cli: URL, vault: URL, args: [String]) throws -> Data {
        let process = try startCLI(cli, vault: vault, args: args)
        process.process.waitUntilExit()
        let output = process.output.fileHandleForReading.readDataToEndOfFile()
        let error = process.error.fileHandleForReading.readDataToEndOfFile()
        if process.process.terminationStatus != 0 {
            let stderr = String(data: error, encoding: .utf8) ?? ""
            Issue.record("cider-cli failed with status \(process.process.terminationStatus): \(stderr)")
        }
        #expect(process.process.terminationStatus == 0)
        return output
    }

    private static func startCLI(
        _ cli: URL,
        vault: URL,
        args: [String]
    ) throws -> (process: Process, output: Pipe, error: Pipe) {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = cli
        process.arguments = ["--vault", vault.path] + args
        process.standardOutput = output
        process.standardError = error
        try process.run()
        return (process, output, error)
    }
}
