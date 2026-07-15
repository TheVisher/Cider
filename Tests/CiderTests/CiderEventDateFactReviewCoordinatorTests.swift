import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Cider Event Date Fact Review Coordinator Tests", .serialized)
@MainActor
struct CiderEventDateFactReviewCoordinatorTests {
    private static let fixedVersion = Date(timeIntervalSince1970: 1_800_100_001.125)

    @Test("Event date approve reject and defer have semantic parity on Home Journal Review Queue and CLI")
    func supportedActionsHaveSurfaceParity() throws {
        for action in [CiderReviewAction.approve, .reject, .defer] {
            var fixtures: [Fixture] = []
            defer { fixtures.forEach { $0.close() } }
            var outcomes: [CiderReviewActionOutcome] = []
            for surface in [CiderReviewInvokingSurface.home, .journal, .reviewQueue, .cli] {
                let fixture = try makeFixture(candidateID: "event-date-parity-\(action.rawValue)")
                fixtures.append(fixture)
                let outcome = CiderReviewActionCoordinator(database: fixture.database).perform(
                    request(for: fixture.candidate, action: action, surface: surface)
                )
                #expect(outcome.isSuccessful, "action=\(action.rawValue) surface=\(surface.rawValue)")
                #expect(outcome.changed)
                #expect(outcome.evidenceStatus == .verifiedExactEvidence)
                #expect(outcome.actionReceiptID != nil)
                outcomes.append(outcome)
            }
            let baseline = try #require(outcomes.first)
            #expect(outcomes.dropFirst().allSatisfy { baseline.isSemanticallyEquivalentMutation(to: $0) })
            #expect(Set(outcomes.compactMap(\.actionReceiptID)).count == 1)
            #expect(fixtures.allSatisfy { (try? scalarCount("action_receipts", in: $0.database)) == 1 })
            print("CID837-CP3-PARITY action=\(action.rawValue) receipt=\(baseline.actionReceiptID ?? "missing") surfaces=home,journal,review_queue,cli")
            fixtures.forEach { $0.close() }
            fixtures.removeAll()
        }
    }

    @Test("Event date stale and missing exact evidence failures preserve every table and source file")
    func staleAndMissingEvidenceFailAtomically() throws {
        let stale = try makeFixture(candidateID: "event-date-stale")
        defer { stale.close() }
        var staleRequest = request(for: stale.candidate, action: .reject, surface: .home)
        staleRequest.expectedVersion.updatedAt = .distantPast
        let staleTables = try allTableFingerprints(in: stale.database)
        let staleFiles = try sourceFileFingerprints(in: stale.root)
        let staleOutcome = CiderReviewActionCoordinator(database: stale.database).perform(staleRequest)
        #expect(staleOutcome.error?.classification == .staleExpectedVersion)
        #expect(!staleOutcome.changed)
        #expect(staleOutcome.actionReceiptID == nil)
        #expect(try allTableFingerprints(in: stale.database) == staleTables)
        #expect(try sourceFileFingerprints(in: stale.root) == staleFiles)
        var optimistic = HomeReviewActionState()
        optimistic.begin(rowID: "event-date-stale-row")
        optimistic.reconcile(rowID: "event-date-stale-row", result: .failed(message: staleOutcome.message))
        #expect(!optimistic.pendingReviewIDs.contains("event-date-stale-row"))
        #expect(!optimistic.resolvedReviewIDs.contains("event-date-stale-row"))
        #expect(optimistic.errorMessage(for: "event-date-stale-row") == staleOutcome.message)
        print("CID837-CP3-FINGERPRINT stale tables=\(fingerprintDigest(staleTables)) tableCount=\(staleTables.count) files=\(fingerprintDigest(staleFiles)) fileCount=\(staleFiles.count) unchanged=true")

        let missing = try makeFixture(candidateID: "event-date-missing-evidence", exactEvidence: false)
        defer { missing.close() }
        let missingTables = try allTableFingerprints(in: missing.database)
        let missingFiles = try sourceFileFingerprints(in: missing.root)
        let missingOutcome = CiderReviewActionCoordinator(database: missing.database).perform(
            request(for: missing.candidate, action: .approve, surface: .reviewQueue)
        )
        #expect(missingOutcome.error?.classification == .missingExactEvidence)
        #expect(missingOutcome.evidenceStatus == .missingExactEvidence)
        #expect(!missingOutcome.changed)
        #expect(missingOutcome.actionReceiptID == nil)
        #expect(try allTableFingerprints(in: missing.database) == missingTables)
        #expect(try sourceFileFingerprints(in: missing.root) == missingFiles)
        print("CID837-CP3-FINGERPRINT missing-evidence tables=\(fingerprintDigest(missingTables)) tableCount=\(missingTables.count) files=\(fingerprintDigest(missingFiles)) fileCount=\(missingFiles.count) unchanged=true")
    }

