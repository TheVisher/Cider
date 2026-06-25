import Foundation
import Testing
@testable import Cider

@Suite("Daily Episode CLI Tests", .serialized)
@MainActor
struct DailyEpisodeCLITests {
    @Test("daily episode preview returns journal slices in chronological order with provenance")
    func dailyEpisodePreviewReturnsChronologicalJournalSlicesWithProvenance() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let first = try captureJournal(
            date: "2026-06-25",
            time: "08:05",
            text: "Morning plan: ship the daily episode read model.",
            vault: vault
        )
        let voice = try captureJournal(
            date: "2026-06-25",
            time: "14:48",
            text: "Drive-home voice note: the day should read like one running episode.",
            vault: vault,
            extraArgs: [
                "--surface", "voice",
                "--channel", "driving-reflection",
                "--message-id", "voice-2026-06-25-1448",
                "--source-meta", "input=voice-derived",
            ]
        )
        _ = try captureJournal(
            date: "2026-06-25",
            time: "21:10",
            text: "Evening wrap: keep generated truth out of user-owned notes.",
            vault: vault
        )

        let firstItem = try #require(first["item"] as? [String: Any])
        let noteID = try #require(firstItem["id"] as? String)
        let voiceProvenance = try #require(voice["provenance"] as? [String: Any])
        let voiceCaptureID = try #require(voiceProvenance["captureEventID"] as? String)

        let preview = try assertJSON(
            runCLI(args: ["item", "daily-episode", "--date", "2026-06-25", "--json"], vault: vault),
            command: "item.daily-episode"
        )

        #expect(preview["ok"] as? Bool == true)
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["date"] as? String == "2026-06-25")
        #expect(preview["title"] as? String == "Daily Episode 2026-06-25")
        #expect(preview["exists"] as? Bool == true)

        let trust = try #require(preview["trustBoundary"] as? [String: Any])
        #expect(trust["status"] as? String == "preview_read_model")
        #expect(trust["generatedTruth"] as? Bool == false)
        #expect(trust["sourcePreserved"] as? Bool == true)

        let journal = try #require(preview["dailyJournal"] as? [String: Any])
        #expect(journal["id"] as? String == noteID)
        #expect(journal["type"] as? String == "note")

        let sourceRefs = try #require(preview["sourceItemRefs"] as? [[String: Any]])
        #expect(sourceRefs.contains { $0["ref"] as? String == "note:\(noteID)" })

        let entries = try #require(preview["entries"] as? [[String: Any]])
        #expect(entries.count == 3)
        #expect(entries.map { $0["time"] as? String } == ["08:05", "14:48", "21:10"])
        #expect(entries[1]["snippet"] as? String == "Drive-home voice note: the day should read like one running episode.")
        #expect(entries[1]["sourceItemRef"] as? String == "note:\(noteID)")

        let provenanceRefs = try #require(entries[1]["provenanceRefs"] as? [[String: Any]])
        #expect(provenanceRefs.contains { ref in
            ref["ref"] as? String == "capture_event:\(voiceCaptureID)"
                && ref["sourceKind"] as? String == "journal"
                && ref["surface"] as? String == "voice"
                && ref["messageID"] as? String == "voice-2026-06-25-1448"
        })

        let safeCommands = try #require(preview["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item get note \(noteID) --json"))
        #expect(safeCommands.contains("cider-cli item context note \(noteID) --json"))
        #expect(safeCommands.contains("cider-cli item search \"2026-06-25\" --scope personalMemory --json"))
    }

    @Test("daily episode preview for missing date is read only and explains next safe commands")
    func dailyEpisodePreviewMissingDateIsReadOnly() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try itemRowCount(in: vault)
        let preview = try assertJSON(
            runCLI(args: ["item", "daily-episode", "--date", "2026-06-24", "--json"], vault: vault),
            command: "item.daily-episode"
        )
        let after = try itemRowCount(in: vault)

        #expect(after == before)
        #expect(preview["ok"] as? Bool == true)
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["exists"] as? Bool == false)
        #expect(preview["date"] as? String == "2026-06-24")
        #expect(preview["explanation"] as? String == "No daily journal note was found for 2026-06-24.")

        let entries = try #require(preview["entries"] as? [[String: Any]])
        #expect(entries.isEmpty)

        let safeCommands = try #require(preview["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item search \"2026-06-24\" --scope personalMemory --json"))
        #expect(safeCommands.contains("cider-cli capture add --kind journal --date 2026-06-24 --stdin --json"))
    }

    private func captureJournal(
        date: String,
        time: String,
        text: String,
        vault: URL,
        extraArgs: [String] = []
    ) throws -> [String: Any] {
        try assertJSON(
            runCLI(
                args: [
                    "capture", "add",
                    "--kind", "journal",
                    "--date", date,
                    "--time", time,
                    "--stdin",
                    "--json",
                ] + extraArgs,
                vault: vault,
                stdin: text
            ),
            command: "capture.add"
        )
    }

    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-daily-episode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func itemRowCount(in vault: URL) throws -> Int {
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return 0 }
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }
        let stmt = try db.prepare("SELECT COUNT(*) FROM items;")
        _ = try stmt.step()
        return stmt.int(at: 0)
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
        return payload
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        let data = Data(json.utf8)
        let object = try JSONSerialization.jsonObject(with: data)
        return try #require(object as? [String: Any])
    }
}
