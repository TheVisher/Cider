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

    private func bookmarkEnrichmentState(_ db: CiderDatabase, itemID: UUID) throws -> (status: String?, lastEnrichedAt: Date?) {
        let stmt = try db.prepare("""
            SELECT enrichment_status, last_enriched_at
            FROM bookmarks
            WHERE item_id = ?;
            """)
        stmt.bind(itemID.uuidString, at: 1)
        guard try stmt.step() else {
            Issue.record("bookmark missing")
            return (nil, nil)
        }
        return (
            stmt.optionalString(at: 0),
            stmt.optionalDouble(at: 1).map(DatabaseHelpers.decodeDate)
        )
    }

    private func insertBookmark(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        title: String = "Example",
        url: String = "https://example.com",
        folderID: UUID? = nil,
        relativePath: String = "Inbox/Bookmarks/Example.webloc",
        enrichmentStatus: String? = "complete",
        lastEnrichedAt: Date? = Date(),
        updatedAt: Date = Date(),
        aiSummary: String? = nil,
        ocrText: String? = nil,
        thumbnailRelativePath: String? = nil,
        thumbnailRemoteURL: String? = nil
    ) throws -> UUID {
        try db.withTransaction {
            let item = try db.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, 'bookmark', ?, ?, ?, ?, ?);
                """)
            item.bind(id.uuidString, at: 1)
                .bind(title, at: 2)
                .bind(Date().timeIntervalSince1970, at: 3)
                .bind(updatedAt.timeIntervalSince1970, at: 4)
                .bind(folderID?.uuidString, at: 5)
                .bind(relativePath, at: 6)
            try item.step()

            let bookmark = try db.prepare("""
                INSERT INTO bookmarks (
                    item_id, url, notes, notes_manually_set, title_manually_set,
                    ai_summary, ocr_text, thumbnail_relative_path, thumbnail_remote_url,
                    enrichment_status, last_enriched_at
                ) VALUES (?, ?, '', 0, 0, ?, ?, ?, ?, ?, ?);
                """)
            bookmark.bind(id.uuidString, at: 1)
                .bind(url, at: 2)
                .bind(aiSummary, at: 3)
                .bind(ocrText, at: 4)
                .bind(thumbnailRelativePath, at: 5)
                .bind(thumbnailRemoteURL, at: 6)
                .bind(enrichmentStatus, at: 7)
                .bind(lastEnrichedAt.map { $0.timeIntervalSince1970 }, at: 8)
            try bookmark.step()
        }
        return id
    }

    private func insertItem(
        _ db: CiderDatabase,
        id: UUID = UUID(),
        type: String,
        title: String,
        relativePath: String,
        folderID: UUID? = nil,
        updatedAt: Date = Date()
    ) throws -> UUID {
        let item = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """)
        item.bind(id.uuidString, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(Date().timeIntervalSince1970, at: 4)
            .bind(updatedAt.timeIntervalSince1970, at: 5)
            .bind(folderID?.uuidString, at: 6)
            .bind(relativePath, at: 7)
        try item.step()
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

    @Test("review queue routes non-bookmark correction to item move instead of review correct")
    func reviewQueueRoutesNonBookmarkCorrectionToItemMove() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertItem(
            db,
            type: "note",
            title: "Routeable Note",
            relativePath: "Inbox/Notes/Routeable Note.md"
        )
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: itemID,
            itemType: "note",
            target: .init(kind: "inbox", name: "Inbox/Notes", relativePath: "Inbox/Notes", folderID: nil),
            confidence: 0,
            reason: "No deterministic note route was supplied.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )

        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)
        let result = try queue.list()

        let item = try #require(result.items.first { $0.itemID == itemID })
        #expect(item.itemType == "note")
        #expect(item.safeActions == ["approve", "item move", "defer"])
        #expect(item.safeActions.contains("correct") == false)
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

    @Test("review queue surfaces graph candidates as source-backed triage items")
    func reviewQueueSurfacesGraphCandidatesAsSourceBackedTriageItems() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let noteID = try insertItem(
            db,
            type: "note",
            title: "Movie journal",
            relativePath: "Journal/Movie journal.md"
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "Watched The Way Way Back tonight and loved the water park scene.",
            sourceKind: "journal",
            objectTypeGuesses: [.movie, .media],
            relationGuesses: [.watched],
            actionGuesses: ["watched"],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.78,
            confidenceReason: "The sentence explicitly says this was watched.",
            source: "graph_candidate.test"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(output)

        let queue = CiderReviewQueueService(database: db)
        let result = try queue.list(kind: "graph_candidate")

        #expect(result.command == "review.list")
        #expect(result.items.count == 1)
        let item = try #require(result.items.first)
        #expect(item.kind == "graph_candidate")
        #expect(item.source == "graph_candidate")
        #expect(item.itemID == noteID)
        #expect(item.itemType == "note")
        #expect(item.title == "The Way Way Back")
        #expect(item.reviewState == "suggested")
        #expect(item.confidence == 0.78)
        #expect(item.confidenceReason == "The sentence explicitly says this was watched.")
        #expect(item.candidateID == output.id)
        #expect(item.candidateRef == "graph_candidate:\(output.id)")
        #expect(item.sourceQuote == "Watched The Way Way Back tonight and loved the water park scene.")
        #expect(item.possibleTypes == ["movie", "media"])
        #expect(item.possibleRelations == ["watched"])
        #expect(item.candidateActions == ["watched"])
        #expect(item.safeActions == ["inspect_source", "link_existing", "create_object", "correct", "reject", "delegate_enrichment"])
        #expect(item.safeNextCommands.contains("cider-cli item graph-candidate \(output.id) --json"))
        #expect(item.safeNextCommands.contains("cider-cli item context note \(noteID.uuidString) --json"))

        let dictionary = item.toDictionary()
        #expect(dictionary["candidateID"] as? String == output.id)
        #expect(dictionary["sourceQuote"] as? String == output.evidence)
        #expect(dictionary["possibleTypes"] as? [String] == ["movie", "media"])
        #expect(dictionary["confidenceReason"] as? String == "The sentence explicitly says this was watched.")
        #expect(dictionary["safeNextCommands"] as? [String] == item.safeNextCommands)

        let summary = try queue.summary()
        #expect(summary.countsByKind["graph_candidate"] == 1)
        #expect(summary.countsBySafeAction["inspect_source"] == 1)
        #expect(summary.groups.first?.id == "graph_candidate:suggested:inspect_source:note")

        let worklist = try queue.captureReviewWorklist(limit: 10)
        let worklistItem = try #require(worklist.items.first { $0.candidateID == output.id })
        #expect(worklistItem.kind == "graph_candidate")
        #expect(worklistItem.ownerType == "note")
        #expect(worklistItem.ownerID == noteID.uuidString)
        #expect(worklistItem.sourceQuote == output.evidence)
        #expect(worklistItem.possibleTypes == ["movie", "media"])
        #expect(worklistItem.confidence == 0.78)
        #expect(worklistItem.safeNextCommands.contains("cider-cli item graph-candidate \(output.id) --json"))
        let worklistDictionary = worklistItem.toDictionary()
        #expect(worklistDictionary["needsReview"] as? Bool == true)
        #expect(worklistDictionary["recommendedNextAction"] as? String == "review_graph_candidate")
        #expect(worklistDictionary["candidateRef"] as? String == "graph_candidate:\(output.id)")
        #expect(worklistDictionary["confidence"] as? Double == 0.78)
    }

    @Test("review list limit does not hide source-backed candidates behind routing rows")
    func reviewListLimitDoesNotHideSourceBackedCandidatesBehindRoutingRows() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let routing = CiderRoutingDecisionService(database: db)
        for index in 0..<5 {
            let itemID = try insertBookmark(
                db,
                title: "Routing review \(index)",
                url: "https://example.com/routing-\(index)",
                relativePath: "Inbox/Bookmarks/Routing review \(index).webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: Date()
            )
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
        }

        let noteID = try insertItem(
            db,
            type: "note",
            title: "Movie journal",
            relativePath: "Journal/Movie journal.md"
        )
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString),
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "Watched The Way Way Back tonight.",
            sourceKind: "journal",
            objectTypeGuesses: [.movie],
            relationGuesses: [.watched],
            actionGuesses: ["watched"],
            safeActions: [.inspectSource, .reject],
            confidence: 0.78,
            confidenceReason: "The source sentence explicitly names the movie.",
            source: "graph_candidate.test"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(output)

        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)
        let result = try queue.list(limit: 1)

        #expect(result.items.map(\.kind) == ["graph_candidate"])
        #expect(result.items.first?.candidateID == output.id)
    }

    @Test("review queue surfaces memory candidates as source-backed triage items")
    func reviewQueueSurfacesMemoryCandidatesAsSourceBackedTriageItems() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let noteID = try insertItem(
            db,
            type: "note",
            title: "Alex context",
            relativePath: "Daily/2026-06-10.md"
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let result = try SecondBrainMemoryCandidateService(database: db).suggest(
            owner: owner,
            requestedOwnerType: "note",
            requestedOwnerRef: noteID.uuidString,
            kind: "relationship_context",
            value: "Alex prefers late coffee catch-ups.",
            evidence: "Journal note says Alex prefers late coffee catch-ups.",
            source: "test",
            confidence: 0.83,
            linkedOwners: [
                SecondBrainOwnerRef(ownerType: "contact", ownerID: "alex"),
                SecondBrainOwnerRef(ownerType: "project", ownerID: "cider"),
            ],
            observedDate: "2026-06-10",
            memoryKey: "alex-coffee-catchups",
            memoryStatus: "current"
        )

        let queue = CiderReviewQueueService(database: db)
        let resultList = try queue.list(kind: "memory_candidate")

        #expect(resultList.command == "review.list")
        #expect(resultList.items.count == 1)
        let item = try #require(resultList.items.first)
        #expect(item.kind == "memory_candidate")
        #expect(item.source == "memory_candidate")
        #expect(item.itemID == noteID)
        #expect(item.itemType == "note")
        #expect(item.title == "Alex prefers late coffee catch-ups.")
        #expect(item.reviewState == "suggested")
        #expect(item.confidence == 0.83)
        #expect(item.candidateID == result.candidate.id)
        #expect(item.candidateRef == "memory_candidate:\(result.candidate.id)")
        #expect(item.sourceQuote == "Journal note says Alex prefers late coffee catch-ups.")
        #expect(item.memoryKind == "relationship_context")
        #expect(item.linkedOwnerRefs == ["contact:alex", "project:cider"])
        #expect(item.observedDate == "2026-06-10")
        #expect(item.memoryKey == "alex-coffee-catchups")
        #expect(item.memoryStatus == "current")
        #expect(item.safeActions == ["inspect_source", "accept", "reject", "defer", "correct"])
        #expect(item.safeNextCommands.contains("cider-cli item context note \(noteID.uuidString) --json"))
        #expect(!item.safeNextCommands.contains { $0.contains("accept") || $0.contains("promote") })

        let dictionary = item.toDictionary()
        #expect(dictionary["candidateRef"] as? String == "memory_candidate:\(result.candidate.id)")
        #expect(dictionary["memoryKind"] as? String == "relationship_context")
        #expect(dictionary["linkedOwnerRefs"] as? [String] == ["contact:alex", "project:cider"])
        #expect(dictionary["sourceQuote"] as? String == result.candidate.evidence)

        let summary = try queue.summary()
        #expect(summary.countsByKind["memory_candidate"] == 1)
        #expect(summary.countsBySafeAction["inspect_source"] == 1)
        #expect(summary.countsBySafeAction["accept"] == 1)
        #expect(summary.countsBySafeAction["reject"] == 1)
        #expect(summary.countsBySafeAction["defer"] == 1)
        #expect(summary.groups.first?.id == "memory_candidate:suggested:inspect_source:note")

        let worklist = try queue.captureReviewWorklist(limit: 10, kind: "memory_candidate")
        let worklistItem = try #require(worklist.items.first { $0.candidateID == result.candidate.id })
        #expect(worklistItem.kind == "memory_candidate")
        #expect(worklistItem.ownerType == "note")
        #expect(worklistItem.ownerID == noteID.uuidString)
        #expect(worklistItem.sourceQuote == result.candidate.evidence)
        #expect(worklistItem.memoryKind == "relationship_context")
        #expect(worklistItem.linkedOwnerRefs == ["contact:alex", "project:cider"])
        let worklistDictionary = worklistItem.toDictionary()
        #expect(worklistDictionary["needsReview"] as? Bool == true)
        #expect(worklistDictionary["recommendedNextAction"] as? String == "review_memory_candidate")
        #expect(worklistDictionary["candidateRef"] as? String == "memory_candidate:\(result.candidate.id)")
        #expect(worklistDictionary["linkedOwnerRefs"] as? [String] == ["contact:alex", "project:cider"])
    }

    @Test("candidate action service accepts rejects and defers memory candidates")
    func candidateActionServiceMutatesMemoryCandidates() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let noteID = try insertItem(
            db,
            type: "note",
            title: "Jami context",
            relativePath: "Daily/2026-06-10.md"
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let memoryService = SecondBrainMemoryCandidateService(database: db)
        let acceptCandidate = try memoryService.suggest(
            owner: owner,
            requestedOwnerType: "note",
            requestedOwnerRef: noteID.uuidString,
            kind: "relationship_context",
            value: "Jami likes pineapple coconut drinks.",
            evidence: "Jami liked the pineapple coconut drink.",
            source: "test.accept",
            confidence: 0.91
        ).candidate
        let rejectCandidate = try memoryService.suggest(
            owner: owner,
            requestedOwnerType: "note",
            requestedOwnerRef: noteID.uuidString,
            kind: "relationship_context",
            value: "Jami dislikes mango.",
            evidence: "Ambiguous line about mango.",
            source: "test.reject",
            confidence: 0.41
        ).candidate
        let deferCandidate = try memoryService.suggest(
            owner: owner,
            requestedOwnerType: "note",
            requestedOwnerRef: noteID.uuidString,
            kind: "relationship_context",
            value: "Jami may prefer late coffee.",
            evidence: "Maybe late coffee worked better.",
            source: "test.defer",
            confidence: 0.55
        ).candidate

        let actionService = CiderReviewCandidateActionService(database: db)
        let accept = try actionService.acceptMemoryCandidate(acceptCandidate.id, actor: "tester")
        let reject = try actionService.rejectMemoryCandidate(rejectCandidate.id, reason: "Nope.", actor: "tester")
        let deferred = try actionService.deferMemoryCandidate(deferCandidate.id, reason: "Later.", actor: "tester")

        #expect(accept.reviewState == "accepted")
        #expect(reject.reviewState == "rejected")
        #expect(deferred.reviewState == "deferred")
        let outputService = SecondBrainEnrichmentOutputService(database: db)
        #expect(try outputService.output(id: acceptCandidate.id)?.reviewState == "accepted")
        #expect(try outputService.output(id: rejectCandidate.id)?.metadata["rejection_reason"] == "Nope.")
        #expect(try outputService.output(id: deferCandidate.id)?.metadata["deferral_reason"] == "Later.")
        let actions = try SecondBrainStore(database: db).agentActions(for: owner)
        #expect(actions.map(\.actionType).contains("memory_candidate.accept"))
        #expect(actions.map(\.actionType).contains("memory_candidate.reject"))
        #expect(actions.map(\.actionType).contains("memory_candidate.defer"))
    }

    @Test("candidate action service rejects ambiguous graph accept but can reject candidate")
    func candidateActionServiceRejectsAmbiguousGraphAccept() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let noteID = try insertItem(
            db,
            type: "note",
            title: "Movie journal",
            relativePath: "Daily/2026-06-10.md"
        )
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let output = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "Watched The Way Way Back tonight.",
            sourceKind: "journal",
            objectTypeGuesses: [.movie, .media],
            relationGuesses: [.watched],
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: 0.78,
            source: "test.graph.reject"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(output)

        let actionService = CiderReviewCandidateActionService(database: db)
        #expect(throws: CiderReviewCandidateActionService.ReviewCandidateActionError.graphAcceptNeedsResolvedTarget(output.id)) {
            _ = try actionService.acceptGraphCandidateIfResolved(output.id, actor: "tester")
        }

        let reject = try actionService.rejectGraphCandidate(output.id, reason: "Wrong movie.", actor: "tester")
        #expect(reject.reviewState == "rejected")
        #expect(try SecondBrainEnrichmentOutputService(database: db).output(id: output.id)?.metadata["rejection_reason"] == "Wrong movie.")
        #expect(try SecondBrainStore(database: db).outgoingRelations(for: owner).isEmpty)

        let resolvedTarget = SecondBrainOwnerRef(ownerType: "graph_object", ownerID: "movie-the-way-way-back")
        let resolved = try SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: "The Way Way Back",
            sourceQuote: "Watched The Way Way Back tonight.",
            sourceKind: "journal",
            objectTypeGuesses: [.movie, .media],
            relationGuesses: [.watched],
            safeActions: [.inspectSource, .accept, .reject],
            confidence: 0.91,
            acceptedTargetOwner: resolvedTarget,
            acceptedRelationType: .watched,
            source: "test.graph.accept"
        )
        try SecondBrainEnrichmentOutputService(database: db).record(resolved)

        let accept = try actionService.acceptGraphCandidateIfResolved(resolved.id, actor: "tester")
        #expect(accept.reviewState == "accepted")
        let relations = try SecondBrainStore(database: db).outgoingRelations(for: owner)
        #expect(relations.count == 1)
        #expect(relations.first?.targetOwner == resolvedTarget)
        #expect(relations.first?.relationType == "watched")
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

    @Test("review queue surfaces duplicate auditor candidates as manual review items")
    func reviewQueueSurfacesDuplicateAuditorCandidates() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let firstID = try insertBookmark(
            db,
            title: "Duplicate A",
            url: "https://example.com/a",
            relativePath: "Saved/Duplicate A.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date()
        )
        let secondID = UUID()
        let duplicateFinding = VaultDuplicateAuditor.Finding(
            id: "duplicate-bookmark-url-example",
            entityType: .bookmark,
            kind: .canonicalURL,
            confidence: .exact,
            summary: "Duplicate bookmark URL: example.com/a",
            detail: "Two bookmarks canonicalize to the same URL and need human merge review.",
            items: [
                .init(
                    id: firstID.uuidString,
                    title: "Duplicate A",
                    path: "Saved/Duplicate A.webloc",
                    value: "https://example.com/a"
                ),
                .init(
                    id: secondID.uuidString,
                    title: "Duplicate A Copy",
                    path: "Inbox/Bookmarks/Duplicate A Copy.webloc",
                    value: "https://example.com/a"
                ),
            ]
        )
        let queue = CiderReviewQueueService(
            database: db,
            duplicateFindingsProvider: { [duplicateFinding] }
        )

        let result = try queue.list(kind: "duplicate_candidate")

        #expect(result.items.count == 1)
        let item = try #require(result.items.first)
        #expect(item.id == "review-duplicate-duplicate-bookmark-url-example")
        #expect(item.kind == "duplicate_candidate")
        #expect(item.source == "duplicate_auditor")
        #expect(item.itemID == firstID)
        #expect(item.itemType == "bookmark")
        #expect(item.title == "Duplicate bookmark URL: example.com/a")
        #expect(item.relativePath == "Saved/Duplicate A.webloc")
        #expect(item.reviewState == "needs_review")
        #expect(item.confidence == 1)
        #expect(item.safeActions == ["inspect_duplicates", "manual_review"])

        let summary = try queue.summary()
        #expect(summary.countsByKind["duplicate_candidate"] == 1)
        #expect(summary.countsBySafeAction["inspect_duplicates"] == 1)
        #expect(summary.groups.first { $0.id == "duplicate_candidate:needs_review:inspect_duplicates:bookmark" }?.count == 1)
    }

    @Test("review queue exposes structured trust boundary reason codes")
    func reviewQueueExposesStructuredTrustBoundaryReasonCodes() throws {
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
        let duplicateFinding = VaultDuplicateAuditor.Finding(
            id: "duplicate-bookmark-url-example",
            entityType: .bookmark,
            kind: .canonicalURL,
            confidence: .exact,
            summary: "Duplicate bookmark URL: example.com/a",
            detail: "Two bookmarks canonicalize to the same URL and need human merge review.",
            items: [
                .init(
                    id: UUID().uuidString,
                    title: "Duplicate A",
                    path: "Saved/Duplicate A.webloc",
                    value: "https://example.com/a"
                ),
            ]
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
            duplicateFindingsProvider: { [duplicateFinding] }
        )

        let items = try queue.list().items

        #expect(items.first { $0.itemID == routingID }?.reasonCodes == ["routing_low_confidence"])
        #expect(items.first { $0.itemID == enrichmentID }?.reasonCodes == ["enrichment_failed"])
        #expect(items.first { $0.itemID == inboxID }?.reasonCodes == ["inbox_unrouted"])
        #expect(items.first { $0.kind == "duplicate_candidate" }?.reasonCodes == ["duplicate_canonical_url"])
        let dictionary = try #require(items.first { $0.itemID == routingID }?.toDictionary())
        #expect(dictionary["reasonCodes"] as? [String] == ["routing_low_confidence"])
    }

    @Test("capture review worklist includes uncertain routing with read only safe commands")
    func captureReviewWorklistIncludesUncertainRouting() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(db, title: "Route Me", enrichmentStatus: "complete", lastEnrichedAt: Date())
        let routing = CiderRoutingDecisionService(database: db)
        _ = try routing.recordDecision(
            itemID: itemID,
            itemType: "bookmark",
            target: .init(kind: "inbox", name: "Inbox/Bookmarks", relativePath: "Inbox/Bookmarks", folderID: nil),
            confidence: 0.1,
            reason: "Needs a human route.",
            actor: "agent",
            source: "capture.add",
            reviewState: "needs_review"
        )
        let queue = CiderReviewQueueService(database: db, routingDecisionService: routing)

        let result = try queue.captureReviewWorklist(limit: 10)

        #expect(result.command == "capture.review-queue")
        #expect(result.readOnly == true)
        #expect(result.changed == false)
        let item = try #require(result.items.first { $0.itemID == itemID })
        #expect(item.kind == "low_confidence_routing")
        #expect(item.reasonCodes == ["routing_low_confidence"])
        #expect(item.severity == "medium")
        #expect(item.reviewState == "needs_review")
        #expect(item.routingState?["targetPath"] == "Inbox/Bookmarks")
        #expect(item.safeNextCommands.contains("cider-cli item get bookmark \(itemID.uuidString) --json"))
        #expect(item.safeNextCommands.contains { $0.contains("review approve") } == false)
        #expect(result.countsByReasonCode["routing_low_confidence"] == 1)

        let dictionary = item.toDictionary()
        #expect(dictionary["saved"] as? Bool == true)
        #expect(dictionary["useful"] as? Bool == false)
        #expect(dictionary["needsReview"] as? Bool == true)
        #expect(dictionary["requiresHumanReview"] as? Bool == true)
        #expect(dictionary["needsRouting"] as? Bool == true)
        #expect(dictionary["agentMayRoute"] as? Bool == false)
        #expect(dictionary["confidence"] as? Double == 0.1)
        #expect(dictionary["recommendedNextAction"] as? String == "review_route")
        #expect((dictionary["blockingIssues"] as? [String]) == ["routing_low_confidence"])
        let nextActions = try #require(dictionary["nextActions"] as? [[String: Any]])
        #expect(nextActions.first?["action"] as? String == "review_route")
        #expect(nextActions.first?["readOnly"] as? Bool == true)
        #expect(nextActions.first?["requiresApproval"] as? Bool == true)
        let routingState = try #require(dictionary["routingState"] as? [String: Any])
        #expect(routingState["confidence"] as? Double == 0.1)
    }

    @Test("capture review worklist surfaces unsupported attachment capture events")
    func captureReviewWorklistSurfacesUnsupportedAttachments() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let eventID = UUID()
        let attachmentID = UUID()
        let now = Date().timeIntervalSince1970
        let metadata = DatabaseHelpers.encodeJSON([
            "review_reason": "unsupported_attachment",
            "review_state": "needs_review",
        ]) ?? "{}"
        let insertEvent = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, 'chat_unsupported_attachment', 'chat', 'discord', 'channel-1', NULL, 'msg-1',
                      'user-1', 'Erik', NULL, NULL, 'see attachment', 1, ?, ?);
            """)
        insertEvent.bind(eventID.uuidString, at: 1)
            .bind(metadata, at: 2)
            .bind(now, at: 3)
        try insertEvent.step()

        let insertAttachment = try db.prepare("""
            INSERT INTO capture_attachments (
                id, capture_event_id, attachment_index, source_attachment_id,
                filename, mime_type, local_path, remote_url, byte_size, metadata, created_at
            ) VALUES (?, ?, 0, 'remote-1', 'remote.pdf', 'application/pdf',
                      NULL, 'https://cdn.example/remote.pdf', NULL, ?, ?);
            """)
        insertAttachment.bind(attachmentID.uuidString, at: 1)
            .bind(eventID.uuidString, at: 2)
            .bind(metadata, at: 3)
            .bind(now, at: 4)
        try insertAttachment.step()

        try SecondBrainEnrichmentOutputService(database: db).record(SecondBrainEnrichmentOutput(
            owner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString),
            kind: "unsupported_chat_attachment",
            value: "remote.pdf",
            normalizedValue: "chat_unsupported_attachments:\(eventID.uuidString.lowercased())",
            label: "Unsupported chat attachment",
            evidence: "Chat capture included attachment metadata without a local file path.",
            source: "chat.capture",
            confidence: 1,
            reviewState: "needs_review",
            metadata: ["review_state": "needs_review"]
        ))

        let result = try CiderReviewQueueService(database: db).captureReviewWorklist(limit: 10)

        let item = try #require(result.items.first { $0.ownerID == eventID.uuidString })
        #expect(item.kind == "unsupported_attachment")
        #expect(item.itemType == "capture_event")
        #expect(item.reasonCodes == ["unsupported_attachment", "remote_only_attachment"])
        #expect(item.severity == "high")
        #expect(item.provenance["channel"] == "discord")
        #expect(item.provenance["messageID"] == "msg-1")
        #expect(item.attachmentSummary?["count"] == "1")
        #expect(item.safeNextCommands.contains("cider-cli item backlinks capture_event \(eventID.uuidString) --json"))
        #expect(result.countsByReasonCode["unsupported_attachment"] == 1)
    }

    @Test("capture review worklist surfaces missing and stale indexing")
    func captureReviewWorklistSurfacesMissingAndStaleIndexing() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let missingID = try insertItem(
            db,
            type: "note",
            title: "Missing Index",
            relativePath: "Inbox/Notes/Missing Index.md"
        )
        let staleID = try insertItem(
            db,
            type: "note",
            title: "Stale Index",
            relativePath: "Inbox/Notes/Stale Index.md",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )
        let insertChunk = try db.prepare("""
            INSERT INTO content_chunks (
                id, item_id, owner_type, owner_id, source, title, body,
                chunk_index, content_hash, metadata, created_at, updated_at
            ) VALUES (?, ?, 'note', ?, 'test', 'Stale Index', 'old body',
                      0, 'old-hash', '{}', ?, ?);
            """)
        insertChunk.bind(UUID().uuidString, at: 1)
            .bind(staleID.uuidString, at: 2)
            .bind(staleID.uuidString, at: 3)
            .bind(Date(timeIntervalSince1970: 1_000).timeIntervalSince1970, at: 4)
            .bind(Date(timeIntervalSince1970: 1_000).timeIntervalSince1970, at: 5)
        try insertChunk.step()

        let result = try CiderReviewQueueService(database: db).captureReviewWorklist(limit: 10)

        let missing = try #require(result.items.first { $0.itemID == missingID })
        let stale = try #require(result.items.first { $0.itemID == staleID })
        #expect(missing.kind == "indexing")
        #expect(missing.reasonCodes == ["index_missing_chunks"])
        #expect(missing.indexingStatus == "missing")
        #expect(missing.safeNextCommands.contains("cider-cli item search-debug \"Missing Index\" --limit 5 --json"))
        #expect(stale.reasonCodes == ["index_stale_chunks"])
        #expect(stale.indexingStatus == "stale")
        #expect(result.countsByReasonCode["index_missing_chunks"] == 1)
        #expect(result.countsByReasonCode["index_stale_chunks"] == 1)
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

    @Test("review enrichment diagnosis explains pending reason groups")
    func reviewEnrichmentDiagnosisExplainsPendingReasonGroups() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let missingStatusID = try insertBookmark(
            db,
            title: "Missing Status",
            relativePath: "Inbox/Bookmarks/Missing Status.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil
        )
        let neverEnrichedID = try insertBookmark(
            db,
            title: "Never Enriched",
            relativePath: "Inbox/Bookmarks/Never Enriched.webloc",
            enrichmentStatus: "pending",
            lastEnrichedAt: nil
        )
        let failedID = try insertBookmark(
            db,
            title: "Failed Enrichment",
            relativePath: "Inbox/Bookmarks/Failed Enrichment.webloc",
            enrichmentStatus: "failed",
            lastEnrichedAt: nil
        )
        let completeMissingTimestampID = try insertBookmark(
            db,
            title: "Complete Missing Timestamp",
            relativePath: "Inbox/Bookmarks/Complete Missing Timestamp.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: nil
        )
        let attemptedIncompleteID = try insertBookmark(
            db,
            title: "Attempted Incomplete",
            relativePath: "Inbox/Bookmarks/Attempted Incomplete.webloc",
            enrichmentStatus: "partial",
            lastEnrichedAt: Date(timeIntervalSince1970: 12)
        )
        _ = try insertBookmark(
            db,
            title: "Complete",
            relativePath: "Inbox/Bookmarks/Complete.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date(timeIntervalSince1970: 20)
        )
        let queue = CiderReviewQueueService(database: db)

        let diagnosis = try queue.enrichmentDiagnosis(sampleLimit: 2, now: Date(timeIntervalSince1970: 30))

        #expect(diagnosis.command == "review.enrichment.diagnosis")
        #expect(diagnosis.totalCandidateCount == 5)
        #expect(diagnosis.isMutating == false)
        #expect(diagnosis.groups.map(\.id) == [
            "missing_status",
            "never_enriched",
            "failed",
            "complete_missing_timestamp",
            "attempted_incomplete",
        ])
        #expect(diagnosis.groups.first { $0.id == "missing_status" }?.sampleItems.map(\.itemID) == [missingStatusID])
        #expect(diagnosis.groups.first { $0.id == "never_enriched" }?.sampleItems.map(\.itemID) == [neverEnrichedID])
        #expect(diagnosis.groups.first { $0.id == "failed" }?.sampleItems.map(\.itemID) == [failedID])
        #expect(diagnosis.groups.first { $0.id == "complete_missing_timestamp" }?.sampleItems.map(\.itemID) == [completeMissingTimestampID])
        #expect(diagnosis.groups.first { $0.id == "attempted_incomplete" }?.sampleItems.map(\.itemID) == [attemptedIncompleteID])
        #expect(diagnosis.groups.first { $0.id == "attempted_incomplete" }?.sampleItems.first?.lastEnrichedAt == Date(timeIntervalSince1970: 12))
        let dictionary = diagnosis.toDictionary()
        #expect(dictionary["command"] as? String == "review.enrichment.diagnosis")
        #expect(dictionary["totalCandidateCount"] as? Int == 5)
        #expect(dictionary["isMutating"] as? Bool == false)
        #expect((dictionary["groups"] as? [[String: Any]])?.count == 5)
    }

    @Test("review enrichment reconciliation plan proposes bounded safe dry-run actions")
    func reviewEnrichmentReconciliationPlanProposesBoundedSafeDryRunActions() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let aiEvidenceUpdatedAt = Date(timeIntervalSince1970: 100)
        let metadataEvidenceUpdatedAt = Date(timeIntervalSince1970: 200)
        let aiEvidenceID = try insertBookmark(
            db,
            title: "AI Evidence",
            relativePath: "Inbox/Bookmarks/AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: aiEvidenceUpdatedAt,
            aiSummary: "A concise useful summary."
        )
        let metadataEvidenceID = try insertBookmark(
            db,
            title: "Metadata Evidence",
            relativePath: "Inbox/Bookmarks/Metadata Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: metadataEvidenceUpdatedAt,
            thumbnailRemoteURL: "https://example.com/thumb.jpg"
        )
        let noEvidenceID = try insertBookmark(
            db,
            title: "No Evidence",
            relativePath: "Inbox/Bookmarks/No Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil
        )
        _ = try insertBookmark(
            db,
            title: "Already Complete",
            relativePath: "Inbox/Bookmarks/Already Complete.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: Date(timeIntervalSince1970: 300),
            aiSummary: "Already complete."
        )
        let queue = CiderReviewQueueService(database: db)

        let plan = try queue.enrichmentReconciliationPlan(sampleLimit: 1, now: Date(timeIntervalSince1970: 400))

        #expect(plan.command == "review.enrichment.reconciliationPlan")
        #expect(plan.isMutating == false)
        #expect(plan.approvalRequired == true)
        #expect(plan.totalCandidateCount == 3)
        #expect(plan.proposedChangeCount == 2)
        #expect(plan.blockedCount == 1)
        #expect(plan.groups.map(\.id) == [
            "can_mark_complete_from_ai_fields",
            "can_mark_partial_from_metadata_fields",
            "needs_enrichment_run",
        ])
        let completeSample = plan.groups.first { $0.id == "can_mark_complete_from_ai_fields" }?.sampleItems.first
        #expect(completeSample?.itemID == aiEvidenceID)
        #expect(completeSample?.proposedStatus == "complete")
        #expect(completeSample?.proposedLastEnrichedAt == aiEvidenceUpdatedAt)
        #expect(completeSample?.evidence.contains("ai_summary") == true)
        let partialSample = plan.groups.first { $0.id == "can_mark_partial_from_metadata_fields" }?.sampleItems.first
        #expect(partialSample?.itemID == metadataEvidenceID)
        #expect(partialSample?.proposedStatus == "partial")
        #expect(partialSample?.proposedLastEnrichedAt == metadataEvidenceUpdatedAt)
        #expect(partialSample?.evidence.contains("thumbnail_remote_url") == true)
        let blockedSample = plan.groups.first { $0.id == "needs_enrichment_run" }?.sampleItems.first
        #expect(blockedSample?.itemID == noEvidenceID)
        #expect(blockedSample?.proposedStatus == nil)
        let dictionary = plan.toDictionary()
        #expect(dictionary["command"] as? String == "review.enrichment.reconciliationPlan")
        #expect(dictionary["isMutating"] as? Bool == false)
        #expect(dictionary["approvalRequired"] as? Bool == true)
    }

    @Test("review enrichment reconciliation samples are bounded and group filterable")
    func reviewEnrichmentReconciliationSamplesAreBoundedAndGroupFilterable() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let firstAIEvidenceID = try insertBookmark(
            db,
            title: "First AI Evidence",
            url: "https://example.com/first-ai",
            relativePath: "Inbox/Bookmarks/First AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            aiSummary: "A concise useful summary."
        )
        _ = try insertBookmark(
            db,
            title: "Second AI Evidence",
            url: "https://example.com/second-ai",
            relativePath: "Inbox/Bookmarks/Second AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 200),
            ocrText: "Detected text."
        )
        _ = try insertBookmark(
            db,
            title: "Metadata Evidence",
            url: "https://example.com/metadata",
            relativePath: "Inbox/Bookmarks/Metadata Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 300),
            thumbnailRemoteURL: "https://example.com/thumb.jpg"
        )
        let queue = CiderReviewQueueService(database: db)

        let samples = try queue.enrichmentReconciliationSamples(
            groupID: "can_mark_complete_from_ai_fields",
            limit: 1,
            now: Date(timeIntervalSince1970: 400)
        )

        #expect(samples.command == "review.enrichment.reconciliationSamples")
        #expect(samples.isMutating == false)
        #expect(samples.approvalRequired == true)
        #expect(samples.totalCandidateCount == 3)
        #expect(samples.matchingCandidateCount == 2)
        #expect(samples.limit == 1)
        #expect(samples.sampleItems.count == 1)
        #expect(samples.sampleItems.first?.itemID == firstAIEvidenceID)
        #expect(samples.sampleItems.first?.groupID == "can_mark_complete_from_ai_fields")
        #expect(samples.sampleItems.first?.url == "https://example.com/first-ai")
        #expect(samples.sampleItems.first?.proposedStatus == "complete")
        #expect(samples.sampleItems.first?.evidence.contains("ai_summary") == true)
        let dictionary = samples.toDictionary()
        #expect(dictionary["command"] as? String == "review.enrichment.reconciliationSamples")
        #expect(dictionary["isMutating"] as? Bool == false)
        #expect(dictionary["approvalRequired"] as? Bool == true)
    }

    @Test("review enrichment reconciliation apply refuses missing exact approval without mutation")
    func reviewEnrichmentReconciliationApplyRefusesMissingExactApprovalWithoutMutation() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let itemID = try insertBookmark(
            db,
            title: "AI Evidence",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            aiSummary: "A concise useful summary."
        )
        let queue = CiderReviewQueueService(database: db)

        let result = try queue.applyEnrichmentReconciliation(
            groupID: "can_mark_complete_from_ai_fields",
            limit: 1,
            approvalToken: nil,
            execute: true,
            actor: "agent",
            now: Date(timeIntervalSince1970: 400)
        )

        #expect(result.command == "review.enrichment.reconciliationApply")
        #expect(result.status == "refused")
        #expect(result.isMutating == false)
        #expect(result.approvalRequired == true)
        #expect(result.requiredApprovalToken == "review.enrichment.reconciliationApply:can_mark_complete_from_ai_fields:limit=1:matching=1:proposed=1")
        #expect(result.blockers.contains { $0.contains("exact approval") })
        let state = try bookmarkEnrichmentState(db, itemID: itemID)
        #expect(state.status == nil)
        #expect(state.lastEnrichedAt == nil)
        #expect(MutationAuditService(database: db).loadEntries().isEmpty)
    }

    @Test("review enrichment reconciliation apply updates bounded selected candidates and records audit")
    func reviewEnrichmentReconciliationApplyUpdatesBoundedSelectedCandidatesAndRecordsAudit() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let firstID = try insertBookmark(
            db,
            title: "First AI Evidence",
            relativePath: "Inbox/Bookmarks/First AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            aiSummary: "A concise useful summary."
        )
        let secondID = try insertBookmark(
            db,
            title: "Second AI Evidence",
            relativePath: "Inbox/Bookmarks/Second AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 200),
            ocrText: "Detected text."
        )
        let partialID = try insertBookmark(
            db,
            title: "Metadata Evidence",
            relativePath: "Inbox/Bookmarks/Metadata Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 300),
            thumbnailRemoteURL: "https://example.com/thumb.jpg"
        )
        let queue = CiderReviewQueueService(database: db)

        let result = try queue.applyEnrichmentReconciliation(
            groupID: "can_mark_complete_from_ai_fields",
            limit: 1,
            approvalToken: "review.enrichment.reconciliationApply:can_mark_complete_from_ai_fields:limit=1:matching=2:proposed=2",
            execute: true,
            actor: "agent",
            now: Date(timeIntervalSince1970: 400)
        )

        #expect(result.status == "applied")
        #expect(result.isMutating == true)
        #expect(result.totalCandidateCount == 3)
        #expect(result.matchingCandidateCount == 2)
        #expect(result.selectedCount == 1)
        #expect(result.appliedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(result.projectedRemainingCandidateCount == 2)
        #expect(result.selectedItems.map(\.itemID) == [firstID])
        #expect(result.appliedItems.map(\.itemID) == [firstID])
        #expect(result.appliedItems.first?.proposedStatus == "complete")
        let firstState = try bookmarkEnrichmentState(db, itemID: firstID)
        #expect(firstState.status == "complete")
        #expect(firstState.lastEnrichedAt == Date(timeIntervalSince1970: 100))
        #expect(try bookmarkEnrichmentState(db, itemID: secondID).status == nil)
        #expect(try bookmarkEnrichmentState(db, itemID: partialID).status == nil)
        let audit = MutationAuditService(database: db).loadEntries().first {
            $0.itemID == firstID && $0.action == "review.enrichment.reconciliationApply"
        }
        #expect(audit?.source == .agent)
        #expect(audit?.beforeState["enrichmentStatus"] == "")
        #expect(audit?.afterState["enrichmentStatus"] == "complete")
        #expect(audit?.metadata["groupID"] == "can_mark_complete_from_ai_fields")
        #expect(audit?.metadata["requiredApprovalToken"] == result.requiredApprovalToken)
    }

    @Test("review enrichment reconciliation apply dry run projects remaining candidates")
    func reviewEnrichmentReconciliationApplyDryRunProjectsRemainingCandidates() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        _ = try insertBookmark(
            db,
            title: "First AI Evidence",
            relativePath: "Inbox/Bookmarks/First AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 100),
            aiSummary: "A concise useful summary."
        )
        _ = try insertBookmark(
            db,
            title: "Second AI Evidence",
            relativePath: "Inbox/Bookmarks/Second AI Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 200),
            ocrText: "Detected text."
        )
        _ = try insertBookmark(
            db,
            title: "Metadata Evidence",
            relativePath: "Inbox/Bookmarks/Metadata Evidence.webloc",
            enrichmentStatus: nil,
            lastEnrichedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 300),
            thumbnailRemoteURL: "https://example.com/thumb.jpg"
        )
        let queue = CiderReviewQueueService(database: db)

        let result = try queue.applyEnrichmentReconciliation(
            groupID: "can_mark_complete_from_ai_fields",
            limit: 1,
            approvalToken: nil,
            execute: false,
            actor: "agent",
            now: Date(timeIntervalSince1970: 400)
        )

        #expect(result.status == "planned")
        #expect(result.isMutating == false)
        #expect(result.totalCandidateCount == 3)
        #expect(result.matchingCandidateCount == 2)
        #expect(result.proposedChangeCount == 2)
        #expect(result.selectedCount == 1)
        #expect(result.appliedCount == 0)
        #expect(result.projectedRemainingCandidateCount == 2)
        #expect(result.selectedItems.count == 1)
        #expect(result.selectedItems.first?.title == "First AI Evidence")
        #expect(result.appliedItems.isEmpty)
        let dictionary = result.toDictionary()
        #expect(dictionary["selectedCount"] as? Int == 1)
        #expect(dictionary["projectedRemainingCandidateCount"] as? Int == 2)
        let selectedItems = try #require(dictionary["selectedItems"] as? [[String: Any]])
        #expect(selectedItems.count == 1)
        let appliedItems = try #require(dictionary["appliedItems"] as? [[String: Any]])
        #expect(appliedItems.isEmpty)
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

    @Test("review action job history summarizes batch enrichment result rows")
    func reviewActionJobHistorySummarizesBatchEnrichmentResultRows() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let completedID = try insertBookmark(
            db,
            title: "Completed Metadata",
            relativePath: "Inbox/Bookmarks/Completed Metadata.webloc",
            enrichmentStatus: "pending",
            lastEnrichedAt: nil
        )
        let timedOutID = try insertBookmark(
            db,
            title: "Timed Out Metadata",
            relativePath: "Inbox/Bookmarks/Timed Out Metadata.webloc",
            enrichmentStatus: "pending",
            lastEnrichedAt: nil
        )
        let queue = CiderReviewQueueService(
            database: db,
            enrichmentScheduler: { _ in }
        )
        let batch = try queue.enrichBatch(actor: "agent", sampleFailureLimit: 3)
        let audit = MutationAuditService(database: db)
        for (itemID, status) in [(completedID, "completed"), (timedOutID, "timed_out")] {
            audit.record(
                action: "review.enrich.batch.result",
                itemType: "bookmark",
                itemID: itemID,
                after: [
                    "reviewAction": "enrich",
                    "status": status,
                ],
                metadata: [
                    "batchID": batch.batchID.uuidString,
                    "candidateCount": "2",
                    "excludedCount": "0",
                ],
                source: .agent
            )
        }

        let history = try queue.actionJobHistory(limit: 10)

        let job = try #require(history.jobs.first)
        #expect(job.batchID == batch.batchID)
        #expect(job.resultState == "partial")
        #expect(job.candidateCount == 2)
        #expect(job.scheduledCount == 2)
        #expect(job.failedCount == 1)
        #expect(job.itemSamples.map(\.status) == ["timed_out", "completed"])

        let dictionary = history.toDictionary()
        let jobs = try #require(dictionary["jobs"] as? [[String: Any]])
        let jobDictionary = try #require(jobs.first)
        #expect(jobDictionary["resultState"] as? String == "partial")
        #expect(jobDictionary["failedCount"] as? Int == 1)
    }

    @Test("review action job history mixes enrichment batches and routing actions")
    func reviewActionJobHistoryMixesEnrichmentBatchesAndRoutingActions() throws {
        let (db, url) = try makeTempDB()
        defer { db.close(); cleanup(url) }
        let enrichmentID = try insertBookmark(
            db,
            title: "Needs Metadata",
            relativePath: "Inbox/Bookmarks/Needs Metadata.webloc",
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
            confidence: 0.2,
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
        let batch = try queue.enrichBatch(actor: "agent")
        let routingResult = try queue.approve(itemID: routingID, actor: "agent")

        let history = try queue.actionJobHistory(limit: 10)

        #expect(history.jobs.count == 2)
        #expect(history.jobs.map(\.action) == ["review.routing.approve", "review.enrich.batch"])
        let routingJob = try #require(history.jobs.first)
        #expect(routingJob.actionFamily == "routing")
        #expect(routingJob.resultState == "accepted")
        #expect(routingJob.jobID == routingResult.routingDecisionID.uuidString)
        #expect(routingJob.batchID == nil)
        #expect(routingJob.scheduledCount == 1)
        #expect(routingJob.candidateCount == 1)
        #expect(routingJob.itemSamples.map(\.itemID) == [routingID])
        #expect(routingJob.itemSamples.map(\.status) == ["accepted"])
        #expect(routingJob.safeActions.contains("routing explain"))

        let enrichmentJob = try #require(history.jobs.last)
        #expect(enrichmentJob.actionFamily == "enrichment")
        #expect(enrichmentJob.resultState == "scheduled")
        #expect(enrichmentJob.jobID == batch.batchID.uuidString)
        #expect(enrichmentJob.batchID == batch.batchID)
        #expect(enrichmentJob.itemSamples.map(\.itemID) == [enrichmentID])

        let dictionary = history.toDictionary()
        let jobs = try #require(dictionary["jobs"] as? [[String: Any]])
        #expect(jobs[0]["actionFamily"] as? String == "routing")
        #expect(jobs[0]["batchID"] == nil)
        #expect(jobs[1]["batchID"] as? String == batch.batchID.uuidString)
    }
}
