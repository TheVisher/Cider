import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Cider Review Action Coordinator Tests")
@MainActor
struct CiderReviewActionCoordinatorTests {
    private enum InjectedFailure: Error {
        case writer
    }

    @Test("Home Journal full Review Queue and CLI use one typed mutation outcome and durable receipt identity")
    func supportedSurfaceOutcomesAreSemanticallyEquivalent() throws {
        let home = try makeFixture(candidateID: "shared-memory")
        defer { home.close() }
        let journal = try makeFixture(candidateID: "shared-memory")
        defer { journal.close() }
        let fullReviewQueue = try makeFixture(candidateID: "shared-memory")
        defer { fullReviewQueue.close() }
        let cli = try makeFixture(candidateID: "shared-memory")
        defer { cli.close() }

        let homeRequest = request(for: home.output, surface: .home, action: .approve)
        let journalRequest = request(for: journal.output, surface: .journal, action: .approve)
        let fullReviewQueueRequest = request(for: fullReviewQueue.output, surface: .home, action: .approve)
        let cliRequest = request(for: cli.output, surface: .cli, action: .approve)
        let homeOutcome = CiderReviewActionCoordinator(database: home.database).perform(homeRequest)
        let journalOutcome = CiderReviewActionCoordinator(database: journal.database).perform(journalRequest)
        let fullReviewQueueOutcome = CiderReviewActionCoordinator(database: fullReviewQueue.database).perform(fullReviewQueueRequest)
        let cliOutcome = CiderReviewActionCoordinator(database: cli.database).perform(cliRequest)

        #expect(homeOutcome.isSuccessful)
        #expect(journalOutcome.isSuccessful)
        #expect(fullReviewQueueOutcome.isSuccessful)
        #expect(cliOutcome.isSuccessful)
        #expect(homeOutcome.isSemanticallyEquivalentMutation(to: journalOutcome))
        #expect(homeOutcome.isSemanticallyEquivalentMutation(to: fullReviewQueueOutcome))
        #expect(homeOutcome.isSemanticallyEquivalentMutation(to: cliOutcome))
        #expect(homeOutcome.changed)
        #expect(homeOutcome.resultingReviewState == "accepted")
        #expect(homeOutcome.truthBoundary == "accepted_memory_candidate")
        #expect(homeOutcome.evidenceStatus == .verifiedExactEvidence)
        #expect(homeOutcome.mutationAuthority == .reviewApprovedCandidate)
        #expect(homeOutcome.actionReceiptID != nil)
        #expect(homeOutcome.actionReceiptID == journalOutcome.actionReceiptID)
        #expect(homeOutcome.actionReceiptID == fullReviewQueueOutcome.actionReceiptID)
        #expect(homeOutcome.actionReceiptID == cliOutcome.actionReceiptID)
        #expect(try scalarCount("action_receipts", in: home.database) == 1)
        #expect(try scalarCount("action_receipts", in: journal.database) == 1)
        #expect(try scalarCount("action_receipts", in: fullReviewQueue.database) == 1)
        #expect(try scalarCount("action_receipts", in: cli.database) == 1)
        print("CID837-PARITY receipt=\(homeOutcome.actionReceiptID ?? "missing") homeChanged=\(homeOutcome.changed) journalChanged=\(journalOutcome.changed) fullReviewChanged=\(fullReviewQueueOutcome.changed) cliChanged=\(cliOutcome.changed)")
    }

    @Test("Every supported graph and memory action has semantic parity across production surfaces")
    func allSupportedFamilyActionsHaveSurfaceParity() throws {
        let cases: [(CiderReviewCandidateFamily, CiderReviewAction)] = [
            (.memoryCandidate, .approve), (.memoryCandidate, .reject), (.memoryCandidate, .defer), (.memoryCandidate, .correct),
            (.graphCandidate, .approve), (.graphCandidate, .reject), (.graphCandidate, .defer), (.graphCandidate, .correct),
        ]
        for (index, actionCase) in cases.enumerated() {
            let surfaces: [CiderReviewInvokingSurface] = actionCase.1 == .correct
                ? [.journal, .cli]
                : [.home, .journal, .home, .cli]
            var fixtures: [Fixture] = []
            defer { fixtures.forEach { $0.close() } }
            var outcomes: [CiderReviewActionOutcome] = []
            for (surfaceIndex, surface) in surfaces.enumerated() {
                let fixture = try makeFixture(
                    candidateID: "surface-parity-\(index)",
                    family: actionCase.0
                )
                fixtures.append(fixture)
                let target = actionCase.0 == .graphCandidate
                    && (actionCase.1 == .approve || actionCase.1 == .correct)
                    ? try #require(graphTargetOptions(for: fixture.output, in: fixture.database).first).optionRef
                    : nil
                let candidateRequest = request(
                    for: fixture.output,
                    surface: surface,
                    action: actionCase.1,
                    correction: actionCase.1 == .correct && actionCase.0 == .memoryCandidate
                        ? "Corrected parity wording."
                        : nil,
                    target: target
                )
                let outcome = CiderReviewActionCoordinator(database: fixture.database).perform(candidateRequest)
                #expect(outcome.isSuccessful, "family=\(actionCase.0.rawValue) action=\(actionCase.1.rawValue) surfaceIndex=\(surfaceIndex)")
                #expect(outcome.changed)
                outcomes.append(outcome)
            }
            let baseline = try #require(outcomes.first)
            #expect(outcomes.dropFirst().allSatisfy { baseline.isSemanticallyEquivalentMutation(to: $0) })
            #expect(Set(outcomes.compactMap(\.actionReceiptID)).count == 1)
            fixtures.forEach { $0.close() }
            fixtures.removeAll()
        }
    }

