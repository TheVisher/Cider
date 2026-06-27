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

        let diagnostic = try #require(preview["candidateCoverageDiagnostic"] as? [String: Any])
        #expect(diagnostic["truthBoundary"] as? String == "candidate_coverage_not_truth")
        #expect(diagnostic["whyRecurringSignals"] as? String == "repeated_reviewable_candidates_found")
        #expect(diagnostic["reviewableRepeatThreshold"] as? Int == 2)
        let counts = try #require(diagnostic["counts"] as? [String: Any])
        #expect(counts["sourceItemCount"] as? Int == 3)
        #expect(counts["graphCandidateOutputCount"] as? Int == 3)
        #expect(counts["reviewableCandidateOutputCount"] as? Int == 3)
        #expect(counts["repeatedReviewableGroupCount"] as? Int == 1)
        #expect(counts["singletonReviewableGroupCount"] as? Int == 1)
        #expect(counts["filteredAcceptedCount"] as? Int == 0)
        #expect(counts["filteredRejectedCount"] as? Int == 0)
        #expect(counts["malformedCandidatePayloadCount"] as? Int == 0)

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

        let diagnosticSafeCommands = try #require(diagnostic["safeNextCommands"] as? [String])
        #expect(diagnosticSafeCommands.contains("cider-cli item graph-candidates note \(mondayNoteID) --json"))
        #expect(diagnosticSafeCommands.contains("cider-cli capture review-queue --kind graph_candidate --json"))
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

        let diagnostic = try #require(preview["candidateCoverageDiagnostic"] as? [String: Any])
        #expect(diagnostic["truthBoundary"] as? String == "candidate_coverage_not_truth")
        #expect(diagnostic["whyRecurringSignals"] as? String == "no_source_items")
        #expect(diagnostic["explanation"] as? String == "No source items were found for this week, so Cider did not find graph candidate outputs to group.")
        let counts = try #require(diagnostic["counts"] as? [String: Any])
        #expect(counts["sourceItemCount"] as? Int == 0)
        #expect(counts["graphCandidateOutputCount"] as? Int == 0)
        #expect(counts["reviewableCandidateOutputCount"] as? Int == 0)
        #expect(counts["repeatedReviewableGroupCount"] as? Int == 0)

        let days = try #require(preview["dailyEpisodes"] as? [[String: Any]])
        #expect(days.count == 7)
        #expect(days.allSatisfy { $0["exists"] as? Bool == false })

        let recurring = try #require(preview["recurringSignals"] as? [[String: Any]])
        #expect(recurring.isEmpty)

        let safeCommands = try #require(preview["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item search \"2026-07-06\" --scope personalMemory --json"))
        #expect(safeCommands.contains("cider-cli item daily-episode --date 2026-07-06 --json"))
    }

    @Test("weekly chapter diagnostic explains source items with no graph candidates")
    func weeklyChapterDiagnosticExplainsSourcesWithNoCandidates() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let capture = try captureJournal(
            date: "2026-07-13",
            time: "08:10",
            text: "quiet notes without extractor-shaped phrases.",
            vault: vault
        )
        let item = try #require(capture["item"] as? [String: Any])
        let noteID = try #require(item["id"] as? String)

        let preview = try assertJSON(
            runCLI(args: ["item", "weekly-chapter", "--week", "2026-07-13", "--json"], vault: vault),
            command: "item.weekly-chapter"
        )

        let recurring = try #require(preview["recurringSignals"] as? [[String: Any]])
        #expect(recurring.isEmpty)

        let diagnostic = try #require(preview["candidateCoverageDiagnostic"] as? [String: Any])
        #expect(diagnostic["whyRecurringSignals"] as? String == "source_items_but_no_graph_candidates")
        #expect(diagnostic["explanation"] as? String == "Source items exist for this week, but no graph candidate enrichment outputs were found for those sources.")
        let counts = try #require(diagnostic["counts"] as? [String: Any])
        #expect(counts["sourceItemCount"] as? Int == 1)
        #expect(counts["graphCandidateOutputCount"] as? Int == 0)

        let byDay = try #require(diagnostic["byDay"] as? [[String: Any]])
        let monday = try #require(byDay.first { $0["date"] as? String == "2026-07-13" })
        #expect(monday["sourceItemCount"] as? Int == 1)
        #expect(monday["graphCandidateOutputCount"] as? Int == 0)

        let safeCommands = try #require(diagnostic["safeNextCommands"] as? [String])
        #expect(safeCommands.contains("cider-cli item context note \(noteID) --json"))
        #expect(safeCommands.contains("cider-cli item graph-candidates note \(noteID) --json"))
    }

    @Test("weekly chapter diagnostic explains singleton-only candidates and filtered states")
    func weeklyChapterDiagnosticExplainsSingletonOnlyCandidatesAndFilteredStates() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let capture = try captureJournal(
            date: "2026-07-20",
            time: "10:00",
            text: "I watched Silo.",
            vault: vault
        )
        let item = try #require(capture["item"] as? [String: Any])
        let noteID = try #require(item["id"] as? String)
        try recordGraphCandidate(
            ownerType: "note",
            ownerID: noteID,
            mention: "Cactus",
            quote: "We went to Cactus.",
            reviewState: .accepted,
            vault: vault
        )
        try recordGraphCandidate(
            ownerType: "note",
            ownerID: noteID,
            mention: "Rejected place",
            quote: "We did not go to Rejected place.",
            reviewState: .rejected,
            vault: vault
        )
        try recordMalformedGraphCandidate(
            ownerType: "note",
            ownerID: noteID,
            vault: vault
        )

        let preview = try assertJSON(
            runCLI(args: ["item", "weekly-chapter", "--week", "2026-07-20", "--json"], vault: vault),
            command: "item.weekly-chapter"
        )

        let recurring = try #require(preview["recurringSignals"] as? [[String: Any]])
        #expect(recurring.isEmpty)

        let diagnostic = try #require(preview["candidateCoverageDiagnostic"] as? [String: Any])
        #expect(diagnostic["whyRecurringSignals"] as? String == "singleton_only_reviewable_candidates")
        #expect(diagnostic["explanation"] as? String == "Reviewable graph candidates were found, but each candidate group appears only once in the week.")
        let counts = try #require(diagnostic["counts"] as? [String: Any])
        #expect(counts["sourceItemCount"] as? Int == 1)
        #expect(counts["graphCandidateOutputCount"] as? Int == 4)
        #expect(counts["reviewableCandidateOutputCount"] as? Int == 1)
        #expect(counts["singletonReviewableGroupCount"] as? Int == 1)
        #expect(counts["repeatedReviewableGroupCount"] as? Int == 0)
        #expect(counts["filteredAcceptedCount"] as? Int == 1)
        #expect(counts["filteredRejectedCount"] as? Int == 1)
        #expect(counts["malformedCandidatePayloadCount"] as? Int == 1)

        let singletonGroups = try #require(diagnostic["singletonReviewableGroups"] as? [[String: Any]])
        #expect(singletonGroups.contains { ($0["mentionText"] as? String)?.localizedCaseInsensitiveContains("Silo") == true })
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

    @Test("natural weekly life recall query redirects to weekly chapter preview")
    func naturalWeeklyLifeRecallQueryRedirectsToWeeklyChapterPreview() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let result = try assertJSON(
            runCLI(args: ["query", "what was happening in my life last week", "--json"], vault: vault),
            command: "query.weekly-chapter"
        )
        let after = try tableCounts(in: vault)

        let expectedWeekStart = weekStartForLastWeek()
        #expect(after == before)
        #expect(result["ok"] as? Bool == true)
        #expect(result["readOnly"] as? Bool == true)
        #expect(result["changed"] as? Bool == false)
        #expect(result["intent"] as? String == "weekly_life_recap")
        #expect(result["query"] as? String == "what was happening in my life last week")
        #expect(result["weekStart"] as? String == expectedWeekStart)
        #expect(result["safeCommand"] as? String == "cider-cli item weekly-chapter --week \(expectedWeekStart) --json")

        let safeCommands = try #require(result["safeNextCommands"] as? [String])
        #expect(safeCommands.first == "cider-cli item weekly-chapter --week \(expectedWeekStart) --json")

        let trust = try #require(result["trustBoundary"] as? [String: Any])
        #expect(trust["status"] as? String == "weekly_chapter_query_interpretation")
        #expect(trust["generatedTruth"] as? Bool == false)
        #expect(trust["sourceMutation"] as? Bool == false)
        #expect(trust["autoPromotesCandidates"] as? Bool == false)

        let weeklyChapter = try #require(result["weeklyChapter"] as? [String: Any])
        #expect(weeklyChapter["command"] as? String == "item.weekly-chapter")
        #expect(weeklyChapter["readOnly"] as? Bool == true)
        #expect(weeklyChapter["changed"] as? Bool == false)
        #expect(weeklyChapter["weekStart"] as? String == expectedWeekStart)
        #expect(weeklyChapter["candidateCoverageDiagnostic"] is [String: Any])
    }

    @Test("natural weekly life recall query accepts literal week date")
    func naturalWeeklyLifeRecallQueryAcceptsLiteralWeekDate() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try assertJSON(
            runCLI(args: ["query", "what happened in my life week of 2026-06-24", "--json"], vault: vault),
            command: "query.weekly-chapter"
        )

        #expect(result["weekStart"] as? String == "2026-06-22")
        #expect(result["safeCommand"] as? String == "cider-cli item weekly-chapter --week 2026-06-22 --json")
    }

    @Test("non recap query keeps existing query behavior")
    func nonRecapQueryKeepsExistingQueryBehavior() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let before = try tableCounts(in: vault)
        let output = try runCLI(args: ["query", "restaurants I saved last week", "--json"], vault: vault)
        let after = try tableCounts(in: vault)
        let payload = try parseJSONObject(output.stdout)

        #expect(output.status != 0)
        #expect(after == before)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["legacyRemoved"] as? Bool == true)
        #expect(payload["replacement"] as? String == "Use cider-cli item search <query> --json.")
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

    private func recordGraphCandidate(
        ownerType: String,
        ownerID: String,
        mention: String,
        quote: String,
        reviewState: SecondBrainGraphCandidateContract.ReviewState,
        vault: URL
    ) throws {
        let db = try openDatabase(in: vault)
        defer { db.close() }
        let owner = SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID)
        var output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: mention,
            sourceQuote: quote,
            objectTypeGuesses: [.place],
            relationGuesses: [.visited],
            reviewState: .suggested,
            source: "graph_candidate.weekly_chapter_test"
        )
        output.reviewState = reviewState.rawValue
        if reviewState == .accepted {
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerType] = "place"
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedTargetOwnerID] = UUID().uuidString
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.acceptedRelationType] = SecondBrainGraphCandidateContract.RelationType.visited.rawValue
        }
        try SecondBrainEnrichmentOutputService(database: db).record(output)
    }

    private func recordMalformedGraphCandidate(ownerType: String, ownerID: String, vault: URL) throws {
        let db = try openDatabase(in: vault)
        defer { db.close() }
        let output = SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID),
            kind: SecondBrainGraphCandidateContract.outputKind,
            value: "Malformed",
            normalizedValue: "malformed",
            label: "Malformed candidate",
            evidence: "",
            source: "graph_candidate.weekly_chapter_test",
            confidence: 0.5,
            reviewState: "suggested",
            metadata: [
                SecondBrainGraphCandidateContract.MetadataKey.candidateKind: "object",
            ]
        )
        try SecondBrainEnrichmentOutputService(database: db).record(output)
    }

    private func openDatabase(in vault: URL) throws -> CiderDatabase {
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent(".cider", isDirectory: true),
            withIntermediateDirectories: true
        )
        let db = CiderDatabase()
        try db.open(at: vault.appendingPathComponent(".cider/cider.db"))
        return db
    }

    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-weekly-chapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func weekStartForLastWeek(referenceDate: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        calendar.firstWeekday = 2
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let currentWeekStart = startOfWeek(containing: startOfToday, calendar: calendar)
        let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: currentWeekStart) ?? currentWeekStart
        return Self.weekFormatter.string(from: lastWeekStart)
    }

    private func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromWeekStart, to: calendar.startOfDay(for: date))
            ?? calendar.startOfDay(for: date)
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

    private static let weekFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
