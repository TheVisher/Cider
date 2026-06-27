import Foundation
import Testing
@testable import Cider

@Suite("Weekly Chapter CLI Tests", .serialized)
@MainActor
struct WeeklyChapterCLITests {
    @Test("weekly chapter preview aggregates daily episodes and repeated reviewable themes with provenance")
    func weeklyChapterPreviewAggregatesEpisodesAndRecurringThemes() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let monday = try captureJournal(
            date: "2026-06-22",
            time: "08:10",
            text: "I watched Silo.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-06-23",
            time: "19:45",
            text: "We watched Silo again.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-06-24",
            time: "12:00",
            text: "We went to Cactus and got lunch.",
            vault: vault
        )

        let mondayItem = try #require(monday["item"] as? [String: Any])
        let mondayNoteID = try #require(mondayItem["id"] as? String)

        let preview = try assertJSON(
            runCLI(args: ["item", "weekly-chapter", "--week", "2026-06-22", "--json"], vault: vault),
            command: "item.weekly-chapter"
        )

        #expect(preview["ok"] as? Bool == true)
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["weekStart"] as? String == "2026-06-22")
        #expect(preview["weekEnd"] as? String == "2026-06-28")
        #expect(preview["title"] as? String == "Weekly Chapter 2026-06-22 to 2026-06-28")

        let trust = try #require(preview["trustBoundary"] as? [String: Any])
        #expect(trust["status"] as? String == "reviewable_weekly_read_model")
        #expect(trust["generatedTruth"] as? Bool == false)
        #expect(trust["autoPromotesCandidates"] as? Bool == false)

        let days = try #require(preview["dailyEpisodes"] as? [[String: Any]])
        #expect(days.count == 7)
        #expect(days[0]["date"] as? String == "2026-06-22")
        #expect(days[0]["exists"] as? Bool == true)
        #expect(days[6]["date"] as? String == "2026-06-28")
        #expect(days[6]["exists"] as? Bool == false)

        let sourceRefs = try #require(preview["sourceItemRefs"] as? [[String: Any]])
        #expect(sourceRefs.contains { $0["ref"] as? String == "note:\(mondayNoteID)" })

        let recurring = try #require(preview["recurringSignals"] as? [[String: Any]])
        let silo = try #require(recurring.first { ($0["mentionText"] as? String)?.localizedCaseInsensitiveContains("Silo") == true })
        #expect(silo["count"] as? Int == 2)
        #expect(silo["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(silo["reviewState"] as? String == "suggested")

        let candidateRefs = try #require(silo["candidateRefs"] as? [String])
        #expect(candidateRefs.count == 2)
        #expect(candidateRefs.allSatisfy { $0.hasPrefix("graph_candidate:") })

        let signalSources = try #require(silo["sourceRefs"] as? [String])
        #expect(signalSources.count == 2)
        #expect(signalSources.allSatisfy { $0.hasPrefix("note:") })

        let examples = try #require(silo["examples"] as? [[String: Any]])
        #expect(examples.count == 2)
        #expect(examples.allSatisfy { ($0["sourceQuote"] as? String)?.localizedCaseInsensitiveContains("Silo") == true })

        let safeCommands = try #require(preview["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item daily-episode --date 2026-06-22 --json"))
        #expect(safeCommands.contains("cider-cli item graph-candidates note \(mondayNoteID) --json"))
        #expect(safeCommands.contains("cider-cli capture review-queue --kind graph_candidate --json"))
    }

    @Test("weekly chapter preview for empty week is read only and does not mutate")
    func weeklyChapterPreviewEmptyWeekIsReadOnlyAndDoesNotMutate() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let preview = try assertJSON(
            runCLI(args: ["item", "weekly-chapter", "--week", "2026-07-06", "--json"], vault: vault),
            command: "item.weekly-chapter"
        )
        let after = try tableCounts(in: vault)

        #expect(after == before)
        #expect(preview["ok"] as? Bool == true)
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["exists"] as? Bool == false)
        #expect(preview["explanation"] as? String == "No daily journal notes or recurring candidate themes were found for 2026-07-06 to 2026-07-12.")

        let days = try #require(preview["dailyEpisodes"] as? [[String: Any]])
        #expect(days.count == 7)
        #expect(days.allSatisfy { $0["exists"] as? Bool == false })

        let recurring = try #require(preview["recurringSignals"] as? [[String: Any]])
        #expect(recurring.isEmpty)

        let safeCommands = try #require(preview["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item search \"2026-07-06\" --scope personalMemory --json"))
        #expect(safeCommands.contains("cider-cli item daily-episode --date 2026-07-06 --json"))
    }

    @Test("weekly chapter help is discoverable and side effect free")
    func weeklyChapterHelpIsDiscoverableAndSideEffectFree() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let help = try runCLI(args: ["item", "weekly-chapter", "--help"], vault: vault)
        let after = try tableCounts(in: vault)

        #expect(help.status == 0)
        #expect(help.stdout.contains("cider-cli item weekly-chapter --week YYYY-MM-DD [--json]"))
        #expect(after == before)
    }

    private func captureJournal(
        date: String,
        time: String,
        text: String,
        vault: URL
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
                ],
                vault: vault,
                stdin: text
            ),
            command: "capture.add"
        )
    }

    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-weekly-chapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func tableCounts(in vault: URL) throws -> [String: Int] {
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".cider", isDirectory: true),
            withIntermediateDirectories: true
        )
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        let db = CiderDatabase()
        try db.open(at: dbURL)
        defer { db.close() }
        var counts: [String: Int] = [:]
        for table in ["items", "notes", "enrichment_outputs", "capture_events", "owner_relations"] {
            let stmt = try db.prepare("SELECT COUNT(*) FROM \(table);")
            _ = try stmt.step()
            counts[table] = stmt.int(at: 0)
        }
        return counts
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