    @Test("Stale and missing evidence failures leave every table and source file unchanged")
    func staleAndEvidenceFailuresAreAtomic() throws {
        let stale = try makeFixture(candidateID: "stale-memory")
        defer { stale.close() }
        var staleRequest = request(for: stale.output, surface: .home, action: .reject)
        staleRequest.expectedVersion.updatedAt = .distantPast
        let staleTablesBefore = try allTableFingerprints(in: stale.database)
        let staleFilesBefore = try sourceFileFingerprints(in: stale.root)

        let staleOutcome = CiderReviewActionCoordinator(database: stale.database).perform(staleRequest)

        #expect(staleOutcome.error?.classification == .staleExpectedVersion)
        #expect(!staleOutcome.changed)
        #expect(staleOutcome.actionReceiptID == nil)
        let staleTablesAfter = try allTableFingerprints(in: stale.database)
        let staleFilesAfter = try sourceFileFingerprints(in: stale.root)
        #expect(staleTablesAfter == staleTablesBefore)
        #expect(staleFilesAfter == staleFilesBefore)
        print("CID837-FINGERPRINT stale tables=\(fingerprintDigest(staleTablesBefore)) tableCount=\(staleTablesBefore.count) files=\(fingerprintDigest(staleFilesBefore)) unchanged=true")

        let missingEvidence = try makeFixture(candidateID: "missing-evidence", exactEvidence: false)
        defer { missingEvidence.close() }
        let evidenceTablesBefore = try allTableFingerprints(in: missingEvidence.database)
        let evidenceFilesBefore = try sourceFileFingerprints(in: missingEvidence.root)

        let evidenceOutcome = CiderReviewActionCoordinator(database: missingEvidence.database).perform(
            request(for: missingEvidence.output, surface: .journal, action: .reject)
        )

        #expect(evidenceOutcome.error?.classification == .missingExactEvidence)
        #expect(evidenceOutcome.evidenceStatus == .missingExactEvidence)
        #expect(!evidenceOutcome.changed)
        let evidenceTablesAfter = try allTableFingerprints(in: missingEvidence.database)
        let evidenceFilesAfter = try sourceFileFingerprints(in: missingEvidence.root)
        #expect(evidenceTablesAfter == evidenceTablesBefore)
        #expect(evidenceFilesAfter == evidenceFilesBefore)
        print("CID837-FINGERPRINT missing-evidence tables=\(fingerprintDigest(evidenceTablesBefore)) tableCount=\(evidenceTablesBefore.count) files=\(fingerprintDigest(evidenceFilesBefore)) unchanged=true")
    }

    @Test("Unsupported family action surface and authority combinations fail closed")
    func unsupportedCombinationsFailClosed() throws {
        let fixture = try makeFixture(candidateID: "unsupported-memory")
        defer { fixture.close() }
        let coordinator = CiderReviewActionCoordinator(database: fixture.database)
        let before = try allTableFingerprints(in: fixture.database)

        var unsupportedFamily = request(for: fixture.output, surface: .home, action: .approve)
        unsupportedFamily.identity.family = .similarityCandidate
        unsupportedFamily.identity.candidateRef = "similarity_candidate:unsupported-memory"
        let familyOutcome = coordinator.perform(unsupportedFamily)
        #expect(familyOutcome.error?.classification == .unsupportedFamily)

        let homeCorrection = coordinator.perform(
            request(for: fixture.output, surface: .home, action: .correct, correction: "Corrected")
        )
        #expect(homeCorrection.error?.classification == .unsupportedActionForSurface)

        let unsupportedSurfaceRequest = request(for: fixture.output, surface: .reviewQueue, action: .approve)
        let unsupportedSurfaceOutcome = coordinator.perform(unsupportedSurfaceRequest)
        #expect(unsupportedSurfaceOutcome.error?.classification == .unsupportedSurface)

        var weakenedCLIRequest = request(for: fixture.output, surface: .cli, action: .approve)
        weakenedCLIRequest.exactEvidenceRequirement = .notRequired
        let weakenedCLIOutcome = coordinator.perform(weakenedCLIRequest)
        #expect(weakenedCLIOutcome.error?.classification == .exactEvidenceRequired)
        #expect(!weakenedCLIOutcome.changed)

        var inferredRequest = request(for: fixture.output, surface: .journal, action: .approve)
        inferredRequest.mutationAuthority = .inferredProposal
        let inferredOutcome = coordinator.perform(inferredRequest)
        #expect(inferredOutcome.error?.classification == .reviewApprovalRequired)
        #expect(try allTableFingerprints(in: fixture.database) == before)
    }