    @Test("Event date writer and database failures roll back candidate truth receipts and every side effect")
    func writerAndDatabaseFailuresAreAtomic() throws {
        let writer = try makeFixture(candidateID: "event-date-writer-failure", proposedDate: "not-a-date")
        defer { writer.close() }
        let writerTables = try allTableFingerprints(in: writer.database)
        let writerFiles = try sourceFileFingerprints(in: writer.root)
        let writerOutcome = CiderReviewActionCoordinator(database: writer.database).perform(
            request(for: writer.candidate, action: .approve, surface: .home)
        )
        #expect(writerOutcome.error?.classification == .writerFailure)
        #expect(!writerOutcome.changed)
        #expect(try allTableFingerprints(in: writer.database) == writerTables)
        #expect(try sourceFileFingerprints(in: writer.root) == writerFiles)
        print("CID837-CP3-FINGERPRINT writer-failure tables=\(fingerprintDigest(writerTables)) tableCount=\(writerTables.count) files=\(fingerprintDigest(writerFiles)) fileCount=\(writerFiles.count) unchanged=true")

        let database = try makeFixture(candidateID: "event-date-database-failure")
        defer { database.close() }
        try database.database.runSQL("CREATE TRIGGER fail_event_date_receipt BEFORE INSERT ON action_receipts BEGIN SELECT RAISE(ABORT, 'injected receipt failure'); END;")
        let databaseTables = try allTableFingerprints(in: database.database)
        let databaseFiles = try sourceFileFingerprints(in: database.root)
        let databaseOutcome = CiderReviewActionCoordinator(database: database.database).perform(
            request(for: database.candidate, action: .approve, surface: .cli)
        )
        #expect(databaseOutcome.error?.classification == .databaseFailure)
        #expect(!databaseOutcome.changed)
        #expect(try allTableFingerprints(in: database.database) == databaseTables)
        #expect(try sourceFileFingerprints(in: database.root) == databaseFiles)
        print("CID837-CP3-FINGERPRINT database-failure tables=\(fingerprintDigest(databaseTables)) tableCount=\(databaseTables.count) files=\(fingerprintDigest(databaseFiles)) fileCount=\(databaseFiles.count) unchanged=true")
    }

