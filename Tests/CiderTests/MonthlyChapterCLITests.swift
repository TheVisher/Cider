import Foundation
import Testing
@testable import Cider

@Suite("Monthly Chapter CLI Tests", .serialized)
@MainActor
struct MonthlyChapterCLITests {
    @Test("monthly chapter preview composes weekly previews with provenance and diagnostics")
    func monthlyChapterPreviewComposesWeeklyPreviewsWithProvenanceAndDiagnostics() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let first = try captureJournal(
            date: "2026-06-02",
            time: "08:10",
            text: "I watched Silo.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-06-09",
            time: "20:00",
            text: "We watched Silo again.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-06-18",
            time: "12:15",
            text: "We went to Cactus for lunch.",
            vault: vault
        )

        let firstItem = try #require(first["item"] as? [String: Any])
        let firstNoteID = try #require(firstItem["id"] as? String)

        let preview = try assertJSON(
            runCLI(args: ["item", "monthly-chapter", "--month", "2026-06", "--json"], vault: vault),
            command: "item.monthly-chapter"
        )

        #expect(preview["ok"] as? Bool == true)
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["month"] as? String == "2026-06")
        #expect(preview["monthStart"] as? String == "2026-06-01")
        #expect(preview["monthEnd"] as? String == "2026-06-30")
        #expect(preview["title"] as? String == "Monthly Chapter 2026-06")
        #expect(preview["exists"] as? Bool == true)

        let trust = try #require(preview["trustBoundary"] as? [String: Any])
        #expect(trust["status"] as? String == "reviewable_monthly_read_model")
        #expect(trust["generatedTruth"] as? Bool == false)
        #expect(trust["sourceMutation"] as? Bool == false)
        #expect(trust["autoPromotesCandidates"] as? Bool == false)

        let weeks = try #require(preview["weeks"] as? [[String: Any]])
        #expect(weeks.map { $0["weekStart"] as? String } == [
            "2026-06-01",
            "2026-06-08",
            "2026-06-15",
            "2026-06-22",
            "2026-06-29",
        ])
        #expect(weeks[0]["daysInMonthWithSources"] as? Int == 1)
        #expect(weeks[1]["daysInMonthWithSources"] as? Int == 1)

        let sourceRefs = try #require(preview["sourceItemRefs"] as? [[String: Any]])
        #expect(sourceRefs.contains { $0["ref"] as? String == "note:\(firstNoteID)" })

        let recurring = try #require(preview["recurringSignals"] as? [[String: Any]])
        let silo = try #require(recurring.first { ($0["mentionText"] as? String)?.localizedCaseInsensitiveContains("Silo") == true })
        #expect(silo["count"] as? Int == 2)
        #expect(silo["truthBoundary"] as? String == "reviewable_candidate_not_truth")
        #expect(try #require(silo["sourceRefs"] as? [String]).count == 2)

        let diagnostic = try #require(preview["candidateCoverageDiagnostic"] as? [String: Any])
        #expect(diagnostic["truthBoundary"] as? String == "candidate_coverage_not_truth")
        #expect(diagnostic["whyRecurringSignals"] as? String == "repeated_reviewable_candidates_found")
        let counts = try #require(diagnostic["counts"] as? [String: Any])
        #expect(counts["sourceItemCount"] as? Int == 3)
        #expect(counts["daysWithSources"] as? Int == 3)
        #expect(counts["graphCandidateOutputCount"] as? Int == 3)
        #expect(counts["reviewableCandidateOutputCount"] as? Int == 3)
        #expect(counts["repeatedReviewableGroupCount"] as? Int == 1)
        #expect(counts["singletonReviewableGroupCount"] as? Int == 1)

        let byWeek = try #require(diagnostic["byWeek"] as? [[String: Any]])
        #expect(byWeek.count == 5)
        #expect(byWeek.contains { $0["weekStart"] as? String == "2026-06-01" && $0["sourceItemCount"] as? Int == 1 })

        let safeCommands = try #require(preview["safeNextCommands"] as? [String])
        #expect(safeCommands.first == "cider-cli item monthly-chapter --month 2026-06 --json")
        #expect(safeCommands.contains("cider-cli item weekly-chapter --week 2026-06-01 --json"))
        #expect(safeCommands.contains("cider-cli item graph-candidates note \(firstNoteID) --json"))
        #expect(safeCommands.contains("cider-cli capture review-queue --kind graph_candidate --json"))
    }

    @Test("monthly chapter preview for empty month is read only and explains why empty")
    func monthlyChapterPreviewEmptyMonthIsReadOnlyAndExplainsWhyEmpty() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let preview = try assertJSON(
            runCLI(args: ["item", "monthly-chapter", "--month", "2026-08", "--json"], vault: vault),
            command: "item.monthly-chapter"
        )
        let after = try tableCounts(in: vault)

        #expect(after == before)
        #expect(preview["readOnly"] as? Bool == true)
        #expect(preview["changed"] as? Bool == false)
        #expect(preview["exists"] as? Bool == false)
        #expect(preview["explanation"] as? String == "No daily journal notes or recurring candidate themes were found for 2026-08.")

        let diagnostic = try #require(preview["candidateCoverageDiagnostic"] as? [String: Any])
        #expect(diagnostic["whyRecurringSignals"] as? String == "no_source_items")
        #expect(diagnostic["explanation"] as? String == "No source items were found for this month, so Cider did not find graph candidate outputs to group.")
        let counts = try #require(diagnostic["counts"] as? [String: Any])
        #expect(counts["sourceItemCount"] as? Int == 0)
        #expect(counts["graphCandidateOutputCount"] as? Int == 0)
        #expect(counts["repeatedReviewableGroupCount"] as? Int == 0)

        let weeks = try #require(preview["weeks"] as? [[String: Any]])
        #expect(weeks.count == 6)
        #expect(weeks.allSatisfy { $0["exists"] as? Bool == false })
    }

    @Test("natural monthly life recall query redirects to monthly chapter preview")
    func naturalMonthlyLifeRecallQueryRedirectsToMonthlyChapterPreview() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let result = try assertJSON(
            runCLI(args: ["query", "what was happening in my life last month", "--json"], vault: vault),
            command: "query.monthly-chapter"
        )
        let after = try tableCounts(in: vault)

        let expectedMonth = monthForLastMonth()
        #expect(after == before)
        #expect(result["ok"] as? Bool == true)
        #expect(result["readOnly"] as? Bool == true)
        #expect(result["changed"] as? Bool == false)
        #expect(result["intent"] as? String == "monthly_life_recap")
        #expect(result["query"] as? String == "what was happening in my life last month")
        #expect(result["month"] as? String == expectedMonth)
        #expect(result["safeCommand"] as? String == "cider-cli item monthly-chapter --month \(expectedMonth) --json")

        let safeCommands = try #require(result["safeNextCommands"] as? [String])
        #expect(safeCommands.first == "cider-cli item monthly-chapter --month \(expectedMonth) --json")

        let trust = try #require(result["trustBoundary"] as? [String: Any])
        #expect(trust["status"] as? String == "monthly_chapter_query_interpretation")
        #expect(trust["generatedTruth"] as? Bool == false)
        #expect(trust["sourceMutation"] as? Bool == false)
        #expect(trust["autoPromotesCandidates"] as? Bool == false)

        let monthlyChapter = try #require(result["monthlyChapter"] as? [String: Any])
        #expect(monthlyChapter["command"] as? String == "item.monthly-chapter")
        #expect(monthlyChapter["readOnly"] as? Bool == true)
        #expect(monthlyChapter["changed"] as? Bool == false)
        #expect(monthlyChapter["month"] as? String == expectedMonth)
        #expect(monthlyChapter["candidateCoverageDiagnostic"] is [String: Any])
    }

    @Test("non month recap query keeps existing query behavior")
    func nonMonthRecapQueryKeepsExistingQueryBehavior() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let output = try runCLI(args: ["query", "restaurants I saved last month", "--json"], vault: vault)
        let after = try tableCounts(in: vault)
        let payload = try parseJSONObject(output.stdout)

        #expect(output.status != 0)
        #expect(after == before)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["legacyRemoved"] as? Bool == true)
        #expect(payload["replacement"] as? String == "Use cider-cli item search <query> --json.")
    }

    @Test("monthly chapter help is discoverable and side effect free")
    func monthlyChapterHelpIsDiscoverableAndSideEffectFree() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let help = try runCLI(args: ["item", "monthly-chapter", "--help"], vault: vault)
        let itemHelp = try runCLI(args: ["item", "--help"], vault: vault)
        let after = try tableCounts(in: vault)

        #expect(help.status == 0)
        #expect(help.stdout.contains("cider-cli item monthly-chapter --month YYYY-MM [--json]"))
        #expect(itemHelp.stdout.contains("cider-cli item monthly-chapter --month YYYY-MM [--json]"))
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
            .appendingPathComponent("cider-monthly-chapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func monthForLastMonth(referenceDate: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let startOfThisMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: referenceDate)
        ) ?? referenceDate
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: startOfThisMonth) ?? startOfThisMonth
        return Self.monthFormatter.string(from: lastMonth)
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

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
}