    @Test("Correction and target validation happens before the canonical writer")
    func correctionAndTargetValidationFailBeforeWriter() throws {
        var writerCallCount = 0
        let coordinator = CiderReviewActionCoordinator { _, _ in
            writerCallCount += 1
            throw InjectedFailure.writer
        }
        let expected = CiderReviewExpectedVersion(reviewState: "suggested", updatedAt: Date(timeIntervalSince1970: 1_800_000_001))
        let memoryCorrection = CiderReviewActionRequest(
            identity: .init(candidateRef: "memory_candidate:correction", family: .memoryCandidate),
            expectedVersion: expected,
            action: .correct,
            correction: "   ",
            actor: "user",
            surface: .journal,
            exactEvidenceRequirement: .required,
            mutationAuthority: .reviewApprovedCandidate
        )
        let graphApproval = CiderReviewActionRequest(
            identity: .init(candidateRef: "graph_candidate:target", family: .graphCandidate),
            expectedVersion: expected,
            action: .approve,
            actor: "user",
            surface: .journal,
            exactEvidenceRequirement: .required,
            mutationAuthority: .reviewApprovedCandidate
        )

        #expect(coordinator.perform(memoryCorrection).error?.classification == .correctionRequired)
        #expect(coordinator.perform(graphApproval).error?.classification == .targetRequired)
        #expect(writerCallCount == 0)
    }

    @Test("Duplicate retry is idempotent and reuses the canonical durable receipt")
    func duplicateRetryReusesReceipt() throws {
        let fixture = try makeFixture(candidateID: "retry-memory")
        defer { fixture.close() }
        let coordinator = CiderReviewActionCoordinator(database: fixture.database)
        let candidateRequest = request(for: fixture.output, surface: .home, action: .approve)

        let first = coordinator.perform(candidateRequest)
        let afterFirst = try allTableFingerprints(in: fixture.database)
        let retry = coordinator.perform(candidateRequest)

        #expect(first.isSuccessful)
        #expect(first.changed)
        #expect(retry.isSuccessful)
        #expect(!retry.changed)
        #expect(retry.actionReceiptID == first.actionReceiptID)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try scalarCount("agent_actions", in: fixture.database) == 1)
        #expect(try allTableFingerprints(in: fixture.database) == afterFirst)
        print("CID837-RETRY receipt=\(first.actionReceiptID ?? "missing") tablesAfterFirst=\(fingerprintDigest(afterFirst)) receiptRows=1 agentActionRows=1 unchangedOnRetry=true")
    }

    @Test("Exact memory approve reject defer and correct retries replay one durable mutation")
    func exactMemoryActionRetriesReplayOnce() throws {
        let cases: [(CiderReviewAction, String?)] = [
            (.approve, nil),
            (.reject, nil),
            (.defer, nil),
            (.correct, "  Keep the corrected private wording.  "),
        ]

        for (index, actionCase) in cases.enumerated() {
            let fixture = try makeFixture(candidateID: "retry-memory-\(index)")
            let coordinator = CiderReviewActionCoordinator(database: fixture.database)
            let candidateRequest = request(
                for: fixture.output,
                surface: .journal,
                action: actionCase.0,
                correction: actionCase.1
            )

            let first = coordinator.perform(candidateRequest)
            let afterFirstTables = try allTableFingerprints(in: fixture.database)
            let afterFirstFiles = try sourceFileFingerprints(in: fixture.root)
            let retry = coordinator.perform(candidateRequest)

            #expect(first.isSuccessful)
            #expect(first.changed)
            #expect(retry.isSuccessful)
            #expect(!retry.changed)
            #expect(retry.actionReceiptID == first.actionReceiptID)
            #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
            #expect(try scalarCount("agent_actions", in: fixture.database) == 1)
            #expect(try allTableFingerprints(in: fixture.database) == afterFirstTables)
            #expect(try sourceFileFingerprints(in: fixture.root) == afterFirstFiles)
            fixture.close()
        }
    }

