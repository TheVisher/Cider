import CryptoKit
import Foundation
import Testing
@testable import Cider

@Suite("Cider Bookmark Enrichment Review Coordinator Tests")
@MainActor
struct CiderBookmarkEnrichmentReviewCoordinatorTests {
    private enum InjectedFailure: Error {
        case checkpoint
        case scheduler
    }
    @Test("Home full Review Queue and CLI schedule one exact enrichment action outcome")
    func supportedSurfacesShareExactSchedulingOutcome() throws {
        let bookmarkID = UUID(uuidString: "70E86B74-D2C5-4A57-A90C-AD7D9E92ECA0")!
        let updatedAt = Date(timeIntervalSinceReferenceDate: 123_456.75)
        let surfaces: [CiderReviewInvokingSurface] = [.home, .reviewQueue, .cli]
        var outcomes: [CiderReviewActionOutcome] = []

        for surface in surfaces {
            let fixture = try makeFixture(bookmarkID: bookmarkID, updatedAt: updatedAt)
            defer { fixture.close() }
            var scheduled: [(UUID, String)] = []
            let coordinator = CiderReviewActionCoordinator(
                database: fixture.database,
                enrichmentScheduler: { itemID, schedulingIdentity in
                    scheduled.append((itemID, schedulingIdentity))
                    return .scheduled
                },
                enrichmentScheduleCanceller: { _, _ in .identityNotFound }
            )

            let outcome = coordinator.perform(
                enrichmentRequest(bookmarkID: bookmarkID, updatedAt: updatedAt, surface: surface)
            )

            #expect(outcome.isSuccessful)
            #expect(outcome.action == .enrich)
            #expect(outcome.changed)
            #expect(outcome.resultingReviewState == "needs_review")
            #expect(outcome.mutationAuthority == .directUserAction)
            #expect(outcome.evidenceStatus == .verifiedExactEvidence)
            #expect(outcome.truthBoundary == "durable_enrichment_schedule_not_enrichment_completion")
            #expect(outcome.actionReceiptID != nil)
            #expect(scheduled.count == 1)
            #expect(scheduled.first?.0 == bookmarkID)
            outcomes.append(outcome)
        }

        let baseline = try #require(outcomes.first)
        #expect(outcomes.dropFirst().allSatisfy { baseline.isSemanticallyEquivalentMutation(to: $0) })
        #expect(Set(outcomes.compactMap(\.actionReceiptID)).count == 1)
    }