    @Test("Exact retry and reopen reuse one durable receipt while changed payload or version fail closed")
    func exactRetryReopenAndChangedRequestBinding() throws {
        let fixture = try makeFixture(candidateID: "event-date-retry")
        defer { fixture.close() }
        let exactRequest = request(for: fixture.candidate, action: .approve, surface: .home, reason: "Private approval reason A")
        let coordinator = CiderReviewActionCoordinator(database: fixture.database)
        let first = coordinator.perform(exactRequest)
        let afterFirst = try allTableFingerprints(in: fixture.database)
        let retry = coordinator.perform(exactRequest)
        #expect(first.isSuccessful)
        #expect(retry.isSuccessful)
        #expect(first.actionReceiptID == retry.actionReceiptID)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try allTableFingerprints(in: fixture.database) == afterFirst)
        let receipt = try #require(try SecondBrainActionReceiptLedgerService(database: fixture.database).inspect(id: first.actionReceiptID ?? ""))
        let durableAfter = try #require(DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON))
        #expect(receipt.command == "item.event-date-facts.accept")
        #expect(receipt.action == "accept")
        #expect(durableAfter["requestFingerprint"]?.count == 64)
        #expect(durableAfter["reviewState"] == "accepted")
        #expect(durableAfter["truthBoundary"] == "accepted_event_date")
        #expect(durableAfter["structuredFactRef"] == "dateCard:22222222-2222-2222-2222-222222222222")

        var changedPayload = exactRequest
        changedPayload.reason = "Private approval reason B"
        #expect(coordinator.perform(changedPayload).error?.classification == .alreadyReviewed)
        var changedVersion = exactRequest
        changedVersion.expectedVersion.updatedAt = Self.fixedVersion.addingTimeInterval(0.000_001)
        #expect(coordinator.perform(changedVersion).error?.classification == .alreadyReviewed)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedRetry = CiderReviewActionCoordinator(database: reopened).perform(exactRequest)
        #expect(reopenedRetry.isSuccessful)
        #expect(reopenedRetry.actionReceiptID == first.actionReceiptID)
        #expect(try scalarCount("action_receipts", in: reopened) == 1)
        print("CID837-CP3-REOPEN receipt=\(first.actionReceiptID ?? "missing") command=\(receipt.command) action=\(receipt.action) reviewState=\(durableAfter["reviewState"] ?? "missing") truthBoundary=\(durableAfter["truthBoundary"] ?? "missing") target=\(durableAfter["structuredFactRef"] ?? "missing") count=1 fingerprint=\(fingerprintDigest(afterFirst)) tableCount=\(afterFirst.count)")
    }

    @Test("Event date receipt identity and bounded errors do not expose private source or reason content")
    func receiptsAndErrorsArePrivacySafe() throws {
        let privateQuote = "PRIVATE-SOURCE-/Users/secret/Journal.md-Ryland birthday"
        let privateReason = "PRIVATE-REASON-/Volumes/Personal"
        let fixture = try makeFixture(candidateID: "event-date-private", quote: privateQuote)
        defer { fixture.close() }
        let outcome = CiderReviewActionCoordinator(database: fixture.database).perform(
            request(for: fixture.candidate, action: .reject, surface: .cli, reason: privateReason)
        )
        let receiptID = try #require(outcome.actionReceiptID)
        let receipt = try #require(try SecondBrainActionReceiptLedgerService(database: fixture.database).inspect(id: receiptID))
        let serialized = [receipt.id, receipt.command, receipt.action, receipt.afterJSON ?? "", outcome.message, outcome.error?.message ?? ""].joined(separator: "\n")
        #expect(!serialized.contains(privateQuote))
        #expect(!serialized.contains(privateReason))
        #expect(!serialized.contains("/Users/secret"))
        #expect(!serialized.contains("/Volumes/Personal"))
        #expect(receipt.command == "item.event-date-facts.reject")
        #expect(receipt.action == "reject")
    }