    @Test("Changed normalized memory correction fails stale without replay or mutation")
    func changedMemoryCorrectionDoesNotReplay() throws {
        let fixture = try makeFixture(candidateID: "changed-correction-memory")
        defer { fixture.close() }
        let coordinator = CiderReviewActionCoordinator(database: fixture.database)
        let original = request(
            for: fixture.output,
            surface: .journal,
            action: .correct,
            correction: "  Correction A  "
        )
        #expect(coordinator.perform(original).isSuccessful)
        var normalizedEquivalent = original
        normalizedEquivalent.correction = "Correction A"
        let normalizedReplay = coordinator.perform(normalizedEquivalent)
        #expect(normalizedReplay.isSuccessful)
        #expect(!normalizedReplay.changed)
        var changed = original
        changed.correction = "Correction B"
        let beforeTables = try allTableFingerprints(in: fixture.database)
        let beforeFiles = try sourceFileFingerprints(in: fixture.root)

        let outcome = coordinator.perform(changed)

        #expect(outcome.error?.classification == .staleExpectedVersion)
        #expect(!outcome.changed)
        #expect(outcome.actionReceiptID == nil)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try scalarCount("agent_actions", in: fixture.database) == 1)
        #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
        #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
        print("CID837-REPLAY-MISMATCH correction tables=\(fingerprintDigest(beforeTables)) files=\(fingerprintDigest(beforeFiles)) unchanged=true")
    }

    @Test("Changed graph target fails stale without replay or mutation")
    func changedGraphTargetDoesNotReplay() throws {
        for action in [CiderReviewAction.approve, .correct] {
            let fixture = try makeFixture(candidateID: "changed-target-graph-\(action.rawValue)", family: .graphCandidate)
            let options = try graphTargetOptions(for: fixture.output, in: fixture.database)
            let targetA = try #require(options.first)
            let targetB = try #require(options.first { $0.optionRef != targetA.optionRef })
            let coordinator = CiderReviewActionCoordinator(database: fixture.database)
            let original = request(
                for: fixture.output,
                surface: .journal,
                action: action,
                target: targetA.optionRef
            )
            #expect(coordinator.perform(original).isSuccessful)
            var changed = original
            changed.targetOptionRef = targetB.optionRef
            let beforeTables = try allTableFingerprints(in: fixture.database)
            let beforeFiles = try sourceFileFingerprints(in: fixture.root)

            let outcome = coordinator.perform(changed)

            #expect(outcome.error?.classification == (action == .approve ? .alreadyReviewed : .staleExpectedVersion))
            #expect(!outcome.changed)
            #expect(outcome.actionReceiptID == nil)
            #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
            #expect(try scalarCount("agent_actions", in: fixture.database) == 1)
            #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
            #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
            print("CID837-REPLAY-MISMATCH target action=\(action.rawValue) tables=\(fingerprintDigest(beforeTables)) files=\(fingerprintDigest(beforeFiles)) unchanged=true")
            fixture.close()
        }
    }

    @Test("Sub-millisecond expected versions have distinct request fingerprints and receipt identities")
    func subMillisecondVersionsHaveDistinctIdentities() {
        let firstDate = Date(timeIntervalSince1970: 1_800_000_000.000_1)
        let secondDate = Date(timeIntervalSince1970: 1_800_000_000.000_2)
        let first = journalRequest(expectedUpdatedAt: firstDate, correction: "private correction")
        let second = journalRequest(expectedUpdatedAt: secondDate, correction: "private correction")

        let firstFingerprint = JournalIntelligenceReviewActionService.requestFingerprint(for: first, actor: "request-fingerprint-test")
        let secondFingerprint = JournalIntelligenceReviewActionService.requestFingerprint(for: second, actor: "request-fingerprint-test")
        let firstReceiptID = JournalIntelligenceReviewActionService.actionReceiptID(for: first, actor: "request-fingerprint-test")
        let secondReceiptID = JournalIntelligenceReviewActionService.actionReceiptID(for: second, actor: "request-fingerprint-test")

        #expect(Int64((firstDate.timeIntervalSince1970 * 1_000).rounded()) == Int64((secondDate.timeIntervalSince1970 * 1_000).rounded()))
        #expect(firstFingerprint != secondFingerprint)
        #expect(firstReceiptID != secondReceiptID)
    }