    @Test("Exact retry reuses one receipt audit and queued task")
    func exactRetryIsIdempotent() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        var scheduled: [(UUID, String)] = []
        let coordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { itemID, schedulingIdentity in
                if scheduled.contains(where: { $0.0 == itemID && $0.1 == schedulingIdentity }) {
                    return .reused
                }
                scheduled.append((itemID, schedulingIdentity))
                return .scheduled
            },
            enrichmentScheduleCanceller: { _, _ in .identityNotFound }
        )
        let request = enrichmentRequest(
            bookmarkID: fixture.bookmarkID,
            updatedAt: fixture.updatedAt,
            surface: .home
        )

        let first = coordinator.perform(request)
        var retry = request
        retry.surface = .cli
        let second = coordinator.perform(retry)

        #expect(first.isSuccessful)
        #expect(second.isSuccessful)
        #expect(first.changed)
        #expect(!second.changed)
        #expect(first.actionReceiptID == second.actionReceiptID)
        #expect(scheduled.count == 1)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try scalarCount("mutation_audit", in: fixture.database) == 1)
    }

    @Test("Reopen requeues one recovery attempt with the same durable receipt and no in-process duplicate")
    func reopenRequeuesOneRecoveryAttempt() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let request = enrichmentRequest(
            bookmarkID: fixture.bookmarkID,
            updatedAt: fixture.updatedAt,
            surface: .home
        )
        var firstProcessIdentities = Set<String>()
        let firstCoordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { _, identity in
                firstProcessIdentities.insert(identity)
                return .scheduled
            },
            enrichmentScheduleCanceller: { _, identity in
                firstProcessIdentities.remove(identity) != nil
                    ? .canceledScheduledTask
                    : .identityNotFound
            }
        )
        let first = firstCoordinator.perform(request)

        // A process restart loses the prior in-memory task but preserves the receipt.
        var reopenedProcessIdentities = Set<String>()
        var reopenedTaskCreations = 0
        let reopenedCoordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { _, identity in
                if reopenedProcessIdentities.insert(identity).inserted {
                    reopenedTaskCreations += 1
                    return .scheduled
                }
                return .reused
            },
            enrichmentScheduleCanceller: { _, identity in
                reopenedProcessIdentities.remove(identity) != nil
                    ? .canceledScheduledTask
                    : .identityNotFound
            }
        )
        var reopenedRequest = request
        reopenedRequest.surface = .reviewQueue
        let reopened = reopenedCoordinator.perform(reopenedRequest)
        reopenedRequest.surface = .cli
        let sameProcessRetry = reopenedCoordinator.perform(reopenedRequest)

        #expect(first.isSuccessful)
        #expect(reopened.isSuccessful)
        #expect(!reopened.changed)
        #expect(reopened.enrichmentQueueDisposition == .scheduled)
        #expect(sameProcessRetry.isSuccessful)
        #expect(!sameProcessRetry.changed)
        #expect(sameProcessRetry.enrichmentQueueDisposition == .reused)
        #expect(first.actionReceiptID == reopened.actionReceiptID)
        #expect(reopened.actionReceiptID == sameProcessRetry.actionReceiptID)
        #expect(reopenedTaskCreations == 1)
        #expect(reopenedProcessIdentities.count == 1)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try scalarCount("mutation_audit", in: fixture.database) == 1)
    }

    @Test("Stale missing ineligible and unauthorized scheduling leave every durable table and file unchanged")
    func invalidRequestsAreAtomic() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let sourceURL = fixture.root.appendingPathComponent("Inbox/Bookmarks/fixture.webloc")
        let cacheURL = fixture.root.appendingPathComponent(".cider/bookmarks/index.json")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("private source artifact".utf8).write(to: sourceURL)
        try Data("private cache artifact".utf8).write(to: cacheURL)
        var scheduledCount = 0
        let coordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { _, _ in scheduledCount += 1; return .scheduled },
            enrichmentScheduleCanceller: { _, _ in .identityNotFound }
        )

        var requests: [CiderReviewActionRequest] = []
        var stale = enrichmentRequest(bookmarkID: fixture.bookmarkID, updatedAt: .distantPast, surface: .home)
        stale.expectedVersion.reviewState = "needs_review"
        requests.append(stale)
        requests.append(enrichmentRequest(bookmarkID: UUID(), updatedAt: fixture.updatedAt, surface: .cli))
        var unauthorized = enrichmentRequest(bookmarkID: fixture.bookmarkID, updatedAt: fixture.updatedAt, surface: .cli)
        unauthorized.actor = "background-inference"
        requests.append(unauthorized)

        for request in requests {
            let tablesBefore = try allTableFingerprints(in: fixture.database)
            let filesBefore = try fileFingerprints(in: fixture.root)
            let outcome = coordinator.perform(request)
            #expect(!outcome.isSuccessful)
            #expect(!outcome.changed)
            #expect(outcome.actionReceiptID == nil)
            #expect(try allTableFingerprints(in: fixture.database) == tablesBefore)
            #expect(try fileFingerprints(in: fixture.root) == filesBefore)
        }

        let invalidURL = try fixture.database.prepare("UPDATE bookmarks SET url = 'not-a-source' WHERE item_id = ?;")
        invalidURL.bind(fixture.bookmarkID.uuidString, at: 1)
        try invalidURL.step()
        let tablesBefore = try allTableFingerprints(in: fixture.database)
        let filesBefore = try fileFingerprints(in: fixture.root)
        let ineligible = coordinator.perform(
            enrichmentRequest(bookmarkID: fixture.bookmarkID, updatedAt: fixture.updatedAt, surface: .reviewQueue)
        )
        #expect(ineligible.error?.classification == .missingExactEvidence)
        #expect(try allTableFingerprints(in: fixture.database) == tablesBefore)
        #expect(try fileFingerprints(in: fixture.root) == filesBefore)
        #expect(scheduledCount == 0)
    }

    @Test("Every partial scheduling checkpoint rolls back receipt audit queue and source caches")
    func partialFailuresRollbackCompletely() throws {
        for checkpoint in CiderBookmarkEnrichmentSchedulingCheckpoint.allCases {
            let fixture = try makeFixture()
            defer { fixture.close() }
            let sourceURL = fixture.root.appendingPathComponent("Inbox/Bookmarks/fixture.webloc")
            let cacheURL = fixture.root.appendingPathComponent(".cider/bookmarks/index.json")
            try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("private source artifact".utf8).write(to: sourceURL)
            try Data("private cache artifact".utf8).write(to: cacheURL)
            var activeSchedulingIdentities = Set<String>()
            var cancellationCount = 0
            let coordinator = CiderReviewActionCoordinator(
                database: fixture.database,
                enrichmentScheduler: { _, identity in
                    activeSchedulingIdentities.insert(identity)
                    return .scheduled
                },
                enrichmentScheduleCanceller: { _, identity in
                    guard activeSchedulingIdentities.remove(identity) != nil else {
                        return .identityNotFound
                    }
                    cancellationCount += 1
                    return .canceledScheduledTask
                },
                enrichmentFailureInjector: { reached in
                    if reached == checkpoint { throw InjectedFailure.checkpoint }
                }
            )
            let tablesBefore = try allTableFingerprints(in: fixture.database)
            let filesBefore = try fileFingerprints(in: fixture.root)

            let outcome = coordinator.perform(
                enrichmentRequest(bookmarkID: fixture.bookmarkID, updatedAt: fixture.updatedAt, surface: .home)
            )

            #expect(!outcome.isSuccessful)
            #expect(try allTableFingerprints(in: fixture.database) == tablesBefore)
            #expect(try fileFingerprints(in: fixture.root) == filesBefore)
            #expect(activeSchedulingIdentities.isEmpty)
            #expect(cancellationCount == (checkpoint == .afterScheduler ? 1 : 0))
        }
    }

    @Test("failed exact queue cleanup reports compensation failure without claiming atomic rollback")
    func failedQueueCleanupReportsCompensationFailure() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        var activeSchedulingIdentities = Set<String>()
        let tablesBefore = try allTableFingerprints(in: fixture.database)
        let coordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { _, identity in
                activeSchedulingIdentities.insert(identity)
                return .scheduled
            },
            enrichmentScheduleCanceller: { _, _ in .identityNotFound },
            enrichmentFailureInjector: { checkpoint in
                if checkpoint == .afterScheduler { throw InjectedFailure.checkpoint }
            }
        )

        let outcome = coordinator.perform(
            enrichmentRequest(
                bookmarkID: fixture.bookmarkID,
                updatedAt: fixture.updatedAt,
                surface: .cli
            )
        )

        #expect(outcome.error?.classification == .writerFailure)
        #expect(outcome.error?.message.contains("queue rollback is not claimed") == true)
        #expect(outcome.actionReceiptID == nil)
        #expect(try allTableFingerprints(in: fixture.database) == tablesBefore)
        #expect(activeSchedulingIdentities.count == 1)
    }

    @Test("SQLite write failure never reaches the scheduler and leaves durable state unchanged")
    func databaseFailureIsAtomic() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let trigger = try fixture.database.prepare("""
            CREATE TRIGGER fail_enrichment_receipt
            BEFORE INSERT ON action_receipts
            BEGIN
                SELECT RAISE(ABORT, 'injected receipt failure');
            END;
            """)
        try trigger.step()
        var scheduledCount = 0
        let coordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { _, _ in scheduledCount += 1; return .scheduled },
            enrichmentScheduleCanceller: { _, _ in .identityNotFound }
        )
        let tablesBefore = try allTableFingerprints(in: fixture.database)
        let outcome = coordinator.perform(
            enrichmentRequest(bookmarkID: fixture.bookmarkID, updatedAt: fixture.updatedAt, surface: .cli)
        )

        #expect(!outcome.isSuccessful)
        #expect(!outcome.changed)
        #expect(outcome.actionReceiptID == nil)
        #expect(scheduledCount == 0)
        #expect(try allTableFingerprints(in: fixture.database) == tablesBefore)
    }

    @Test("Canonical compensation prevents delayed queued work and permits one exact clean retry")
    func canonicalSchedulerCompensationPreventsDelayedMutation() async throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let sourceURL = fixture.root.appendingPathComponent("Inbox/Bookmarks/fixture.webloc")
        let sidecarURL = fixture.root.appendingPathComponent("Inbox/Bookmarks/fixture.webloc.cider.json")
        let cacheURL = fixture.root.appendingPathComponent(".cider/bookmarks/_cider_bookmarks_index.json")
        let thumbnailURL = fixture.root.appendingPathComponent(
            ".cider/bookmarks/.thumbnails/\(fixture.bookmarkID.uuidString).png"
        )
        let originalURL = fixture.root.appendingPathComponent(
            ".cider/bookmarks/.originals/\(fixture.bookmarkID.uuidString).jpg"
        )
        for url in [sourceURL, sidecarURL, cacheURL, thumbnailURL, originalURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("fixture artifact: \(url.lastPathComponent)".utf8).write(to: url)
        }
        var downstreamAISchedulingCount = 0
        let bookmarkService = VaultBookmarkService(
            database: fixture.database,
            schedulesEnrichment: true,
            writesVaultCaches: true,
            vaultRootOverride: fixture.root,
            enrichmentPayloadFetcher: { _ in nil },
            aiEnrichmentScheduler: { _ in downstreamAISchedulingCount += 1 }
        )
        bookmarkService.loadBookmarksFromDatabase(fixture.database)
        let tablesBefore = try allTableFingerprints(in: fixture.database)
        let filesBefore = try fileFingerprints(in: fixture.root)
        let bookmarkBefore = try #require(
            bookmarkService.bookmarks.first { $0.id == fixture.bookmarkID }
        )
        let taskStateBefore = bookmarkService._enrichmentTaskStateForTesting(
            bookmarkID: fixture.bookmarkID
        )
        var failedSchedulingIdentity: String?
        let failingCoordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            bookmarkService: bookmarkService,
            enrichmentFailureInjector: { checkpoint in
                if checkpoint == .afterScheduler {
                    failedSchedulingIdentity = bookmarkService
                        ._enrichmentTaskStateForTesting(bookmarkID: fixture.bookmarkID)
                        .schedulingIdentity
                    throw InjectedFailure.checkpoint
                }
            }
        )
        let request = enrichmentRequest(
            bookmarkID: fixture.bookmarkID,
            updatedAt: fixture.updatedAt,
            surface: .home
        )

        let failed = failingCoordinator.perform(request)
        await Task.yield()
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(!failed.isSuccessful)
        #expect(failed.actionReceiptID == nil)
        #expect(failedSchedulingIdentity != nil)
        #expect(bookmarkService.bookmarks.first { $0.id == fixture.bookmarkID } == bookmarkBefore)
        #expect(try allTableFingerprints(in: fixture.database) == tablesBefore)
        #expect(try fileFingerprints(in: fixture.root) == filesBefore)
        #expect(
            bookmarkService._enrichmentTaskStateForTesting(bookmarkID: fixture.bookmarkID)
                == taskStateBefore
        )
        #expect(downstreamAISchedulingCount == 0)

        let retryCoordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            bookmarkService: bookmarkService
        )
        let retry = retryCoordinator.perform(request)
        #expect(retry.isSuccessful)
        #expect(retry.changed)
        #expect(retry.enrichmentQueueDisposition == .scheduled)
        #expect(retry.actionReceiptID == failedSchedulingIdentity)
        let retryTaskState = bookmarkService._enrichmentTaskStateForTesting(
            bookmarkID: fixture.bookmarkID
        )
        #expect(retryTaskState.taskCount == 1)
        #expect(retryTaskState.hasTask)
        #expect(retryTaskState.taskIsCancelled == false)
        #expect(retryTaskState.schedulingIdentity == retry.actionReceiptID)
        #expect(retryTaskState.schedulingOrigin == .scheduled)
        let tablesAfterRetry = try allTableFingerprints(in: fixture.database)
        let filesAfterRetry = try fileFingerprints(in: fixture.root)

        let receiptID = try #require(retry.actionReceiptID)
        let cancellation = bookmarkService.cancelReviewEnrichment(
            for: fixture.bookmarkID,
            schedulingIdentity: receiptID
        )
        #expect(cancellation == .canceledScheduledTask)
        await Task.yield()
        try await Task.sleep(nanoseconds: 150_000_000)

        #expect(bookmarkService.bookmarks.first { $0.id == fixture.bookmarkID } == bookmarkBefore)
        #expect(
            bookmarkService._enrichmentTaskStateForTesting(bookmarkID: fixture.bookmarkID)
                == taskStateBefore
        )
        #expect(try allTableFingerprints(in: fixture.database) == tablesAfterRetry)
        #expect(try fileFingerprints(in: fixture.root) == filesAfterRetry)
        #expect(downstreamAISchedulingCount == 0)
    }

    @Test("Adopted automatic work detaches the temporary review identity without canceling the task")
    func adoptedAutomaticWorkDetachesWithoutCancellation() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        let bookmarkService = VaultBookmarkService(
            database: fixture.database,
            schedulesEnrichment: true,
            writesVaultCaches: false,
            vaultRootOverride: fixture.root,
            enrichmentPayloadFetcher: { _ in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            },
            aiEnrichmentScheduler: { _ in }
        )
        bookmarkService.loadBookmarksFromDatabase(fixture.database)
        bookmarkService.refetchMetadata(for: fixture.bookmarkID)
        let automaticTask = bookmarkService._enrichmentTaskStateForTesting(
            bookmarkID: fixture.bookmarkID
        )
        let schedulingIdentity = "temporary-review-identity"

        let disposition = try bookmarkService.scheduleReviewEnrichment(
            for: fixture.bookmarkID,
            schedulingIdentity: schedulingIdentity
        )
        let adoptedTask = bookmarkService._enrichmentTaskStateForTesting(
            bookmarkID: fixture.bookmarkID
        )
        let cancellation = bookmarkService.cancelReviewEnrichment(
            for: fixture.bookmarkID,
            schedulingIdentity: schedulingIdentity
        )
        let detachedTask = bookmarkService._enrichmentTaskStateForTesting(
            bookmarkID: fixture.bookmarkID
        )

        #expect(disposition == .adopted)
        #expect(adoptedTask.taskToken == automaticTask.taskToken)
        #expect(adoptedTask.schedulingIdentity == schedulingIdentity)
        #expect(adoptedTask.schedulingOrigin == .adopted)
        #expect(cancellation == .detachedAdoptedTask)
        #expect(detachedTask.taskToken == automaticTask.taskToken)
        #expect(detachedTask.hasTask)
        #expect(detachedTask.taskIsCancelled == false)
        #expect(detachedTask.schedulingIdentity == nil)
        #expect(detachedTask.schedulingOrigin == nil)

        bookmarkService._cancelAllEnrichmentTasksForTesting()
    }

    @Test("Changed version never replays an earlier receipt and private content never enters receipt or audit")
    func changedVersionAndPrivacyBoundary() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }
        var scheduledCount = 0
        let coordinator = CiderReviewActionCoordinator(
            database: fixture.database,
            enrichmentScheduler: { _, _ in scheduledCount += 1; return .scheduled },
            enrichmentScheduleCanceller: { _, _ in .identityNotFound }
        )
        let request = enrichmentRequest(
            bookmarkID: fixture.bookmarkID,
            updatedAt: fixture.updatedAt,
            surface: .home
        )
        let first = coordinator.perform(request)
        let changedAt = fixture.updatedAt.addingTimeInterval(1)
        let update = try fixture.database.prepare("UPDATE items SET updated_at = ? WHERE id = ?;")
        update.bind(changedAt.timeIntervalSince1970, at: 1)
            .bind(fixture.bookmarkID.uuidString, at: 2)
        try update.step()
        let staleRetry = coordinator.perform(request)

        #expect(first.isSuccessful)
        #expect(staleRetry.error?.classification == .staleExpectedVersion)
        #expect(scheduledCount == 1)
        #expect(try scalarCount("action_receipts", in: fixture.database) == 1)
        #expect(try scalarCount("mutation_audit", in: fixture.database) == 1)
        let receiptText = try concatenatedColumns(
            "SELECT source_refs_json, evidence_refs_json, before_json, after_json, receipt_json FROM action_receipts;",
            columnCount: 5,
            database: fixture.database
        )
        let auditText = try concatenatedColumns(
            "SELECT before_state, after_state, metadata FROM mutation_audit;",
            columnCount: 3,
            database: fixture.database
        )
        for privateValue in ["Private title excluded from receipts", "https://example.com/private-path", "private notes", "fixture.webloc"] {
            #expect(!receiptText.contains(privateValue))
            #expect(!auditText.contains(privateValue))
        }
    }

    @Test("Scheduled UI outcomes keep the exact row visible and failures attach a bounded row error")
    func uiRowReconciliation() {
        var state = HomeReviewActionState()
        state.begin(rowID: "exact-enrichment-row")
        state.reconcile(rowID: "exact-enrichment-row", result: .scheduled)
        #expect(!state.resolvedReviewIDs.contains("exact-enrichment-row"))
        #expect(state.errorMessage(for: "exact-enrichment-row") == nil)

        state.begin(rowID: "failed-enrichment-row")
        state.reconcile(
            rowID: "failed-enrichment-row",
            result: .failed(message: "Refresh this exact bookmark row and retry enrichment.")
        )
        #expect(!state.resolvedReviewIDs.contains("failed-enrichment-row"))
        #expect(state.errorMessage(for: "failed-enrichment-row") == "Refresh this exact bookmark row and retry enrichment.")
    }

    @Test("Production enrichment surfaces cannot bypass the coordinator and the coordinator is not a queue writer")
    func productionSourceGuards() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let queueSource = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Services/CiderReviewQueueService.swift"), encoding: .utf8)
        let coordinatorSource = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Services/CiderReviewActionCoordinator.swift"), encoding: .utf8)
        let panelSource = try String(contentsOf: root.appendingPathComponent("Sources/Cider/Views/CiderPanelView+ContentArea.swift"), encoding: .utf8)
        let cliSource = try String(contentsOf: root.appendingPathComponent("Sources/CiderCLI/CiderCLI.swift"), encoding: .utf8)

        #expect(queueSource.contains("enrichmentActionCoordinator.perform("))
        #expect(!queueSource.contains("VaultBookmarkService.shared.refetchMetadata"))
        #expect(!panelSource.contains("refetchMetadata(for:"))
        #expect(cliSource.contains("action: \"bookmark.refetch\""))
        #expect(coordinatorSource.contains("CiderBookmarkEnrichmentReviewActionAdapter"))
        #expect(!coordinatorSource.contains("INSERT INTO action_receipts"))
        #expect(!coordinatorSource.contains("enrichmentTasks"))
        #expect(!coordinatorSource.contains("refetchMetadata(for:"))
    }

    private func enrichmentRequest(
        bookmarkID: UUID,
        updatedAt: Date,
        surface: CiderReviewInvokingSurface
    ) -> CiderReviewActionRequest {
        CiderReviewActionRequest(
            identity: .init(candidateRef: "enrichment:\(bookmarkID.uuidString)", family: .enrichment),
            expectedVersion: .init(reviewState: "needs_review", updatedAt: updatedAt),
            action: .enrich,
            enrichmentItemID: bookmarkID,
            actor: "agent",
            surface: surface,
            exactEvidenceRequirement: .required,
            mutationAuthority: .directUserAction
        )
    }

    private func makeFixture(
        bookmarkID: UUID = UUID(),
        updatedAt: Date = Date(timeIntervalSinceReferenceDate: 45_678.125)
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-enrichment-review-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let databaseURL = root.appendingPathComponent("Cider.sqlite")
        let database = CiderDatabase()
        try database.open(at: databaseURL)
        try database.withTransaction {
            let item = try database.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
                VALUES (?, 'bookmark', 'Private title excluded from receipts', ?, ?, 'Inbox/Bookmarks/fixture.webloc');
                """)
            item.bind(bookmarkID.uuidString, at: 1)
                .bind(updatedAt.addingTimeInterval(-1).timeIntervalSince1970, at: 2)
                .bind(updatedAt.timeIntervalSince1970, at: 3)
            try item.step()
            let bookmark = try database.prepare("""
                INSERT INTO bookmarks (item_id, url, notes, enrichment_status, last_enriched_at)
                VALUES (?, 'https://example.com/private-path', 'private notes', 'failed', NULL);
                """)
            bookmark.bind(bookmarkID.uuidString, at: 1)
            try bookmark.step()
        }
        return Fixture(root: root, database: database, bookmarkID: bookmarkID, updatedAt: updatedAt)
    }

    private func scalarCount(_ table: String, in database: CiderDatabase) throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
        guard try statement.step() else { return 0 }
        return statement.int(at: 0)
    }

    private func allTableFingerprints(in database: CiderDatabase) throws -> [String: String] {
        let tableStatement = try database.prepare("""
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
            ORDER BY name;
            """)
        var tables: [String] = []
        while try tableStatement.step() { tables.append(tableStatement.string(at: 0)) }
        return try Dictionary(uniqueKeysWithValues: tables.map { table in
            let pragma = try database.prepare("PRAGMA table_info(\(table));")
            var columns: [String] = []
            while try pragma.step() { columns.append(pragma.string(at: 1)) }
            let pairs = columns.flatMap { ["'\($0)'", "quote(\"\($0)\")"] }.joined(separator: ", ")
            let statement = try database.prepare("SELECT json_object(\(pairs)) FROM \(table);")
            var rows: [String] = []
            while try statement.step() { rows.append(statement.string(at: 0)) }
            return (table, "count=\(rows.count);sha256=\(sha256(rows.sorted().joined(separator: "\n")))")
        })
    }

    private func fileFingerprints(in root: URL) throws -> [String: String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: []
        ) else { return [:] }
        var result: [String: String] = [:]
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
            guard relative.hasPrefix("Inbox/Bookmarks/") || relative.hasPrefix(".cider/bookmarks/") else { continue }
            result[relative] = sha256(try Data(contentsOf: fileURL))
        }
        return result
    }

    private func concatenatedColumns(
        _ sql: String,
        columnCount: Int,
        database: CiderDatabase
    ) throws -> String {
        let statement = try database.prepare(sql)
        var values: [String] = []
        while try statement.step() {
            for index in 0..<columnCount {
                values.append(statement.optionalString(at: Int32(index)) ?? "")
            }
        }
        return values.joined(separator: "\n")
    }

    private func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private struct Fixture {
        let root: URL
        let database: CiderDatabase
        let bookmarkID: UUID
        let updatedAt: Date

        @MainActor
        func close() {
            database.close()
            try? FileManager.default.removeItem(at: root)
        }
    }
}
