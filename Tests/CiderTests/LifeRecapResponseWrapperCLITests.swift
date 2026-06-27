import Foundation
import Testing
@testable import Cider

@Suite("Life Recap Response Wrapper CLI Tests", .serialized)
@MainActor
struct LifeRecapResponseWrapperCLITests {
    @Test("weekly life recap query includes compact source-backed wrapper")
    func weeklyLifeRecapQueryIncludesCompactSourceBackedWrapper() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let first = try captureJournal(
            date: "2026-06-22",
            time: "08:10",
            text: "I watched Silo before work.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-06-23",
            time: "19:45",
            text: "We watched Silo again after dinner.",
            vault: vault
        )

        let item = try #require(first["item"] as? [String: Any])
        let noteID = try #require(item["id"] as? String)
        let secondPreview = try assertJSON(
            runCLI(args: ["item", "daily-episode", "--date", "2026-06-23", "--json"], vault: vault),
            command: "item.daily-episode"
        )
        let secondJournal = try #require(secondPreview["dailyJournal"] as? [String: Any])
        let secondNoteID = try #require(secondJournal["id"] as? String)
        try recordGraphCandidate(ownerType: "note", ownerID: noteID, mention: "Silo", quote: "I watched Silo before work.", vault: vault)
        try recordGraphCandidate(ownerType: "note", ownerID: secondNoteID, mention: "Silo", quote: "We watched Silo again after dinner.", vault: vault)

        let result = try assertJSON(
            runCLI(args: ["query", "what happened in my life week of 2026-06-24", "--json"], vault: vault),
            command: "query.weekly-chapter"
        )

        #expect(result["readOnly"] as? Bool == true)
        #expect(result["changed"] as? Bool == false)
        #expect(result["weeklyChapter"] is [String: Any])

        let recap = try #require(result["recap"] as? [String: Any])
        #expect(recap["periodLabel"] as? String == "Weekly Chapter 2026-06-22 to 2026-06-28")
        #expect((recap["answer"] as? String)?.contains("2026-06-22 to 2026-06-28") == true)
        #expect((recap["sourceCoverageSummary"] as? String)?.contains("2 source-backed day") == true)
        #expect(recap["safeCommand"] as? String == "cider-cli item weekly-chapter --week 2026-06-22 --json")

        let citations = try #require(recap["sourceCitations"] as? [[String: Any]])
        #expect(citations.contains { $0["ref"] as? String == "note:\(noteID)" })
        #expect(citations.allSatisfy { $0["acceptedAsTruth"] as? Bool == true })

        let claims = try #require(recap["claims"] as? [[String: Any]])
        #expect(claims.contains { ($0["text"] as? String)?.contains("watched Silo") == true })
        #expect(claims.allSatisfy { (($0["sourceRefs"] as? [String])?.isEmpty == false) })

        let diagnostics = try #require(recap["reviewableDiagnostics"] as? [[String: Any]])
        #expect(diagnostics.contains { ($0["truthBoundary"] as? String) == "reviewable_candidate_not_truth" })

        let boundary = try #require(recap["truthBoundary"] as? [String: Any])
        #expect(boundary["generatedTruth"] as? Bool == false)
        #expect(boundary["sourceBackedClaimsOnly"] as? Bool == true)
        #expect(boundary["candidateSignalsAcceptedAsTruth"] as? Bool == false)
        #expect(boundary["sourceMutation"] as? Bool == false)
    }

    @Test("monthly sparse recap query explains no source items in human language")
    func monthlySparseRecapQueryExplainsNoSourceItems() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let result = try assertJSON(
            runCLI(args: ["query", "what was happening in my life last month", "--json"], vault: vault),
            command: "query.monthly-chapter"
        )

        let recap = try #require(result["recap"] as? [String: Any])
        let answer = try #require(recap["answer"] as? String)
        #expect(answer.localizedCaseInsensitiveContains("no source items"))
        #expect(answer.localizedCaseInsensitiveContains("last month") || answer.localizedCaseInsensitiveContains("monthly chapter"))
        #expect(recap["sparseReason"] as? String == "no_source_items")

        let boundary = try #require(recap["truthBoundary"] as? [String: Any])
        #expect(boundary["sourceBackedClaimsOnly"] as? Bool == true)
        #expect(boundary["candidateSignalsAcceptedAsTruth"] as? Bool == false)
    }

    @Test("yearly recap wrapper keeps reviewable candidates out of accepted truth")
    func yearlyRecapWrapperKeepsReviewableCandidatesOutOfAcceptedTruth() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let january = try captureJournal(
            date: "2026-01-12",
            time: "08:10",
            text: "I watched Silo.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-03-09",
            time: "20:00",
            text: "We watched Silo again.",
            vault: vault
        )
        let item = try #require(january["item"] as? [String: Any])
        let noteID = try #require(item["id"] as? String)
        let marchPreview = try assertJSON(
            runCLI(args: ["item", "daily-episode", "--date", "2026-03-09", "--json"], vault: vault),
            command: "item.daily-episode"
        )
        let marchJournal = try #require(marchPreview["dailyJournal"] as? [String: Any])
        let marchNoteID = try #require(marchJournal["id"] as? String)
        try recordGraphCandidate(ownerType: "note", ownerID: noteID, mention: "Silo", quote: "I watched Silo.", vault: vault)
        try recordGraphCandidate(ownerType: "note", ownerID: marchNoteID, mention: "Silo", quote: "We watched Silo again.", vault: vault)

        let result = try assertJSON(
            runCLI(args: ["query", "what was happening in my life this year", "--json"], vault: vault),
            command: "query.yearly-book"
        )

        let recap = try #require(result["recap"] as? [String: Any])
        let diagnostics = try #require(recap["reviewableDiagnostics"] as? [[String: Any]])
        #expect(diagnostics.contains { ($0["text"] as? String)?.localizedCaseInsensitiveContains("Silo") == true })
        let candidateDiagnostics = diagnostics.filter { $0["candidateRefs"] is [String] }
        #expect(candidateDiagnostics.allSatisfy { $0["acceptedAsTruth"] as? Bool == false })
        #expect(candidateDiagnostics.allSatisfy { $0["truthBoundary"] as? String == "reviewable_candidate_not_truth" })

        let claims = try #require(recap["claims"] as? [[String: Any]])
        #expect(claims.contains { (($0["sourceRefs"] as? [String]) ?? []).contains("note:\(noteID)") })

        let boundary = try #require(recap["truthBoundary"] as? [String: Any])
        #expect(boundary["candidateSignalsAcceptedAsTruth"] as? Bool == false)
    }

    @Test("non recap query does not include recap wrapper")
    func nonRecapQueryDoesNotIncludeRecapWrapper() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        let output = try runCLI(args: ["query", "restaurants I saved last week", "--json"], vault: vault)
        let payload = try parseJSONObject(output.stdout)

        #expect(output.status != 0)
        #expect(payload["ok"] as? Bool == false)
        #expect(payload["recap"] == nil)
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
            .appendingPathComponent("cider-life-recap-wrapper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func recordGraphCandidate(
        ownerType: String,
        ownerID: String,
        mention: String,
        quote: String,
        vault: URL
    ) throws {
        let db = try openDatabase(in: vault)
        defer { db.close() }
        let owner = SecondBrainOwnerRef(ownerType: ownerType, ownerID: ownerID)
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: mention,
            sourceQuote: quote,
            objectTypeGuesses: [.media],
            relationGuesses: [.watched],
            reviewState: .suggested,
            source: "graph_candidate.life_recap_wrapper_test"
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
