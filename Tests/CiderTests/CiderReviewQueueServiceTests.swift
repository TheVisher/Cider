import Foundation
import Testing
@testable import Cider

@Suite("Cider Review Queue Service Tests")
@MainActor
struct CiderReviewQueueServiceTests {
    private func makeTempDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-review-queue-test-\(UUID().uuidString).db")
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(atPath: url.path + "-wal")
        try? fm.removeItem(atPath: url.path + "-shm")
    }

    private func insertBookmark(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        title: String = "Example",
        url: String = "https://example.com",
        folderID: UUID? = nil,
        relativePath: String = "Inbox/Bookmarks/Example.webloc",
        enrichmentStatus: String? = "complete",
        lastEnrichedAt: Date? = Date()
    ) throws -> UUID {
        try db.withTransaction {
            let item = try db.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, 'bookmark', ?, ?, ?, ?, ?);
                """)
            item.bind(id.uuidString, at: 1)
                .bind(title, at: 2)
                .bind(Date().timeIntervalSince1970, at: 3)
                .bind(Date().timeIntervalSince1970, at: 4)
                .bind(folderID?.uuidString, at: 5)
                .bind(relativePath, at: 6)
            try item.step()

            let bookmark = try db.prepare("""
                INSERT INTO bookmarks (
                    item_id, url, notes, notes_manually_set, title_manually_set,
                    enrichment_status, last_enriched_at
                ) VALUES (?, ?, '', 0, 0, ?, ?);
                """)
            bookmark.bind(id.uuidString, at: 1)
                .bind(url, at: 2)
                .bind(enrichmentStatus, at: 3)
                .bind(lastEnrichedAt.map { $0.timeIntervalSince1970 }, at: 4)
            try bookmark.step()
        }
        return id
    }

    @Test("review queue lists low-confidence routing once and exposes safe actions")
    func reviewQueueListsLowConfidenceRouting() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(db, enrichmentStatus: "complete", lastEnrichedAt: Date())
        let routing = CiderRoutingDecisionService(database: db)
        let decision = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0,
            reason: "No deterministic route was supplied.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )

        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)
        let result = try queue.list()

        #expect(result.command == "review.list")
        #expect(result.items.count == 1)
        #expect(result.items[0].itemID == itemID)
        #expect(result.items[0].kind == "low_confidence_routing")
        #expect(result.items[0].source == "routing_decision")
        #expect(result.items[0].routingDecisionID == decision.id)
        #expect(result.items[0].reviewState == "needs_review")
        #expect(result.items[0].safeActions == ["approve", "correct", "defer"])
    }

    @Test("review queue approve and defer remove active routing items while preserving deferred history")
    func approveAndDeferRemoveActiveRoutingItems() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(db, enrichmentStatus: "complete", lastEnrichedAt: Date())
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0,
            reason: "No deterministic route was supplied.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        _ = try queue.deferReview(itemID: itemID, reason: "Not enough context yet.")
        #expect(try queue.list().items.isEmpty)

        let deferred = try queue.list(includeDeferred: true)
        #expect(deferred.items.count == 1)
        #expect(deferred.items[0].reviewState == "deferred")
        #expect(deferred.items[0].reason == "Not enough context yet.")

        _ = try queue.approve(itemID: itemID)
        #expect(try queue.list(includeDeferred: true).items.isEmpty)
    }

    @Test("review routing actions return durable result payloads and audit provenance")
    func reviewRoutingActionsReturnDurableResultPayloadsAndAuditProvenance() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(db, title: "Route Review", enrichmentStatus: "complete", lastEnrichedAt: Date())
        let routing = CiderRoutingDecisionService(database: db)
        let original = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.2,
            reason: "Low confidence route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        let result = try queue.approve(itemID: itemID, actor: "agent")

        #expect(result.action == "review.routing.approve")
        #expect(result.itemID == itemID)
        #expect(result.itemType == "bookmark")
        #expect(result.title == "Route Review")
        #expect(result.status == "accepted")
        #expect(result.actor == "agent")
        #expect(result.reviewState == "accepted")
        #expect(result.target.relativePath == "Inbox/Bookmarks")
        #expect(result.supersedesDecisionID == original.id)
        #expect(result.routingDecisionID != original.id)
        #expect(result.remainingActiveRoutingReviewCount == 0)
        #expect(result.safeActions.contains("review summary"))
        #expect(try queue.summary().countsByKind["low_confidence_routing"] == nil)

        let audit = MutationAuditService(database: db).loadEntries().first {
            $0.itemID == itemID && $0.action == "review.routing.approve"
        }
        #expect(audit?.source == .agent)
        #expect(audit?.beforeState["reviewState"] == "needs_review")
        #expect(audit?.afterState["reviewState"] == "accepted")
        #expect(audit?.metadata["supersedesDecisionID"] == original.id.uuidString)
        #expect(audit?.metadata["routingDecisionID"] == result.routingDecisionID.uuidString)

        let dictionary = result.toDictionary()
        #expect(dictionary["action"] as? String == "review.routing.approve")
        #expect(dictionary["status"] as? String == "accepted")
        #expect(dictionary["remainingActiveRoutingReviewCount"] as? Int == 0)
    }

    @Test("review routing defer returns durable result payload and preserves deferred history")
    func reviewRoutingDeferReturnsDurableResultPayloadAndPreservesDeferredHistory() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(db, title: "Later Route", enrichmentStatus: "complete", lastEnrichedAt: Date())
        let routing = CiderRoutingDecisionService(database: db)
        let original = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.1,
            reason: "Needs manual destination.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        let result = try queue.deferReview(itemID: itemID, reason: "Waiting for better context.", actor: "agent")

        #expect(result.action == "review.routing.defer")
        #expect(result.status == "deferred")
        #expect(result.reviewState == "deferred")
        #expect(result.supersedesDecisionID == original.id)
        #expect(result.remainingActiveRoutingReviewCount == 0)
        #expect(try queue.list().items.isEmpty)
        let deferred = try queue.list(includeDeferred: true).items
        #expect(deferred.map(\.itemID) == [itemID])
        #expect(deferred[0].reason == "Waiting for better context.")

        let audit = MutationAuditService(database: db).loadEntries().first {
            $0.itemID == itemID && $0.action == "review.routing.defer"
        }
        #expect(audit?.source == .agent)
        #expect(audit?.beforeState["reviewState"] == "needs_review")
        #expect(audit?.afterState["reviewState"] == "deferred")
        #expect(audit?.metadata["routingDecisionID"] == result.routingDecisionID.uuidString)
    }

    @Test("deferred routing keeps pending enrichment from re-surfacing the same item")
    func deferredRoutingSuppressesDerivedItemsForSameBookmark() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(db, enrichmentStatus: "pending", lastEnrichedAt: nil)
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0,
            reason: "No deterministic route was supplied.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        _ = try queue.deferReview(itemID: itemID, reason: "Wait for a human choice.")

        #expect(try queue.list().items.isEmpty)
        let deferred = try queue.list(includeDeferred: true)
        #expect(deferred.items.count == 1)
        #expect(deferred.items[0].kind == "deferred_routing")
    }

    @Test("review queue includes enrichment and inbox backlog items without routing decisions")
    func reviewQueueIncludesDerivedBookmarkIssues() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let enrichmentID = try insertBookmark(
            db,
            title: "Generic",
            relativePath: "Inbox/Bookmarks/Generic.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let inboxID = try insertBookmark(
            db,
            title: "Needs Filing",
            url: "https://example.com/file-me",
            relativePath: "Inbox/Bookmarks/Needs Filing.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let queue = CiderReviewQueueService(database: db)

        let items = try queue.list().items

        #expect(items.map(\.itemID).contains(enrichmentID))
        #expect(items.map(\.itemID).contains(inboxID))
        #expect(items.first { $0.itemID == enrichmentID }?.kind == "enrichment")
        #expect(items.first { $0.itemID == enrichmentID }?.suggestedAction == "Enrichment failed")
        #expect(items.first { $0.itemID == inboxID }?.kind == "inbox_backlog")
    }

    @Test("review queue filters by kind and required safe action")
    func reviewQueueFiltersByKindAndRequiredSafeAction() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let enrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata",
            relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let inboxID = try insertBookmark(
            db,
            title: "Needs Filing",
            url: "https://example.com/file-me",
            relativePath: "Inbox/Bookmarks/Needs Filing.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let queue = CiderReviewQueueService(database: db)

        let enrichmentItems = try queue.list(kind: "enrichment").items
        let enrichableItems = try queue.list(requiredSafeAction: "enrich").items
        let correctableItems = try queue.list(requiredSafeAction: "correct").items

        #expect(enrichmentItems.map(\.itemID) == [enrichmentID])
        #expect(enrichableItems.map(\.itemID) == [enrichmentID])
        #expect(correctableItems.map(\.itemID).contains(enrichmentID))
        #expect(correctableItems.map(\.itemID).contains(inboxID))
    }

    @Test("review queue summary counts mixed queue composition")
    func reviewQueueSummaryCountsMixedQueueComposition() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let routingID = try insertBookmark(db, title: "Route Me", enrichmentStatus: "complete", lastEnrichedAt: Date())
        let enrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata",
            relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let inboxID = try insertBookmark(
            db,
            title: "Needs Filing",
            url: "https://example.com/file-me",
            relativePath: "Inbox/Bookmarks/Needs Filing.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: routingID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.1,
            reason: "Needs a human route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        let summary = try queue.summary()

        #expect(summary.totalCount == 3)
        #expect(summary.countsByKind["low_confidence_routing"] == 1)
        #expect(summary.countsByKind["enrichment"] == 1)
        #expect(summary.countsByKind["inbox_backlog"] == 1)
        #expect(summary.countsByItemType["bookmark"] == 3)
        #expect(summary.countsByReviewState["needs_review"] == 3)
        #expect(summary.countsBySafeAction["approve"] == 1)
        #expect(summary.countsBySafeAction["enrich"] == 1)
        #expect(summary.countsBySafeAction["correct"] == 3)
        #expect(summary.countsBySafeAction["defer"] == 3)
        #expect(summary.toDictionary()["totalCount"] as? Int == 3)
        _ = enrichmentID
        _ = inboxID
    }

    @Test("review queue summary groups actionable work and previews batch enrichment")
    func reviewQueueSummaryGroupsActionableWorkAndPreviewsBatchEnrichment() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let routingID = try insertBookmark(db, title: "Route Me", enrichmentStatus: "complete", lastEnrichedAt: Date())
        let firstEnrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata A",
            relativePath: "Inbox/Bookmarks/Needs Metadata A.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let secondEnrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata B",
            relativePath: "Inbox/Bookmarks/Needs Metadata B.webloc",
            enrichmentStatus: "pending",
            lastEnrichedAt: nil
        )
        let inboxID = try insertBookmark(
            db,
            title: "Needs Filing",
            url: "https://example.com/file-me",
            relativePath: "Inbox/Bookmarks/Needs Filing.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: routingID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.1,
            reason: "Needs a human route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        let summary = try queue.summary()

        #expect(summary.groups.map(\.id) == [
            "low_confidence_routing:needs_review:approve:bookmark",
            "enrichment:needs_review:enrich:bookmark",
            "enrichment:pending:enrich:bookmark",
            "inbox_backlog:needs_review:correct:bookmark",
        ])
        #expect(summary.groups.first { $0.id == "low_confidence_routing:needs_review:approve:bookmark" }?.count == 1)
        #expect(summary.groups.first { $0.id == "enrichment:needs_review:enrich:bookmark" }?.count == 1)
        #expect(summary.groups.first { $0.id == "enrichment:pending:enrich:bookmark" }?.sampleItems.first?.itemID == secondEnrichmentID)
        #expect(summary.batchEnrichmentPreview.action == "review.enrich")
        #expect(summary.batchEnrichmentPreview.isMutating == false)
        #expect(summary.batchEnrichmentPreview.candidateCount == 2)
        #expect(summary.batchEnrichmentPreview.candidateSamples.map(\.itemID) == [firstEnrichmentID, secondEnrichmentID])
        #expect(summary.batchEnrichmentPreview.excludedCount == 2)
        #expect(summary.batchEnrichmentPreview.exclusionsByReason["routing_requires_explicit_approval"] == 1)
        #expect(summary.batchEnrichmentPreview.exclusionsByReason["manual_routing_required"] == 1)
        let dictionary = summary.toDictionary()
        #expect((dictionary["groups"] as? [[String: Any]])?.count == 4)
        #expect((dictionary["batchEnrichmentPreview"] as? [String: Any])?["candidateCount"] as? Int == 2)
        _ = inboxID
    }

    @Test("review lane drilldown returns bounded items for summary groups")
    func reviewLaneDrilldownReturnsBoundedItemsForSummaryGroups() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let enrichmentIDs = try (0..<4).map { index in
            try insertBookmark(
                db,
                title: "Needs Metadata \(index)",
                relativePath: "Inbox/Bookmarks/Needs Metadata \(index).webloc",
                enrichmentStatus: "pending",
                lastEnrichedAt: nil
            )
        }
        let routingID = try insertBookmark(
            db,
            title: "Needs Routing",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: routingID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.15,
            reason: "Needs explicit destination.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        let enrichmentLane = try queue.drilldown(
            groupID: "enrichment:pending:enrich:bookmark",
            limit: 2
        )
        #expect(enrichmentLane.command == "review.drilldown")
        #expect(enrichmentLane.groupID == "enrichment:pending:enrich:bookmark")
        #expect(enrichmentLane.kind == "enrichment")
        #expect(enrichmentLane.reviewState == "pending")
        #expect(enrichmentLane.requiredSafeAction == "enrich")
        #expect(enrichmentLane.totalCount == 4)
        #expect(enrichmentLane.items.count == 2)
        #expect(enrichmentLane.hasMore == true)
        #expect(enrichmentLane.items.map(\.itemID) == Array(enrichmentIDs.prefix(2)))
        #expect(enrichmentLane.items.allSatisfy { $0.safeActions.contains("enrich") })

        let routingLane = try queue.drilldown(
            groupID: "low_confidence_routing:needs_review:approve:bookmark",
            limit: 10
        )
        #expect(routingLane.totalCount == 1)
        #expect(routingLane.hasMore == false)
        #expect(routingLane.items.map(\.itemID) == [routingID])
        #expect(routingLane.items[0].target?.relativePath == "Inbox/Bookmarks")
        #expect(routingLane.items[0].safeActions == ["approve", "correct", "defer"])

        let dictionary = enrichmentLane.toDictionary()
        #expect(dictionary["command"] as? String == "review.drilldown")
        #expect(dictionary["groupID"] as? String == "enrichment:pending:enrich:bookmark")
        #expect(dictionary["totalCount"] as? Int == 4)
        #expect(dictionary["count"] as? Int == 2)
        #expect(dictionary["hasMore"] as? Bool == true)
    }

    @Test("review queue batch enrichment preview caps sample payload while preserving candidate count")
    func reviewQueueBatchEnrichmentPreviewCapsSamplePayload() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        var enrichmentIDs: [UUID] = []
        for index in 1...7 {
            let id = try insertBookmark(
                db,
                title: "Needs Metadata \(index)",
                relativePath: "Inbox/Bookmarks/Needs Metadata \(index).webloc",
                enrichmentStatus: "failed",
                lastEnrichedAt: nil
            )
            enrichmentIDs.append(id)
        }
        let queue = CiderReviewQueueService(database: db)

        let summary = try queue.summary(batchEnrichmentSampleLimit: 3)
        let dictionary = summary.toDictionary()
        let previewDictionary = try #require(dictionary["batchEnrichmentPreview"] as? [String: Any])

        #expect(summary.batchEnrichmentPreview.candidateCount == 7)
        #expect(summary.batchEnrichmentPreview.candidateSampleLimit == 3)
        #expect(summary.batchEnrichmentPreview.candidateSamples.map(\.itemID) == Array(enrichmentIDs.prefix(3)))
        #expect(summary.batchEnrichmentPreview.candidateSamples.count == 3)
        #expect(previewDictionary["candidateCount"] as? Int == 7)
        #expect(previewDictionary["candidateSampleLimit"] as? Int == 3)
        #expect((previewDictionary["candidateSamples"] as? [[String: Any]])?.count == 3)
        #expect(previewDictionary["candidates"] == nil)
    }

    @Test("review queue enrich action schedules bookmark enrichment")
    func reviewQueueEnrichActionSchedulesBookmarkEnrichment() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let bookmarkID = try insertBookmark(
            db,
            title: "Needs Metadata",
            relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        var scheduledIDs: [UUID] = []
        let queue = CiderReviewQueueService(
            database: db,
            enrichmentScheduler: { scheduledIDs.append($0) }
        )

        let result = try queue.enrich(itemID: bookmarkID, actor: "agent")

        #expect(scheduledIDs == [bookmarkID])
        #expect(result.action == "review.enrich")
        #expect(result.itemID == bookmarkID)
        #expect(result.itemType == "bookmark")
        #expect(result.status == "scheduled")
        #expect(result.actor == "agent")
        #expect(result.safeActions.contains("review list"))
        #expect(result.safeActions.contains("bookmark get"))
    }

    @Test("review queue enrich action rejects bookmarks without enrichment issue")
    func reviewQueueEnrichActionRejectsCompleteBookmarks() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let bookmarkID = try insertBookmark(
            db,
            title: "Complete Metadata",
            relativePath: "Inbox/Bookmarks/Complete Metadata.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        var scheduledIDs: [UUID] = []
        let queue = CiderReviewQueueService(
            database: db,
            enrichmentScheduler: { scheduledIDs.append($0) }
        )

        #expect(throws: CiderReviewQueueActionError.self) {
            _ = try queue.enrich(itemID: bookmarkID, actor: "agent")
        }
        #expect(scheduledIDs.isEmpty)
    }

    @Test("review queue batch enrichment schedules eligible bookmarks and reports exclusions")
    func reviewQueueBatchEnrichmentSchedulesEligibleBookmarksAndReportsExclusions() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let firstEnrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata A",
            relativePath: "Inbox/Bookmarks/Needs Metadata A.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let secondEnrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata B",
            relativePath: "Inbox/Bookmarks/Needs Metadata B.webloc",
            enrichmentStatus: "pending",
            lastEnrichedAt: nil
        )
        let routingID = try insertBookmark(
            db,
            title: "Needs Routing",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: routingID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.1,
            reason: "Needs a human route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        var scheduledIDs: [UUID] = []
        let queue = CiderReviewQueueService(
            database: db,
            routingDecisionService: routing,
            enrichmentScheduler: { scheduledIDs.append($0) }
        )

        let result = try queue.enrichBatch(actor: "agent", sampleFailureLimit: 3)

        #expect(scheduledIDs == [firstEnrichmentID, secondEnrichmentID])
        #expect(result.action == "review.enrich.batch")
        #expect(result.actor == "agent")
        #expect(result.isMutating)
        #expect(result.candidateCount == 2)
        #expect(result.scheduledCount == 2)
        #expect(result.excludedCount == 1)
        #expect(result.skippedCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.exclusionsByReason["routing_requires_explicit_approval"] == 1)
        #expect(result.failures.isEmpty)
        #expect(result.safeActions.contains("review summary"))

        let dictionary = result.toDictionary()
        #expect(dictionary["action"] as? String == "review.enrich.batch")
        #expect(dictionary["scheduledCount"] as? Int == 2)
        #expect(dictionary["excludedCount"] as? Int == 1)
        #expect((dictionary["batchID"] as? String)?.isEmpty == false)

        let auditEntries = MutationAuditService(database: db).loadEntries()
        #expect(auditEntries.count == 2)
        #expect(Set(auditEntries.map(\.itemID)) == Set([firstEnrichmentID, secondEnrichmentID]))
        #expect(Set(auditEntries.map(\.action)) == ["review.enrich.batch.schedule"])
        #expect(Set(auditEntries.map(\.source)) == [.agent])
        #expect(Set(auditEntries.map { $0.metadata["batchID"] }) == [result.batchID.uuidString])
        #expect(Set(auditEntries.map { $0.metadata["candidateCount"] }) == ["2"])
        #expect(Set(auditEntries.map { $0.metadata["excludedCount"] }) == ["1"])
    }

    @Test("review action job history summarizes batch enrichment audit rows")
    func reviewActionJobHistorySummarizesBatchEnrichmentAuditRows() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let firstEnrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata A",
            relativePath: "Inbox/Bookmarks/Needs Metadata A.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let secondEnrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata B",
            relativePath: "Inbox/Bookmarks/Needs Metadata B.webloc",
            enrichmentStatus: "pending",
            lastEnrichedAt: nil
        )
        let routingID = try insertBookmark(
            db,
            title: "Needs Routing",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: routingID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.1,
            reason: "Needs a human route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(
            database: db,
            routingDecisionService: routing,
            enrichmentScheduler: { _ in }
        )
        let batch = try queue.enrichBatch(actor: "agent", sampleFailureLimit: 3)

        let history = try queue.actionJobHistory(limit: 10)

        #expect(history.command == "review.jobs")
        #expect(history.jobs.count == 1)
        let job = try #require(history.jobs.first)
        #expect(job.action == "review.enrich.batch")
        #expect(job.batchID == batch.batchID)
        #expect(job.actor == "agent")
        #expect(job.source == "agent")
        #expect(job.candidateCount == 2)
        #expect(job.scheduledCount == 2)
        #expect(job.excludedCount == 1)
        #expect(job.failedCount == 0)
        #expect(job.itemSamples.map(\.itemID) == [secondEnrichmentID, firstEnrichmentID])
        #expect(job.itemSamples.map(\.title) == ["Needs Metadata B", "Needs Metadata A"])
        #expect(job.safeActions.contains("review summary"))

        let dictionary = history.toDictionary()
        #expect(dictionary["command"] as? String == "review.jobs")
        let jobs = try #require(dictionary["jobs"] as? [[String: Any]])
        let jobDictionary = try #require(jobs.first)
        #expect(jobDictionary["batchID"] as? String == batch.batchID.uuidString)
        #expect(jobDictionary["scheduledCount"] as? Int == 2)
        #expect(jobDictionary["excludedCount"] as? Int == 1)
        #expect((jobDictionary["itemSamples"] as? [[String: Any]])?.count == 2)
    }
}
