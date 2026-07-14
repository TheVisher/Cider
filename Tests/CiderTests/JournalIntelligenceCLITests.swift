import Foundation
import Testing
@testable import Cider

@Suite("Journal Intelligence CLI Tests", .serialized)
@MainActor
struct JournalIntelligenceCLITests {
    @Test("representative text and voice captures produce all reviewable Journal Intelligence categories")
    func representativeCapturesProduceAllCategories() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        for capture in JournalIntelligenceCorpus.captures {
            _ = try captureJournal(
                date: JournalIntelligenceCorpus.date,
                time: capture.time,
                text: capture.text,
                vault: vault,
                extraArgs: capture.surface == "voice"
                    ? ["--surface", "voice", "--channel", "voice-transcript", "--source-meta", "input=voice-transcript"]
                    : []
            )
        }

        let result = try runCLI(
            args: ["item", "journal-intelligence", "--date", JournalIntelligenceCorpus.date, "--json"],
            vault: vault
        )
        #expect(result.status == 0, "stderr: \(result.stderr)")
        let payload = try parseJSONObject(result.stdout)
        let groups = try #require(payload["groups"] as? [[String: Any]])
        #expect(Set(groups.compactMap { $0["category"] as? String }) == Set(JournalIntelligenceCategory.allCases.map(\.rawValue)))