    @Test("Queue exposes exact event date version and Home production routes the family through the coordinator")
    func queueAndHomeProductionSeamsAreTyped() throws {
        let fixture = try makeFixture(candidateID: "event-date-home-seam")
        defer { fixture.close() }
        let item = try #require(
            try CiderReviewQueueService(database: fixture.database).list(kind: "event_date_fact").items.first
        )
        #expect(item.candidateUpdatedAt == Self.fixedVersion)
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [],
            recentItems: [],
            folders: [],
            reviewQueueItems: [item],
            surfacingDays: 30
        )
        let homeItem = try #require(snapshot.reviewCockpitItems.first)
        #expect(homeItem.kindLabel == "Event Date Fact")
        #expect(homeItem.reviewActions == [.accept, .reject, .deferReview])
        #expect(homeItem.candidateUpdatedAt == Self.fixedVersion)

        let beforeUnsupported = try allTableFingerprints(in: fixture.database)
        let unsupportedCorrection = CiderReviewActionCoordinator(database: fixture.database).perform(
            request(for: fixture.candidate, action: .correct, surface: .journal)
        )
        #expect(unsupportedCorrection.error?.classification == .unsupportedActionForSurface)
        #expect(try allTableFingerprints(in: fixture.database) == beforeUnsupported)

        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let provider = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/Home/HomeOverviewDataProvider.swift"), encoding: .utf8)
        let content = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        #expect(provider.contains("case \"event_date_fact\":"))
        #expect(content.contains("family = .eventDateFact"))
        #expect(content.contains("surface: .reviewQueue"))
        #expect(content.contains("CiderReviewActionCoordinator"))
    }

    @Test("Event date CLI preserves aliases help safety exact retry and executes emitted verification commands")
    func cliCompatibilityHelpAndVerificationCommands() throws {
        let helpFixture = try makeFixture(candidateID: "event-date-help")
        let helpTables = try allTableFingerprints(in: helpFixture.database)
        let helpFiles = try sourceFileFingerprints(in: helpFixture.root)
        helpFixture.database.close()
        let jsonHelp = try runCLI(args: ["item", "event-date-facts", "--help", "--json"], vault: helpFixture.root)
        let plainHelp = try runCLI(args: ["item", "event-date-facts", "--help"], vault: helpFixture.root)
        #expect(jsonHelp.status == 0)
        #expect(plainHelp.status == 0)
        let helpPayload = try parseJSONObject(jsonHelp.stdout)
        #expect(helpPayload["readOnly"] as? Bool == true)
        #expect(helpPayload["changed"] as? Bool == false)
        let reopenedHelp = CiderDatabase()
        try reopenedHelp.open(at: helpFixture.databaseURL)
        #expect(try allTableFingerprints(in: reopenedHelp) == helpTables)
        #expect(try sourceFileFingerprints(in: helpFixture.root) == helpFiles)
        reopenedHelp.close()
        try? FileManager.default.removeItem(at: helpFixture.root)

        let actionFixture = try makeFixture(candidateID: "event-date-cli-smoke")
        actionFixture.database.close()
        let first = try runCLI(
            args: ["review", "reject", actionFixture.candidate.id, "--json"],
            vault: actionFixture.root
        )
        #expect(first.status == 0, "stderr=\(first.stderr) stdout=\(first.stdout)")
        let payload = try parseJSONObject(first.stdout)
        #expect(payload["command"] as? String == "review.event-date-facts.reject")
        #expect(payload["action"] as? String == "reject")
        #expect(payload["reviewFamily"] as? String == "event_date_fact")
        #expect(payload["evidenceStatus"] as? String == "verified_exact_evidence")
        let receipt = try #require(payload["actionReceipt"] as? [String: Any])
        #expect(receipt["canonicalCommand"] as? String == "item.event-date-facts.reject")
        let selector = try #require(payload["expectedVersionSelector"] as? String)
        let receiptID = try #require(payload["actionReceiptID"] as? String)
        let retry = try runCLI(
            args: ["item", "event-date-facts", "reject", actionFixture.candidate.id, "--actor", "user", "--expected-version", selector, "--json"],
            vault: actionFixture.root
        )
        #expect(retry.status == 0)
        let retryPayload = try parseJSONObject(retry.stdout)
        #expect(retryPayload["command"] as? String == "item.event-date-facts.reject")
        #expect(retryPayload["actionReceiptID"] as? String == receiptID)
        let genericAlias = try runCLI(
            args: ["item", "fact-validity", "reject", actionFixture.candidate.id, "--actor", "user", "--expected-version", selector, "--json"],
            vault: actionFixture.root
        )
        #expect(genericAlias.status == 0)
        let genericPayload = try parseJSONObject(genericAlias.stdout)
        #expect(genericPayload["command"] as? String == "item.fact-validity.reject")
        #expect(genericPayload["actionReceiptID"] as? String == receiptID)
        #expect(genericPayload["candidate"] as? [String: Any] != nil)

        let plainReviewAlias = try runCLI(
            args: ["review", "reject", actionFixture.candidate.id, "--expected-version", selector],
            vault: actionFixture.root
        )
        #expect(plainReviewAlias.status == 0)
        #expect(plainReviewAlias.stdout.contains("Event/date fact review action: \(actionFixture.candidate.id)"))
        let plainGenericAlias = try runCLI(
            args: ["item", "fact-validity", "reject", actionFixture.candidate.id, "--actor", "user", "--expected-version", selector],
            vault: actionFixture.root
        )
        #expect(plainGenericAlias.status == 0)
        #expect(plainGenericAlias.stdout.contains("Fact validity reject: \(actionFixture.candidate.id)"))

        let commands = try #require(payload["safeVerificationCommands"] as? [String])
        #expect(!commands.isEmpty)
        for command in commands {
            let args = command.split(separator: " ").map(String.init)
            #expect(args.first == "cider-cli")
            let verified = try runCLI(args: Array(args.dropFirst()), vault: actionFixture.root)
            #expect(verified.status == 0, "command=\(command) stderr=\(verified.stderr) stdout=\(verified.stdout)")
            if let verifiedPayload = try? parseJSONObject(verified.stdout) {
                #expect(verifiedPayload["ok"] as? Bool != false)
            }
        }
        let reopenedAction = CiderDatabase()
        try reopenedAction.open(at: actionFixture.databaseURL)
        #expect(try mutationReceiptCount(command: "item.event-date-facts.reject", in: reopenedAction) == 1)
        reopenedAction.close()
        try? FileManager.default.removeItem(at: actionFixture.root)
        print("CID837-CP3-CLI candidate=\(actionFixture.candidate.id) receipt=\(receiptID) verificationCommands=\(commands.count) helpUnchanged=true")
    }

    private struct Fixture {
        let root: URL
        let databaseURL: URL
        let database: CiderDatabase
        let candidate: SecondBrainEventDateFactCandidateView

        @MainActor
        func close() {
            database.close()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture(
        candidateID: String,
        exactEvidence: Bool = true,
        proposedDate: String = "2027-01-16",
        quote: String = "Today is Ryland's birthday; remember the exact source.") throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cid837-cp3-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".cider"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Daily"), withIntermediateDirectories: true)
        try quote.write(to: root.appendingPathComponent("Daily/Journal.md"), atomically: true, encoding: .utf8)
        let databaseURL = root.appendingPathComponent(".cider/cider.db")
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        let noteID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let item = try database.prepare("INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path) VALUES (?, 'note', 'Disposable Journal', ?, ?, NULL, 'Daily/Journal.md');")
        item.bind(noteID.uuidString, at: 1).bind(Self.fixedVersion.timeIntervalSince1970, at: 2).bind(Self.fixedVersion.timeIntervalSince1970, at: 3)
        try item.step()
        let note = try database.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, NULL, 0);")
        note.bind(noteID.uuidString, at: 1).bind(quote, at: 2)
        try note.step()
        let targetID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let target = try database.prepare("INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path) VALUES (?, 'event', 'Ryland birthday', ?, ?, NULL, 'Inbox/DateCards/Ryland birthday.ics');")
        target.bind(targetID.uuidString, at: 1).bind(Self.fixedVersion.timeIntervalSince1970, at: 2).bind(Self.fixedVersion.timeIntervalSince1970, at: 3)
        try target.step()
        let service = SecondBrainEventDateFactReviewService(database: database)
        let proposed = try service.proposeFromSourceObservation(
            sourceOwner: .init(ownerType: "note", ownerID: noteID.uuidString),
            sourceQuote: quote,
            sourceDate: Date(timeIntervalSince1970: 1_800_100_000),
            targetKind: .dateCard,
            actor: "fixture",
            reason: "Source-backed disposable fixture.",
            targetItemID: targetID
        )
        try database.runSQL("UPDATE fact_validity_candidates SET id = '\(candidateID)', updated_at = \(Self.fixedVersion.timeIntervalSince1970), metadata = json_set(metadata, '$.proposed_date', '\(proposedDate)') WHERE id = '\(proposed.id)';")
        try database.runSQL("UPDATE source_evidence SET derived_owner_id = '\(candidateID)', candidate_ref = 'fact_validity_candidate:\(candidateID)' WHERE derived_owner_id = '\(proposed.id)';")
        try database.runSQL("UPDATE review_lifecycle_events SET owner_id = '\(candidateID)', candidate_ref = 'fact_validity_candidate:\(candidateID)' WHERE owner_id = '\(proposed.id)';")
        if !exactEvidence {
            try database.runSQL("DELETE FROM source_evidence WHERE derived_owner_id = '\(candidateID)';")
        }
        let candidate = try service.inspect(candidateID: candidateID)
        return Fixture(root: root, databaseURL: databaseURL, database: database, candidate: candidate)
    }

    private func request(
        for candidate: SecondBrainEventDateFactCandidateView,
        action: CiderReviewAction,
        surface: CiderReviewInvokingSurface,
        reason: String = "Review exact source-backed event date.") -> CiderReviewActionRequest {
        CiderReviewActionRequest(
            identity: .init(candidateRef: candidate.candidateRef, family: .eventDateFact),
            expectedVersion: .init(reviewState: candidate.reviewState, updatedAt: candidate.candidate.candidate.updatedAt),
            action: action,
            reason: reason,
            actor: "cid837-cp3-reviewer",
            surface: surface,
            exactEvidenceRequirement: .required,
            mutationAuthority: .reviewApprovedCandidate
        )
    }

    private func scalarCount(_ table: String, in database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func mutationReceiptCount(command: String, in database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM action_receipts WHERE command = ? AND changed = 1;")
        statement.bind(command, at: 1)
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func allTableFingerprints(in database: CiderDatabase) throws -> [String: String] {
        let statement = try database.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name;")
        var tables: [String] = []
        while try statement.step() { tables.append(statement.string(at: 0)) }
        return try Dictionary(uniqueKeysWithValues: tables.map { table in
            let pragma = try database.prepare("PRAGMA table_info(\(table));")
            var columns: [String] = []
            while try pragma.step() { columns.append(pragma.string(at: 1)) }
            let pairs = columns.flatMap { ["'\($0)'", "quote(\"\($0)\")"] }.joined(separator: ", ")
            let rowsStatement = try database.prepare("SELECT json_object(\(pairs)) FROM \(table);")
            var rows: [String] = []
            while try rowsStatement.step() { rows.append(rowsStatement.string(at: 0)) }
            return (table, "count=\(rows.count);sha256=\(sha256(Data(rows.sorted().joined(separator: "\n").utf8)))")
        })
    }

    private func sourceFileFingerprints(in root: URL) throws -> [String: String] {
        let files = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Daily"), includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, sha256(try Data(contentsOf: $0))) })
    }

    private func fingerprintDigest(_ values: [String: String]) -> String {
        sha256(Data(values.keys.sorted().map { "\($0)=\(values[$0] ?? "")" }.joined(separator: "\n").utf8))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func runCLI(args: [String], vault: URL) throws -> (stdout: String, stderr: String, status: Int32) {
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
            process.terminationStatus
        )
    }

    private func cliURL() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            root.appendingPathComponent(".build/arm64-apple-macosx/debug/cider-cli"),
            root.appendingPathComponent(".build/debug/cider-cli"),
        ]
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private func parseJSONObject(_ output: String) throws -> [String: Any] {
        let json = output.drop { $0 != "{" }
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return try #require(object as? [String: Any])
    }
}