    @Test("checkpoint one default requests retain their receipt fingerprint identity")
    func checkpointOneReceiptFingerprintIdentityIsStable() {
        let expectedDate = Date(timeIntervalSince1970: 1_800_000_000.25)
        let request = journalRequest(expectedUpdatedAt: expectedDate, correction: "private correction")
        let fields = [
            "journal-review-request-v1",
            "memory_candidate:fingerprint-contract",
            "memory_candidate",
            "correct",
            "fingerprint-stability-test",
            "suggested",
            String(format: "%016llx", expectedDate.timeIntervalSinceReferenceDate.bitPattern),
            "private correction",
            "",
        ]
        let canonical = fields.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
        let checkpointOneFingerprint = SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        #expect(JournalIntelligenceReviewActionService.requestFingerprint(
            for: request,
            actor: "fingerprint-stability-test"
        ) == checkpointOneFingerprint)
    }

    @Test("Intervening correction invalidates replay even while review state stays reviewable")
    func interveningCorrectionInvalidatesOriginalReplay() throws {
        let fixture = try makeFixture(candidateID: "intervening-correction-memory")
        defer { fixture.close() }
        let coordinator = CiderReviewActionCoordinator(database: fixture.database)
        let original = request(
            for: fixture.output,
            surface: .journal,
            action: .correct,
            correction: "Correction A"
        )
        #expect(coordinator.perform(original).isSuccessful)
        let afterFirst = try #require(
            try SecondBrainEnrichmentOutputService(database: fixture.database).output(id: fixture.output.id)
        )
        let later = request(
            for: afterFirst,
            surface: .journal,
            action: .correct,
            correction: "Correction B"
        )
        #expect(coordinator.perform(later).isSuccessful)
        let current = try #require(
            try SecondBrainEnrichmentOutputService(database: fixture.database).output(id: fixture.output.id)
        )
        #expect(current.reviewState == "needs_review")
        let beforeTables = try allTableFingerprints(in: fixture.database)
        let beforeFiles = try sourceFileFingerprints(in: fixture.root)

        let replay = coordinator.perform(original)

        #expect(replay.error?.classification == .staleExpectedVersion)
        #expect(!replay.changed)
        #expect(replay.actionReceiptID == nil)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 2)
        #expect(try scalarCount("agent_actions", in: fixture.database) == 2)
        #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
        #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
        print("CID837-REPLAY-MISMATCH intervening tables=\(fingerprintDigest(beforeTables)) files=\(fingerprintDigest(beforeFiles)) unchanged=true")
    }

    @Test("Missing or tampered durable replay bindings fail closed")
    func missingOrTamperedReplayBindingsFailClosed() throws {
        enum TamperCase {
            case missingFingerprint
            case changedFingerprint
            case missingResultingVersion
            case changedResultingVersion
        }
        let cases: [TamperCase] = [.missingFingerprint, .changedFingerprint, .missingResultingVersion, .changedResultingVersion]

        for (index, tamperCase) in cases.enumerated() {
            let fixture = try makeFixture(candidateID: "tampered-receipt-\(index)")
            let coordinator = CiderReviewActionCoordinator(database: fixture.database)
            let candidateRequest = request(for: fixture.output, surface: .journal, action: .approve)
            let first = coordinator.perform(candidateRequest)
            let receiptID = try #require(first.actionReceiptID)
            let receipt = try #require(try SecondBrainActionReceiptLedgerService(database: fixture.database).inspect(id: receiptID))
            var envelope = try #require(DatabaseHelpers.decodeJSON([String: String].self, from: receipt.afterJSON))
            switch tamperCase {
            case .missingFingerprint:
                envelope["requestFingerprint"] = nil
            case .changedFingerprint:
                envelope["requestFingerprint"] = String(repeating: "0", count: 64)
            case .missingResultingVersion:
                envelope["resultingCandidateVersion"] = nil
            case .changedResultingVersion:
                envelope["resultingCandidateVersion"] = "0000000000000000"
            }
            let update = try fixture.database.prepare("UPDATE action_receipts SET after_json = ? WHERE id = ?;")
            update.bind(DatabaseHelpers.encodeJSON(envelope), at: 1).bind(receiptID, at: 2)
            try update.step()
            let beforeTables = try allTableFingerprints(in: fixture.database)
            let beforeFiles = try sourceFileFingerprints(in: fixture.root)

            let replay = coordinator.perform(candidateRequest)

            #expect(replay.error?.classification == .alreadyReviewed)
            #expect(!replay.changed)
            #expect(replay.actionReceiptID == nil)
            #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
            #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
            fixture.close()
        }
    }

    @Test("Receipt identity envelope and errors keep correction target path and evidence private")
    func replayBindingArtifactsAreContentFree() throws {
        let correctionSentinel = "RAW-CORRECTION-PRIVATE-7ab4"
        let targetSentinel = "/private/targets/PRIVATE-TARGET-42"
        let evidenceSentinel = "PRIVATE-EVIDENCE-DO-NOT-LOG-91cc"
        let fixture = try makeFixture(candidateID: "privacy-memory", evidence: evidenceSentinel)
        defer { fixture.close() }
        let request = request(
            for: fixture.output,
            surface: .journal,
            action: .correct,
            correction: correctionSentinel
        )
        let outcome = CiderReviewActionCoordinator(database: fixture.database).perform(request)
        let receipt = try #require(
            try SecondBrainActionReceiptLedgerService(database: fixture.database).inspect(id: outcome.actionReceiptID ?? "")
        )
        let targetRequest = journalRequest(
            expectedUpdatedAt: fixture.output.updatedAt,
            correction: correctionSentinel,
            target: targetSentinel
        )
        let targetReceiptID = JournalIntelligenceReviewActionService.actionReceiptID(
            for: targetRequest,
            actor: "privacy-test"
        )
        let stale = CiderReviewActionCoordinator(database: fixture.database).perform(request)
        let boundedText = [
            receipt.id,
            receipt.afterJSON ?? "",
            targetReceiptID,
            stale.message,
            stale.error?.message ?? "",
            JournalIntelligenceReviewActionError.targetUnavailable(targetSentinel).localizedDescription,
        ].joined(separator: "\n")

        #expect(!boundedText.contains(correctionSentinel))
        #expect(!boundedText.contains(targetSentinel))
        #expect(!boundedText.contains(evidenceSentinel))
        #expect(receipt.afterJSON?.contains("requestFingerprint") == true)
        #expect(receipt.afterJSON?.contains("resultingCandidateVersion") == true)
    }

    @Test("Writer failures are bounded private and leave disposable truth untouched")
    func writerFailureIsBoundedPrivateAndAtomic() throws {
        let fixture = try makeFixture(candidateID: "writer-failure")
        defer { fixture.close() }
        let privatePath = fixture.root.appendingPathComponent("private-source-token.txt").path
        let privateText = "PRIVATE JOURNAL EVIDENCE 8f8bf93b"
        let beforeTables = try allTableFingerprints(in: fixture.database)
        let beforeFiles = try sourceFileFingerprints(in: fixture.root)
        let coordinator = CiderReviewActionCoordinator { _, _ in
            throw NSError(
                domain: "writer",
                code: 71,
                userInfo: [NSLocalizedDescriptionKey: "failed at \(privatePath) with \(privateText)"]
            )
        }
        var privateRequest = request(for: fixture.output, surface: .home, action: .reject)
        privateRequest.identity.candidateRef = "memory_candidate:\(privatePath)-\(privateText)"

        let outcome = coordinator.perform(privateRequest)

        #expect(outcome.error?.classification == .writerFailure)
        #expect(outcome.error?.message.contains(privatePath) == false)
        #expect(outcome.error?.message.contains(privateText) == false)
        #expect(outcome.error?.message.count ?? 0 < 180)
        #expect(!outcome.changed)
        #expect(outcome.actionReceiptID == nil)
        let writerTablesAfter = try allTableFingerprints(in: fixture.database)
        let writerFilesAfter = try sourceFileFingerprints(in: fixture.root)
        #expect(writerTablesAfter == beforeTables)
        #expect(writerFilesAfter == beforeFiles)
        print("CID837-FINGERPRINT writer-failure tables=\(fingerprintDigest(beforeTables)) tableCount=\(beforeTables.count) files=\(fingerprintDigest(beforeFiles)) unchanged=true")

        let databaseCoordinator = CiderReviewActionCoordinator { _, _ in
            throw CiderDatabaseError.step("database failure at \(privatePath) with \(privateText)")
        }
        let databaseOutcome = databaseCoordinator.perform(
            request(for: fixture.output, surface: .journal, action: .reject)
        )
        #expect(databaseOutcome.error?.classification == .databaseFailure)
        #expect(databaseOutcome.error?.message.contains(privatePath) == false)
        #expect(databaseOutcome.error?.message.contains(privateText) == false)
        #expect(try allTableFingerprints(in: fixture.database) == beforeTables)
        #expect(try sourceFileFingerprints(in: fixture.root) == beforeFiles)
        print("CID837-FINGERPRINT database-failure tables=\(fingerprintDigest(beforeTables)) tableCount=\(beforeTables.count) files=\(fingerprintDigest(beforeFiles)) unchanged=true")
    }

    @Test("Exact retry survives reopen only while the current post-action version matches")
    func successSurvivesReopen() throws {
        let fixture = try makeFixture(candidateID: "reopen-memory")
        let root = fixture.root
        let databaseURL = fixture.databaseURL
        let candidateRequest = request(for: fixture.output, surface: .home, action: .approve)
        let expectedReceiptID = CiderReviewActionCoordinator(database: fixture.database).perform(candidateRequest).actionReceiptID
        fixture.database.close()

        let reopened = CiderDatabase()
        try reopened.open(at: databaseURL)
        defer {
            reopened.close()
            try? FileManager.default.removeItem(at: root)
        }
        let stored = try #require(
            try SecondBrainEnrichmentOutputService(database: reopened).output(id: "reopen-memory")
        )
        let beforeRetry = try allTableFingerprints(in: reopened)
        let retry = CiderReviewActionCoordinator(database: reopened).perform(candidateRequest)
        #expect(stored.reviewState == "accepted")
        #expect(retry.isSuccessful)
        #expect(!retry.changed)
        #expect(retry.actionReceiptID == expectedReceiptID)
        #expect(try scalarCount("action_receipts", in: reopened) == 1)
        #expect(try scalarCount("agent_actions", in: reopened) == 1)
        #expect(try allTableFingerprints(in: reopened) == beforeRetry)
        #expect(try SecondBrainActionReceiptLedgerService(database: reopened).inspect(id: expectedReceiptID ?? "")?.id == expectedReceiptID)
        print("CID837-REOPEN reviewState=\(stored.reviewState) receipt=\(expectedReceiptID ?? "missing") receiptRows=1 exactRetry=true")
    }

    @Test("Home reconciliation never loses a failed optimistic row")
    func homeReconciliationKeepsFailedRowAndClearsPendingState() {
        var state = HomeReviewActionState()
        let rowID = "review-cockpit-memory"
        state.begin(rowID: rowID)
        #expect(state.pendingReviewIDs == [rowID])

        state.reconcile(
            rowID: rowID,
            result: .failed(message: "Refresh this suggestion and try again.")
        )

        #expect(!state.resolvedReviewIDs.contains(rowID))
        #expect(!state.pendingReviewIDs.contains(rowID))
        #expect(state.errorMessage(for: rowID) == "Refresh this suggestion and try again.")

        state.begin(rowID: rowID)
        state.reconcile(rowID: rowID, result: .succeeded)
        #expect(state.resolvedReviewIDs.contains(rowID))
        #expect(!state.pendingReviewIDs.contains(rowID))
        #expect(state.errorMessage(for: rowID) == nil)
    }

    @Test("Production Home and Journal mutation call sites cannot bypass the coordinator")
    func productionCallSitesUseCoordinator() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let home = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"),
            encoding: .utf8
        )
        let journal = try String(
            contentsOf: root.appendingPathComponent("Sources/Cider/Views/JournalIntelligencePanelView.swift"),
            encoding: .utf8
        )

        #expect(home.contains("CiderReviewActionCoordinator"))
        #expect(!home.contains("CiderReviewCandidateActionService()"))
        #expect(journal.contains("CiderReviewActionCoordinator"))
        #expect(!journal.contains("JournalIntelligenceReviewActionService().perform"))
    }

    @Test("Production CLI graph and memory review actions use one typed coordinator adapter")
    func productionCLICallSitesUseCoordinatorAdapter() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let cli = try String(
            contentsOf: root.appendingPathComponent("Sources/CiderCLI/CiderCLI.swift"),
            encoding: .utf8
        )
        let adapterURL = root.appendingPathComponent("Sources/CiderCLI/CiderReviewCLIActionAdapter.swift")

        #expect(FileManager.default.fileExists(atPath: adapterURL.path))
        #expect(cli.contains("CiderReviewCLIActionAdapter"))
        #expect(!cli.contains("service.approveGraphCandidate("))
        #expect(!cli.contains("service.rejectGraphCandidate("))
        #expect(!cli.contains("service.deferGraphCandidate("))
        #expect(!cli.contains("service.approveMemoryCandidate("))
        #expect(!cli.contains("service.rejectMemoryCandidate("))
        #expect(!cli.contains("service.deferMemoryCandidate("))
    }

    private struct Fixture {
        var root: URL
        var databaseURL: URL
        var database: CiderDatabase
        var output: SecondBrainEnrichmentOutput

        @MainActor
        func close() {
            database.close()
            try? FileManager.default.removeItem(at: root)
        }
    }

    private func makeFixture(
        candidateID: String,
        exactEvidence: Bool = true,
        family: CiderReviewCandidateFamily = .memoryCandidate,
        evidence: String = "A private source-backed statement."
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sourceDirectory = root.appendingPathComponent("Daily", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sourceURL = sourceDirectory.appendingPathComponent("Journal.md")
        try evidence.write(to: sourceURL, atomically: true, encoding: .utf8)
        let databaseURL = root.appendingPathComponent("Cider.db")
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        let noteID = UUID()
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', 'Disposable Journal', ?, ?, NULL, 'Daily/Journal.md');
            """)
        item.bind(noteID.uuidString, at: 1)
            .bind(timestamp.timeIntervalSince1970, at: 2)
            .bind(timestamp.timeIntervalSince1970, at: 3)
        try item.step()
        let note = try database.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, NULL, 0);")
        note.bind(noteID.uuidString, at: 1).bind(evidence, at: 2)
        try note.step()

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        var output: SecondBrainEnrichmentOutput
        if family == .graphCandidate {
            output = try SecondBrainGraphCandidateContract.makeOutput(
                sourceOwner: owner,
                candidateKind: .objectRelation,
                mentionText: "Private Target",
                sourceQuote: evidence,
                sourceKind: "journal",
                objectTypeGuesses: [.place],
                relationGuesses: [.visited],
                confidence: 0.91,
                confidenceReason: "Disposable exact evidence backs this candidate.",
                source: "test.review.coordinator"
            )
            output.id = candidateID
            output.createdAt = timestamp
            output.updatedAt = timestamp.addingTimeInterval(1)
        } else {
            output = SecondBrainEnrichmentOutput(
                id: candidateID,
                owner: owner,
                kind: "memory_candidate",
                value: "A durable memory candidate.",
                normalizedValue: "a durable memory candidate.",
                label: "Memory candidate",
                evidence: evidence,
                source: "test.review.coordinator",
                confidence: 0.91,
                reviewState: "suggested",
                metadata: [
                    "memory_kind": "preference",
                    "candidate_kind": "preference",
                    "requires_review": "true",
                    "source_kind": "journal",
                    "source_quote": evidence,
                    "source_owner_ref": owner.canonicalRef,
                    "truth_boundary": "reviewable_candidate_not_truth",
                ],
                createdAt: timestamp,
                updatedAt: timestamp.addingTimeInterval(1)
            )
        }
        if exactEvidence {
            output.metadata["capture_event_id"] = "capture-\(candidateID)"
            output.metadata["source_span_start"] = "0"
            output.metadata["source_span_end"] = String(evidence.count)
        }
        let outputService = SecondBrainEnrichmentOutputService(database: database)
        try outputService.record(output)
        if family == .graphCandidate {
            let labels = SecondBrainOwnerLabelIndexService(database: database)
            _ = try labels.upsertLabel(
                owner: SecondBrainOwnerRef(ownerType: "place", ownerID: "target-a"),
                ownerKind: "place",
                canonicalLabel: "Private Target",
                sourceRefs: ["place:target-a"],
                labelSource: "test.review.coordinator"
            )
            _ = try labels.upsertLabel(
                owner: SecondBrainOwnerRef(ownerType: "place", ownerID: "target-b"),
                ownerKind: "place",
                canonicalLabel: "Private Target Annex",
                aliases: ["Private Target"],
                sourceRefs: ["place:target-b"],
                labelSource: "test.review.coordinator"
            )
        }
        let stored = try #require(try outputService.output(id: candidateID))
        return Fixture(root: root, databaseURL: databaseURL, database: database, output: stored)
    }

    private func graphTargetOptions(
        for output: SecondBrainEnrichmentOutput,
        in database: CiderDatabase
    ) throws -> [CiderGraphCandidateTargetOption] {
        let item = try #require(
            try CiderReviewQueueService(database: database)
                .list(limit: Int.max, includeDeferred: true)
                .items
                .first { $0.candidateRef == "graph_candidate:\(output.id)" }
        )
        return item.targetOptions
    }

    private func journalRequest(
        expectedUpdatedAt: Date,
        correction: String? = nil,
        target: String? = nil
    ) -> JournalIntelligenceReviewActionRequest {
        JournalIntelligenceReviewActionRequest(
            candidateRef: "memory_candidate:fingerprint-contract",
            family: "memory_candidate",
            expectedReviewState: "suggested",
            expectedUpdatedAt: expectedUpdatedAt,
            action: .correct,
            correctedValue: correction,
            targetOptionRef: target
        )
    }

    private func request(
        for output: SecondBrainEnrichmentOutput,
        surface: CiderReviewInvokingSurface,
        action: CiderReviewAction,
        correction: String? = nil,
        target: String? = nil
    ) -> CiderReviewActionRequest {
        CiderReviewActionRequest(
            identity: .init(candidateRef: "\(output.kind):\(output.id)", family: .init(rawValue: output.kind)),
            expectedVersion: .init(reviewState: output.reviewState, updatedAt: output.updatedAt),
            action: action,
            correction: correction,
            targetOptionRef: target,
            actor: "review-coordinator-test",
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

    private func allTableFingerprints(in database: CiderDatabase) throws -> [String: String] {
        let statement = try database.prepare("""
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name;
            """)
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
            let data = Data(rows.sorted().joined(separator: "\n").utf8)
            return (table, "count=\(rows.count);sha256=\(sha256(data))")
        })
    }

    private func sourceFileFingerprints(in root: URL) throws -> [String: String] {
        let files = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Daily"),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return try Dictionary(uniqueKeysWithValues: files.map { url in
            (url.lastPathComponent, sha256(try Data(contentsOf: url)))
        })
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fingerprintDigest(_ fingerprints: [String: String]) -> String {
        let canonical = fingerprints.keys.sorted().map { key in
            "\(key)=\(fingerprints[key] ?? "")"
        }.joined(separator: "\n")
        return sha256(Data(canonical.utf8))
    }
}