        let proposals = groups.flatMap { $0["proposals"] as? [[String: Any]] ?? [] }
        #expect(proposals.allSatisfy { proposal in
            guard let reconciliation = proposal["crossTimeReconciliation"] as? [String: Any],
                  let likelyMatches = reconciliation["likelyMatches"] as? [[String: Any]],
                  let canonicalScans = reconciliation["canonicalFamilyScans"] as? [[String: Any]],
                  let maximum = reconciliation["maxLikelyMatches"] as? Int else { return false }
            return reconciliation["readOnly"] as? Bool == true
                && reconciliation["changed"] as? Bool == false
                && reconciliation["truthBoundary"] as? String == "reviewable_candidate_not_truth"
                && reconciliation["status"] as? String != nil
                && reconciliation["reasonCodes"] as? [String] != nil
                && reconciliation["explanation"] as? String != nil
                && likelyMatches.count <= maximum
                && canonicalScans.allSatisfy { scan in
                    scan["family"] as? String != nil
                        && scan["limit"] as? Int != nil
                        && scan["loadedCount"] as? Int != nil
                        && scan["complete"] as? Bool != nil
                        && scan["truncated"] as? Bool != nil
                }
        })
        let unsupportedCategories = Set(proposals.compactMap { proposal -> String? in
            guard let reconciliation = proposal["crossTimeReconciliation"] as? [String: Any],
                  reconciliation["status"] as? String == "unsupported" else { return nil }
            return proposal["category"] as? String
        })
        #expect(unsupportedCategories == Set(["activities", "commitments"]))
        let requiredQuotes = [
            "Maya started a new job at Alder Labs",
            "I promised Maya I would bring the trail map tomorrow",
            "Remember to email the signed permit",
            "We are planning a September trip to Kyoto",
            "Save the ferry itinerary PDF with the trip",
            "Remember that hiking before work improves my mood",
        ]
        for quote in requiredQuotes {
            #expect(proposals.contains { proposal in
                guard let source = proposal["source"] as? [String: Any] else { return false }
                return (source["quote"] as? String)?.localizedCaseInsensitiveContains(quote) == true
                    && source["coordinateSpace"] as? String == "capture_event.source_text"
                    && proposal["truthBoundary"] as? String == "reviewable_candidate_not_truth"
            }, "Missing source-backed proposal for: \(quote)")
        }
        #expect(!proposals.contains { proposal in
            guard let source = proposal["source"] as? [String: Any],
                  let quote = source["quote"] as? String else { return false }
            let lower = quote.lowercased()
            return lower.contains("maybe alex")
                || lower.contains("did not go to portland")
                || lower.contains("did not visit the red barn")
                || lower == "i liked it"
        })
    }

    @Test("equivalent mentions across captures retain occurrences but deduplicate the receipt")
    func equivalentMentionsRetainOccurrencesAndDeduplicateReceipt() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let task = "Remember to email the signed permit."
        _ = try captureJournal(date: JournalIntelligenceCorpus.date, time: "07:05", text: task, vault: vault)
        _ = try captureJournal(
            date: JournalIntelligenceCorpus.date,
            time: "09:40",
            text: task,
            vault: vault,
            extraArgs: ["--surface", "voice", "--channel", "voice-transcript", "--source-meta", "input=voice-transcript"]
        )
        _ = try captureJournal(
            date: JournalIntelligenceCorpus.date,
            time: "09:55",
            text: "I need to email the signed permit.",
            vault: vault
        )
        _ = try captureJournal(
            date: JournalIntelligenceCorpus.date,
            time: "10:10",
            text: "Maya started a new job at Alder Labs.",
            vault: vault
        )
        _ = try captureJournal(
            date: JournalIntelligenceCorpus.date,
            time: "11:15",
            text: "Maya started a new job at Beacon Works.",
            vault: vault,
            extraArgs: ["--surface", "voice", "--channel", "voice-transcript", "--source-meta", "input=voice-transcript"]
        )

        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let stored = try database.prepare("""
            SELECT COUNT(DISTINCT json_extract(metadata, '$.capture_event_id'))
            FROM enrichment_outputs
            WHERE kind = 'memory_candidate'
              AND json_extract(metadata, '$.memory_kind') = 'task_intent'
              AND normalized_value = 'email the signed permit';
            """)
        _ = try stored.step()
        #expect(stored.int(at: 0) == 3)
        database.close()

        let result = try runCLI(
            args: ["item", "journal-intelligence", "--date", JournalIntelligenceCorpus.date, "--json"],
            vault: vault
        )
        #expect(result.status == 0, "stderr: \(result.stderr)")
        let payload = try parseJSONObject(result.stdout)
        let groups = try #require(payload["groups"] as? [[String: Any]])
        let taskGroup = try #require(groups.first { $0["category"] as? String == "tasks" })
        #expect(taskGroup["count"] as? Int == 1)
        let peopleGroup = try #require(groups.first { $0["category"] as? String == "people" })
        #expect(peopleGroup["count"] as? Int == 2)
        let people = try #require(peopleGroup["proposals"] as? [[String: Any]])
        #expect(Set(people.compactMap { $0["value"] as? String }) == Set([
            "Maya started a new job at Alder Labs.",
            "Maya started a new job at Beacon Works.",
        ]))
        #expect(Set(people.compactMap { proposal in
            (proposal["captureEvent"] as? [String: Any])?["id"] as? String
        }).count == 2)
        let suppressions = try #require(payload["suppressions"] as? [[String: Any]])
        #expect(suppressions.count { suppression in
            (suppression["reasonCodes"] as? [String])?.contains("duplicate_within_day") == true
                && (suppression["sourceQuote"] as? String)?.localizedCaseInsensitiveContains("email the signed permit") == true
        } == 2)
    }

    @Test("read-only JSON receipt is deterministic and leaves every SQLite table count unchanged")
    func receiptIsDeterministicAndNonMutating() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }

        _ = try captureJournal(
            date: "2026-07-12",
            time: "08:10",
            text: "I went to Discovery Park. I watched Arrival last night. I loved the cedar loop hike.",
            vault: vault
        )
        _ = try captureJournal(
            date: "2026-07-12",
            time: "18:45",
            text: "Dinner was tacos at home.",
            vault: vault,
            extraArgs: [
                "--surface", "voice",
                "--channel", "voice-transcript",
                "--source-meta", "input=voice-transcript",
            ]
        )

        let before = try tableCounts(in: vault)
        let firstResult = try runCLI(
            args: ["item", "journal-intelligence", "--date", "2026-07-12", "--json"],
            vault: vault
        )
        let middle = try tableCounts(in: vault)
        let secondResult = try runCLI(
            args: ["item", "journal-intelligence", "--date", "2026-07-12", "--json"],
            vault: vault
        )
        let after = try tableCounts(in: vault)

        #expect(firstResult.status == 0, "stderr: \(firstResult.stderr)")
        #expect(secondResult.status == 0, "stderr: \(secondResult.stderr)")
        #expect(firstResult.stdout == secondResult.stdout)
        #expect(before == middle)
        #expect(middle == after)

        let payload = try parseJSONObject(firstResult.stdout)
        #expect(payload["command"] as? String == "item.journal-intelligence")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["proposalCount"] as? Int == 4)
        #expect(payload["statement"] as? String == "Cider found 4 things worth reviewing.")
        let groups = try #require(payload["groups"] as? [[String: Any]])
        #expect(groups.map { $0["category"] as? String } == ["places", "activities", "preferences", "artifacts_media"])
        let proposals = groups.flatMap { $0["proposals"] as? [[String: Any]] ?? [] }
        #expect(proposals.allSatisfy { proposal in
            guard let owner = proposal["journalOwner"] as? [String: Any],
                  let capture = proposal["captureEvent"] as? [String: Any],
                  let section = proposal["section"] as? [String: Any],
                  let source = proposal["source"] as? [String: Any] else { return false }
            return (owner["ref"] as? String)?.hasPrefix("note:") == true
                && (capture["ref"] as? String)?.hasPrefix("capture_event:") == true
                && section["timestamp24Hour"] as? String != nil
                && source["coordinateSpace"] as? String == "capture_event.source_text"
                && source["quote"] as? String != nil
        })
    }

    @Test("JSON help contract declares read-only receipt semantics")
    func helpContractIsReadOnly() throws {
        let vault = try makeTempVault()
        defer { try? FileManager.default.removeItem(at: vault) }
        let result = try runCLI(
            args: ["item", "journal-intelligence", "--help", "--json"],
            vault: vault
        )
        let payload = try parseJSONObject(result.stdout)
        #expect(result.status == 0)
        #expect(payload["command"] as? String == "item.journal-intelligence.help")
        #expect(payload["readOnly"] as? Bool == true)
        #expect(payload["changed"] as? Bool == false)
        #expect(payload["usage"] as? String == "cider-cli item journal-intelligence --date YYYY-MM-DD [--json]")
    }

    private func captureJournal(
        date: String,
        time: String,
        text: String,
        vault: URL,
        extraArgs: [String] = []
    ) throws -> [String: Any] {
        let result = try runCLI(
            args: [
                "capture", "add", "--kind", "journal",
                "--date", date, "--time", time, "--stdin", "--json",
            ] + extraArgs,
            vault: vault,
            stdin: text
        )
        #expect(result.status == 0, "stderr: \(result.stderr)")
        return try parseJSONObject(result.stdout)
    }

    private func makeTempVault() throws -> URL {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-intelligence-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        return vault
    }

    private func tableCounts(in vault: URL) throws -> [String: Int] {
        let database = CiderDatabase()
        try database.open(at: vault.appendingPathComponent(".cider/cider.db"))
        defer { database.close() }
        let tables = try database.prepare("""
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name ASC;
            """)
        var result: [String: Int] = [:]
        while try tables.step() {
            let name = tables.string(at: 0)
            let count = try database.prepare("SELECT COUNT(*) FROM \(name);")
            _ = try count.step()
            result[name] = count.int(at: 0)
        }
        return result
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

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }
}
