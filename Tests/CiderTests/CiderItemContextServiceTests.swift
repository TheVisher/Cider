import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Item Context Service Tests")
@MainActor
struct CiderItemContextServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-context-\(UUID().uuidString).db")
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func insertItem(
        _ ref: LibraryEntityRef,
        title: String,
        relativePath: String?,
        into db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
            .bind(DatabaseHelpers.encode(Date()), at: 5)
            .bind(relativePath, at: 6)
        try stmt.step()
    }

    @Test("context bundle includes item identity, sections, chunks, and related items")
    func contextBundleIncludesIdentitySectionsChunksAndRelatedItems() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and check insurance first.",
                source: "test",
                sortOrder: 0
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Dentist follow-up",
                body: "Call the dentist and check insurance first.",
                chunkIndex: 0
            )
        ])

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(database: db, linkService: linkService, secondBrainStore: store)

        let bundle = try service.context(for: note)

        #expect(bundle.item.id == note.entityID)
        #expect(bundle.item.type == .note)
        #expect(bundle.item.title == "Dentist follow-up")
        #expect(bundle.item.relativePath == "Inbox/Notes/Dentist follow-up.md")
        #expect(bundle.sections.map(\.sectionKey) == ["summary"])
        #expect(bundle.chunks.map(\.body) == ["Call the dentist and check insurance first."])
        #expect(bundle.related.map(\.title) == ["Dental insurance portal"])
    }

    @Test("captured item context exposes capture source context")
    func capturedItemContextExposesCaptureSourceContext() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Dogfood graph backend capture", relativePath: "Inbox/Notes/Dogfood graph backend capture.md", into: db)

        let eventID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_745_084_400)
        let metadata = DatabaseHelpers.encodeJSON(["workspace": "Cider"]) ?? "{}"
        let insertEvent = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """)
        insertEvent.bind(eventID.uuidString, at: 1)
            .bind("text", at: 2)
            .bind("codex_dogfood", at: 3)
            .bind("cli", at: 4)
            .bind("local", at: 5)
            .bind("thread-42", at: 6)
            .bind("dogfood-2026-05-19", at: 7)
            .bind("codex", at: 8)
            .bind("Codex", at: 9)
            .bind(String?.none, at: 10)
            .bind(String?.none, at: 11)
            .bind("Original dogfood capture text", at: 12)
            .bind(0, at: 13)
            .bind(metadata, at: 14)
            .bind(DatabaseHelpers.encode(createdAt), at: 15)
        try insertEvent.step()

        let store = SecondBrainStore(database: db)
        let captureOwner = SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: captureOwner,
            targetOwner: noteOwner,
            relationType: "produced_item",
            evidence: "Capture event produced note Dogfood graph backend capture.",
            source: "capture.add",
            actor: "system",
            confidence: 1,
            metadata: ["command": "capture.add"]
        ))

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let bundle = try service.context(for: note)

        #expect(bundle.captureProvenance.count == 1)
        #expect(bundle.captureProvenance[0].eventID == eventID.uuidString)
        #expect(bundle.captureProvenance[0].surface == "codex_dogfood")
        #expect(bundle.captureProvenance[0].channel == "cli")
        #expect(bundle.captureProvenance[0].messageID == "dogfood-2026-05-19")
        #expect(bundle.captureProvenance[0].senderID == "codex")
        #expect(bundle.captureProvenance[0].sourceText == "Original dogfood capture text")
        #expect(bundle.captureProvenance[0].metadata["workspace"] == "Cider")

        let dict = CiderCLI.itemContextBundleToDict(bundle)
        let provenance = try #require(dict["captureProvenance"] as? [[String: Any]])
        #expect(provenance.count == 1)
        #expect(provenance[0]["surface"] as? String == "codex_dogfood")
        #expect(provenance[0]["channel"] as? String == "cli")
        #expect(provenance[0]["messageID"] as? String == "dogfood-2026-05-19")

        let packet = try service.agentContext(for: note)
        #expect(packet.provenance.contains("capture:codex_dogfood/cli"))
        #expect(packet.captureProvenance.map(\.eventID) == [eventID.uuidString])
    }

    @Test("item context and home overview share recent capture surfacing for unfiled bookmarks")
    func itemContextAndHomeOverviewShareRecentCaptureSurfacingForUnfiledBookmarks() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let bookmarkID = UUID()
        let ref = LibraryEntityRef(type: .bookmark, entityID: bookmarkID)
        try insertItem(
            ref,
            title: "Saved Article",
            relativePath: "Inbox/Bookmarks/Saved Article.webloc",
            into: db
        )

        let bookmark = Bookmark(
            id: bookmarkID,
            title: "Saved Article",
            urlString: "https://example.com/article",
            createdAt: now.addingTimeInterval(-120),
            updatedAt: now.addingTimeInterval(-60),
            notes: "",
            tags: [],
            labelIDs: [],
            dismissedLabelIDs: [],
            folderID: nil,
            enrichmentStatus: "complete",
            lastEnrichedAt: now
        )
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: [.bookmark(bookmark)],
            recentItems: [.bookmark(bookmark)],
            folders: [],
            surfacingDays: 7,
            now: now
        )

        let packet = try CiderItemContextService(database: db).agentContext(for: ref)
        let homeSurfacing = try #require(snapshot.recentCaptureItems.first?.surfacingExplanation)

        #expect(packet.surfacing.reviewState == homeSurfacing.reviewState)
        #expect(packet.surfacing.suggestedAction == homeSurfacing.suggestedAction)
        #expect(packet.surfacing.reviewState == "ok")
        #expect(packet.surfacing.suggestedAction == "Open")
    }

    @Test("search returns item title matches and chunk text matches through one surface")
    func searchReturnsItemTitleMatchesAndChunkTextMatchesThroughOneSurface() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let dentist = LibraryEntityRef(type: .note, entityID: UUID())
        let renewal = LibraryEntityRef(type: .todo, entityID: UUID())
        try insertItem(dentist, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(renewal, title: "Review home insurance", relativePath: "Inbox/Todos/Review home insurance.md", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "todo", ownerID: renewal.entityID.uuidString)
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: renewal.entityID.uuidString,
                source: "test",
                title: "Insurance renewal",
                body: "The renewal window opens in September.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let titleMatches = try service.search("dentist", limit: 10)
        #expect(titleMatches.contains {
            $0.kind == .item && $0.item?.id == dentist.entityID && $0.title == "Dentist follow-up"
        })

        let chunkMatches = try service.search("renewal window", limit: 10)
        #expect(chunkMatches.contains {
            $0.kind == .chunk && $0.item?.id == renewal.entityID && $0.owner.ownerType == "todo"
        })
    }

    @Test("search diagnostics explain FTS chunk hits with item routing and safe commands")
    func searchDiagnosticsExplainChunkHitsWithItemContext() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Saffron recall note", relativePath: "Inbox/Notes/Saffron recall note.md", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "test",
                title: "Saffron memory",
                body: "The saffron diagnostic token should be visible through FTS.",
                chunkIndex: 0
            )
        ])
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: note.entityID.uuidString,
                targetType: "folder",
                targetPath: "Projects/Cider/Recall",
                confidence: 0.82,
                reason: "Recall diagnostics work belongs with Cider.",
                status: "accepted",
                actor: "agent",
                source: "routing.test"
            )
        )

        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let report = try service.searchDiagnostics("saffron diagnostic", limit: 10)

        #expect(report.query == "saffron diagnostic")
        #expect(report.exactMatches.contains { $0.kind == .chunk && $0.item?.id == note.entityID })
        #expect(report.matchedChunks.contains {
            $0.chunk.owner == owner
                && $0.item?.id == note.entityID
                && $0.routingDecisions.map(\.targetPath).contains("Projects/Cider/Recall")
                && $0.indexFreshness.status == "fresh"
        })
        #expect(report.semanticStatus.available == false)
        #expect(report.semanticStatus.status == "unavailable")
        #expect(report.safeNextCommands.contains("cider-cli item get note \(note.entityID.uuidString) --json"))
        #expect(report.safeNextCommands.contains("cider-cli item rebuild-chunks note \(note.entityID.uuidString) --json"))

        let dict = CiderCLI.itemSearchDiagnosticsReportToDict(report)
        #expect(dict["command"] as? String == "item.search-debug")
        #expect(dict["readOnly"] as? Bool == true)
        #expect(dict["changed"] as? Bool == false)
        #expect((dict["matchedChunks"] as? [[String: Any]])?.isEmpty == false)
        #expect((dict["semanticStatus"] as? [String: Any])?["status"] as? String == "unavailable")
        #expect((dict["safeNextCommands"] as? [String])?.contains("cider-cli item rebuild-chunks note \(note.entityID.uuidString) --json") == true)
    }

    @Test("search diagnostics return machine readable no match warnings")
    func searchDiagnosticsReturnNoMatchWarnings() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(note, title: "Ordinary recall note", relativePath: "Inbox/Notes/Ordinary recall note.md", into: db)

        let service = CiderItemContextService(database: db)
        let report = try service.searchDiagnostics("missing-zircon-token", limit: 10)

        #expect(report.exactMatches.isEmpty)
        #expect(report.matchedChunks.isEmpty)
        #expect(report.warnings.contains { $0.kind == "no_matches" })
        #expect(report.safeNextCommands.contains("cider-cli item search \"missing-zircon-token\" --limit 10 --json"))
    }

    @Test("search diagnostics identify missing and stale item chunk indexes")
    func searchDiagnosticsIdentifyMissingAndStaleIndexes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let missing = LibraryEntityRef(type: .note, entityID: UUID())
        let stale = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(missing, title: "Nebula missing index", relativePath: "Inbox/Notes/Nebula missing index.md", into: db)
        try insertItem(stale, title: "Nebula stale index", relativePath: "Inbox/Notes/Nebula stale index.md", into: db)

        let oldDate = Date(timeIntervalSince1970: 1_000)
        let newDate = Date(timeIntervalSince1970: 2_000)
        let updateItem = try db.prepare("UPDATE items SET updated_at = ? WHERE id = ?;")
        updateItem.bind(DatabaseHelpers.encode(newDate), at: 1)
            .bind(DatabaseHelpers.encode(stale.entityID), at: 2)
        try updateItem.step()

        let chunkStmt = try db.prepare("""
            INSERT INTO content_chunks (
                id, item_id, owner_type, owner_id, source, title, body,
                chunk_index, content_hash, metadata, created_at, updated_at
            )
            VALUES (?, ?, 'note', ?, 'test', 'Nebula stale index', 'old nebula body',
                    0, 'stale-hash', '{}', ?, ?);
            """)
        chunkStmt.bind(UUID().uuidString, at: 1)
            .bind(stale.entityID.uuidString, at: 2)
            .bind(stale.entityID.uuidString, at: 3)
            .bind(DatabaseHelpers.encode(oldDate), at: 4)
            .bind(DatabaseHelpers.encode(oldDate), at: 5)
        try chunkStmt.step()

        let service = CiderItemContextService(database: db)
        let report = try service.searchDiagnostics("Nebula", limit: 10)

        #expect(report.indexWarnings.contains {
            $0.kind == "missing_chunks" && $0.item?.id == missing.entityID
        })
        #expect(report.indexWarnings.contains {
            $0.kind == "stale_chunks" && $0.item?.id == stale.entityID
        })
        #expect(report.indexWarnings.contains {
            $0.safeRepairCommand == "cider-cli item rebuild-chunks note \(missing.entityID.uuidString) --json"
        })
        #expect(report.indexWarnings.contains {
            $0.safeRepairCommand == "cider-cli item rebuild-chunks note \(stale.entityID.uuidString) --json"
        })
    }

    @Test("search handles common Kanban acceptance terms alongside item matches")
    func searchHandlesCommonKanbanAcceptanceTermsAlongsideItemMatches() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        try insertItem(
            note,
            title: "Cutover acceptance text",
            relativePath: "Inbox/Notes/Cutover acceptance text.md",
            into: db
        )

        let store = SecondBrainStore(database: db)
        let cardOwner = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "board/card")
        try store.replaceChunks(owner: cardOwner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: nil,
                source: "kanban_notes",
                title: "Acceptance Criteria",
                body: "Focused CLI acceptance checks pass or produce scoped follow-up cards.",
                chunkIndex: 0
            )
        ])

        let service = CiderItemContextService(database: db, secondBrainStore: store)

        let singleTermMatches = try service.search("acceptance", limit: 10)
        #expect(singleTermMatches.contains {
            $0.kind == .item && $0.item?.id == note.entityID
        })
        #expect(singleTermMatches.contains {
            $0.kind == .chunk && $0.owner == cardOwner
        })

        let phraseMatches = try service.search("Cutover acceptance", limit: 10)
        #expect(phraseMatches.contains {
            $0.kind == .item && $0.item?.id == note.entityID
        })
    }

    @Test("space listing and search use native membership rather than folder paths")
    func spaceListingAndSearchUseNativeMembership() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let inSpace = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let outside = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(
            inSpace,
            title: "Steam Deck review",
            relativePath: "Inbox/Bookmarks/Steam Deck review.webloc",
            into: db
        )
        try insertItem(
            outside,
            title: "Steam invoice",
            relativePath: "Inbox/Bookmarks/Steam invoice.webloc",
            into: db
        )

        let spaceStore = CiderSpaceMembershipStore(database: db)
        try spaceStore.assign(
            item: inSpace,
            toSpaceID: "space-media",
            spaceName: "Media",
            reason: "Games and hardware belong in Media even while staged in Inbox.",
            confidence: 0.9,
            source: "space.test",
            actor: "agent"
        )
        let service = CiderItemContextService(database: db, spaceMembershipStore: spaceStore)

        let listed = try service.items(inSpaceID: "space-media")
        #expect(listed.map(\.id) == [inSpace.entityID])
        #expect(listed.first?.relativePath == "Inbox/Bookmarks/Steam Deck review.webloc")

        let filtered = try service.search("Steam", limit: 10, inSpaceID: "space-media")
        #expect(filtered.map(\.item?.id) == [inSpace.entityID])
        #expect(!filtered.contains { $0.item?.id == outside.entityID })

        let context = try service.context(for: inSpace)
        #expect(context.ownerRelations.contains { relation in
            relation.targetOwner == SecondBrainOwnerRef(ownerType: "space", ownerID: "space-media")
                && relation.relationType == "belongs_to_space"
                && relation.source == "space_memberships"
        })
    }

    @Test("agent context bundle is bounded and includes provenance review history and safe commands")
    func agentContextBundleIsBoundedAndActionable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let note = LibraryEntityRef(type: .note, entityID: UUID())
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        try insertItem(note, title: "Dentist follow-up", relativePath: "Inbox/Notes/Dentist follow-up.md", into: db)
        try insertItem(bookmark, title: "Dental insurance portal", relativePath: "Inbox/Bookmarks/Dental insurance portal.url", into: db)

        let store = SecondBrainStore(database: db)
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.entityID.uuidString)
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "summary",
                title: "Summary",
                body: "Call the dentist and confirm insurance before booking the follow-up appointment.",
                source: "projection",
                sortOrder: 0
            )
        )
        try store.upsertSection(
            SecondBrainSection(
                owner: owner,
                itemID: note.entityID.uuidString,
                sectionKey: "details",
                title: "Details",
                body: "This longer section should not be included when the section limit is one.",
                source: "projection",
                sortOrder: 1
            )
        )
        try store.replaceChunks(owner: owner, chunks: [
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "note-body",
                title: "Dentist follow-up chunk",
                body: "Call the dentist, verify the insurance portal, and ask whether the claim requires prior authorization.",
                chunkIndex: 0
            ),
            SecondBrainChunkDraft(
                sectionID: nil,
                itemID: note.entityID.uuidString,
                source: "note-body",
                title: "Extra chunk",
                body: "This chunk should be omitted by the max chunk limit.",
                chunkIndex: 1
            ),
        ])
        try store.recordRoutingDecision(
            SecondBrainRoutingDecision(
                owner: owner,
                itemID: note.entityID.uuidString,
                targetType: "folder",
                targetPath: "Health/Dental",
                confidence: 0.64,
                reason: "Health admin item, but target needs review.",
                status: "needs_review",
                actor: "agent",
                source: "routing.test"
            )
        )
        try store.recordAgentAction(
            SecondBrainAgentAction(
                owner: owner,
                itemID: note.entityID.uuidString,
                toolName: "cider-cli",
                actionType: "route",
                source: "agent.test",
                status: "suggested",
                summary: "Suggested routing to Health/Dental.",
                argumentsJSON: nil,
                resultJSON: nil
            )
        )
        let spaceStore = CiderSpaceMembershipStore(database: db)
        try spaceStore.assign(
            item: note,
            toSpaceID: "space-health",
            spaceName: "Health",
            reason: "Dental follow-up belongs in the Health meaning layer.",
            confidence: 0.88,
            source: "space.test",
            actor: "agent"
        )

        let linkService = ItemLinkService(database: db)
        try linkService.addDirectLink(from: note, to: bookmark)
        let service = CiderItemContextService(
            database: db,
            linkService: linkService,
            secondBrainStore: store,
            spaceMembershipStore: spaceStore
        )

        let packet = try service.agentContext(
            for: note,
            limits: CiderItemAgentContextLimits(
                maxSections: 1,
                maxChunks: 1,
                maxRelated: 1,
                maxHistory: 2,
                maxBodyCharacters: 48
            )
        )

        #expect(packet.item.id == note.entityID)
        #expect(packet.summary == "Call the dentist and confirm insurance before bo")
        #expect(packet.summary.count <= 48)
        #expect(packet.provenance.contains("item:note"))
        #expect(packet.provenance.contains("path:Inbox/Notes/Dentist follow-up.md"))
        #expect(packet.provenance.contains("space:Health"))
        #expect(packet.spaceMemberships.map(\.spaceName) == ["Health"])
        #expect(packet.spaceMemberships.first?.reason == "Dental follow-up belongs in the Health meaning layer.")
        #expect(packet.contentBlocks.map(\.title) == ["Summary", "Dentist follow-up chunk"])
        #expect(packet.contentBlocks.allSatisfy { $0.body.count <= 48 })
        #expect(packet.related.map(\.title) == ["Dental insurance portal"])
        #expect(packet.review?.status == "needs_review")
        #expect(packet.review?.targetPath == "Health/Dental")
        #expect(packet.surfacing.reason == "Health admin item, but target needs review.")
        #expect(packet.surfacing.urgency == "review")
        #expect(packet.surfacing.sourceSignal == "item_context")
        #expect(packet.surfacing.reviewState == "needs_review")
        #expect(packet.recentHistory.map(\.summary).contains("Suggested routing to Health/Dental."))
        #expect(packet.safeCommands.contains("cider-cli item get note \(note.entityID.uuidString) --json"))
        #expect(packet.safeCommands.contains("cider-cli item related note \(note.entityID.uuidString) --json"))
        #expect(packet.safeCommands.contains("cider-cli routing explain \(note.entityID.uuidString) --json"))
    }

    @Test("agent context uses shared reminder relevance for todo surfacing")
    func agentContextUsesReminderRelevanceForTodoSurfacing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let now = Date(timeIntervalSince1970: 1_745_084_400)
        let todoID = UUID()
        let todoRef = LibraryEntityRef(type: .todo, entityID: todoID)
        let todo = TodoCard(
            id: todoID,
            title: "Pay rent",
            dueDate: now,
            priority: .high,
            actionURLString: "https://rent.example.com",
            createdAt: now.addingTimeInterval(-86_400),
            updatedAt: now
        )
        try insertItem(todoRef, title: "Pay rent", relativePath: "Inbox/Todos/Pay rent.md", into: db)

        let service = CiderItemContextService(
            database: db,
            todoProvider: { [todo] },
            dateCardProvider: { [] },
            nowProvider: { now }
        )

        let packet = try service.agentContext(for: todoRef)

        #expect(packet.surfacing.reason == "due today")
        #expect(packet.surfacing.urgency == "today")
        #expect(packet.surfacing.sourceSignal == "reminder_relevance")
        #expect(packet.surfacing.reviewState == "ok")
        #expect(packet.surfacing.suggestedAction == "open action URL")
        #expect(packet.surfacing.actionURLString == "https://rent.example.com")
    }
}
