import AppKit
import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Capture Service Tests")
@MainActor
struct CiderCaptureServiceTests {
    private func makeTempVault() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-capture-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeTempDatabase(in vault: URL) throws -> CiderDatabase {
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = CiderDatabase()
        try db.open(at: dbURL)
        return db
    }

    private func expectQuietCaptureSafeCommands(for result: CiderCaptureResult) throws {
        let commands = try #require(result.toDictionary()["safeNextCommands"] as? [String])
        #expect(commands.first == "cider-cli item get \(result.item.type) \(result.item.id.uuidString) --json")
        #expect(!commands.contains("cider-cli routing explain \(result.item.id.uuidString) --json"))
        #expect(!commands.contains("cider-cli review list --item-type \(result.item.type) --state needs_review --limit 10 --json"))
    }

    private func expectDuplicateInspectionCommand(
        for result: CiderCaptureResult,
        existingItemID: UUID
    ) throws {
        let commands = try #require(result.toDictionary()["safeNextCommands"] as? [String])
        #expect(commands.contains("cider-cli item get \(result.item.type) \(existingItemID.uuidString) --json"))
    }

    private func withIsolatedVault<T>(
        _ body: (CiderDatabase, VaultBookmarkService, NotesStorage, TodoCardStorage, VaultFileStorage) throws -> T
    ) throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let db = try makeTempDatabase(in: vault)
        defer {
            db.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        let bookmarks = VaultBookmarkService(database: db, schedulesEnrichment: false)
        let notes = NotesStorage(database: db)
        let todos = TodoCardStorage(database: db)
        let files = VaultFileStorage(database: db)
        return try body(db, bookmarks, notes, todos, files)
    }

    @Test("capture source context records capture event and graph relation")
    func captureSourceContextRecordsEventAndRelation() throws {
        try withIsolatedVault { db, _, notes, _, _ in
            let service = CiderCaptureService(notesStorage: notes, database: db)
            let result = try service.addNoteCapture(
                title: "Telegram idea",
                content: "Ship provenance",
                folderID: nil,
                sourceContext: CaptureSourceContext(
                    surface: "telegram",
                    channel: "telegram",
                    channelID: "chat-1",
                    threadID: nil,
                    messageID: "msg-9",
                    senderID: "user-7",
                    senderName: "Erik",
                    originalText: "Ship provenance",
                    attachments: [],
                    metadata: ["bot": "hermes"]
                )
            )

            let eventID = try #require(result.captureEventID)
            #expect(result.captureEventOwner == SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString))
            let dict = result.toDictionary()
            #expect(dict["captureEventID"] as? String == eventID.uuidString)
            let sourceContext = try #require(dict["sourceContext"] as? [String: Any])
            #expect(sourceContext["surface"] as? String == "telegram")
            #expect(sourceContext["messageID"] as? String == "msg-9")

            let stmt = try db.prepare("""
                SELECT surface, channel, channel_id, message_id, sender_id, sender_name, source_text, metadata
                FROM capture_events
                WHERE id = ?;
                """)
            stmt.bind(eventID.uuidString, at: 1)
            #expect(try stmt.step())
            #expect(stmt.string(at: 0) == "telegram")
            #expect(stmt.string(at: 1) == "telegram")
            #expect(stmt.string(at: 2) == "chat-1")
            #expect(stmt.string(at: 3) == "msg-9")
            #expect(stmt.string(at: 4) == "user-7")
            #expect(stmt.string(at: 5) == "Erik")
            #expect(stmt.string(at: 6) == "Ship provenance")

            let relations = try SecondBrainStore(database: db).outgoingRelations(
                for: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
            )
            #expect(relations.count == 1)
            #expect(relations[0].relationType == "produced_item")
            #expect(relations[0].targetOwner == SecondBrainOwnerRef(ownerType: "note", ownerID: result.item.id.uuidString))
        }
    }

    @Test("default capture service persists provenance through shared database")
    func defaultCaptureServicePersistsProvenanceThroughSharedDatabase() throws {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        CiderDatabase.shared.close()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CiderDatabase.shared.open(at: dbURL)
        defer {
            CiderDatabase.shared.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }

        let notes = NotesStorage(database: CiderDatabase.shared)
        let service = CiderCaptureService(notesStorage: notes)
        let result = try service.addNoteCapture(
            title: "Shared DB capture",
            content: "Default capture service should persist provenance",
            folderID: nil,
            sourceContext: CaptureSourceContext(surface: "test-harness")
        )

        let eventID = try #require(result.captureEventID)
        let statement = try CiderDatabase.shared.prepare("SELECT surface FROM capture_events WHERE id = ?;")
        statement.bind(eventID.uuidString, at: 1)
        #expect(try statement.step())
        #expect(statement.string(at: 0) == "test-harness")
    }

    @Test("explicitly captured markdown files remain visible after vault file scan")
    func capturedMarkdownFileRemainsVisibleAfterVaultFileScan() throws {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        CiderDatabase.shared.close()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let dbURL = vault.appendingPathComponent(".cider/cider.db")
        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try CiderDatabase.shared.open(at: dbURL)
        let vaultFileService = VaultFileService.shared
        vaultFileService._resetIDMapForTesting()
        vaultFileService._setFilesForTesting([])
        defer {
            vaultFileService._resetIDMapForTesting()
            vaultFileService._setFilesForTesting([])
            CiderDatabase.shared.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }

        let sourceURL = vault.appendingPathComponent("source.md")
        try "Captured markdown body".write(to: sourceURL, atomically: true, encoding: .utf8)

        let storage = VaultFileStorage(database: CiderDatabase.shared)
        let capture = CiderCaptureService(vaultFileStorage: storage, database: CiderDatabase.shared)
        let result = try capture.addFileCapture(
            sourcePath: sourceURL.path,
            title: nil,
            folderID: nil
        )

        vaultFileService.scan()

        #expect(result.item.type == "vaultFile")
        #expect(result.item.relativePath == "Inbox/Files/source.md")
        #expect(vaultFileService.files.contains { $0.id == result.item.id })
        #expect(vaultFileService.files.count == 1)
    }

    private func withIsolatedVault<T>(
        _ body: (CiderDatabase, VaultBookmarkService, NotesStorage, TodoCardStorage, VaultFileStorage) async throws -> T
    ) async throws -> T {
        let previousOverride = StoragePaths.vaultOverride
        let vault = try makeTempVault()
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        StoragePaths.ensureVaultStructure()
        let db = try makeTempDatabase(in: vault)
        defer {
            db.close()
            StoragePaths.vaultOverride = previousOverride
            StoragePaths.invalidateCachedDirectory()
            try? FileManager.default.removeItem(at: vault)
        }
        let bookmarks = VaultBookmarkService(database: db, schedulesEnrichment: false)
        let notes = NotesStorage(database: db)
        let todos = TodoCardStorage(database: db)
        let files = VaultFileStorage(database: db)
        return try await body(db, bookmarks, notes, todos, files)
    }

    private func withIsolatedVaultDomains<T>(
        _ body: (
            CiderDatabase,
            VaultBookmarkService,
            NotesStorage,
            TodoCardStorage,
            DateCardStorage,
            ContactStorage,
            VaultFileStorage
        ) throws -> T
    ) throws -> T {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let dateCards = DateCardStorage(database: db)
            let contacts = ContactStorage(database: db)
            return try body(db, bookmarks, notes, todos, dateCards, contacts, files)
        }
    }

    @Test("capture add stores a URL in Inbox immediately and returns agent state")
    func captureAddStoresURLImmediately() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )

            let result = try service.add("https://example.com/articles/42?utm_source=test")

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "url")
            #expect(result.source.url == "https://example.com/articles/42?utm_source=test")
            #expect(result.source.itemID == result.item.id)
            #expect(result.source.itemType == "bookmark")
            #expect(result.item.type == "bookmark")
            #expect(result.item.title == "Example.Com")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Bookmarks/") == true)
            #expect(result.enrichment.status == "pending")
            #expect(result.duplicate.status == "new")
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Bookmarks")
            #expect(result.routing.decisionID != nil)
            #expect(result.nextSafeAction == "enrich")
            let resultDict = result.toDictionary()
            #expect(resultDict["saved"] as? Bool == true)
            #expect(resultDict["useful"] as? Bool == false)
            #expect(resultDict["needsReview"] as? Bool == true)
            #expect(resultDict["requiresHumanReview"] as? Bool == true)
            #expect(resultDict["needsRouting"] as? Bool == true)
            #expect(resultDict["needsEnrichment"] as? Bool == true)
            #expect(resultDict["agentMayRoute"] as? Bool == false)
            #expect(resultDict["confidence"] as? Double == 0)
            #expect(resultDict["recommendedNextAction"] as? String == "review_route")
            #expect((resultDict["blockingIssues"] as? [String])?.contains("routing_needs_review") == true)
            #expect(resultDict["humanQuestion"] as? String != nil)
            let nextActions = try #require(resultDict["nextActions"] as? [[String: Any]])
            #expect(nextActions.first?["action"] as? String == "review_route")
            #expect(nextActions.first?["readOnly"] as? Bool == true)
            #expect(nextActions.first?["requiresApproval"] as? Bool == true)
            try expectQuietCaptureSafeCommands(for: result)

            let stored = bookmarks.bookmarks.first(where: { $0.id == result.item.id })
            #expect(stored?.urlString == "https://example.com/articles/42?utm_source=test")

            let itemStatement = try db.prepare("SELECT type, title, relative_path FROM items WHERE id = ?;")
            itemStatement.bind(result.item.id.uuidString, at: 1)
            #expect(try itemStatement.step())
            #expect(itemStatement.string(at: 0) == "bookmark")
            #expect(itemStatement.string(at: 1) == "Example.Com")
            #expect(itemStatement.string(at: 2).hasPrefix("Inbox/Bookmarks/"))

            let bookmarkStatement = try db.prepare("SELECT url FROM bookmarks WHERE item_id = ?;")
            bookmarkStatement.bind(result.item.id.uuidString, at: 1)
            #expect(try bookmarkStatement.step())
            #expect(bookmarkStatement.string(at: 0) == "https://example.com/articles/42?utm_source=test")

            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.item.id == result.item.id)
            #expect(explanation.latestDecision?.id == result.routing.decisionID)
            #expect(explanation.latestDecision?.target.relativePath == "Inbox/Bookmarks")
            #expect(explanation.latestDecision?.reviewState == "needs_review")
            #expect(explanation.latestDecision?.actor == "agent")
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("bookmark capture stages obvious Space and project intent without routing")
    func bookmarkCaptureStagesObviousSpaceAndProjectIntentWithoutRouting() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )

            let rottenTomatoes = try service.addBookmarkCapture(
                urlString: "https://www.rottentomatoes.com/tv/the_vampire_lestat/s01",
                title: "The Vampire Lestat: Season 1 | Rotten Tomatoes",
                folderID: nil
            ).toDictionary()
            let rottenIntent = try #require(rottenTomatoes["spaceIntent"] as? [String: Any])
            #expect(rottenIntent["status"] as? String == "staged")
            #expect(rottenIntent["spaceName"] as? String == "Media")
            #expect(rottenIntent["area"] as? String == "Shows")
            #expect(rottenIntent["storageDestination"] as? String == "Inbox/Bookmarks")
            #expect(rottenIntent["wouldRouteWithoutReview"] as? Bool == false)
            let rottenRouting = try #require(rottenTomatoes["routing"] as? [String: Any])
            #expect((rottenRouting["candidateTarget"] as? [String: Any])?["relativePath"] as? String == "Inbox/Bookmarks")
            #expect(rottenRouting["reviewNeeded"] as? Bool == true)

            let steam = try service.addBookmarkCapture(
                urlString: "https://store.steampowered.com/app/1118520/Paralives/",
                title: "Paralives on Steam",
                folderID: nil
            ).toDictionary()
            let steamIntent = try #require(steam["spaceIntent"] as? [String: Any])
            #expect(steamIntent["spaceName"] as? String == "Media")
            #expect(steamIntent["area"] as? String == "Games")

            let projectReference = try service.addBookmarkCapture(
                urlString: "https://x.com/openaidevs/status/2062599291479478275?s=12",
                title: "OpenAI Developers Codex iOS app loop",
                folderID: nil
            ).toDictionary()
            let projectIntent = try #require(projectReference["projectIntent"] as? [String: Any])
            #expect(projectIntent["status"] as? String == "staged")
            #expect(projectIntent["projectName"] as? String == "Cider iOS")
            #expect(projectIntent["storageDestination"] as? String == "Inbox/Bookmarks")
            #expect(projectIntent["wouldRouteWithoutReview"] as? Bool == false)
            let staging = try #require(projectReference["intentStaging"] as? [String: Any])
            #expect(staging["status"] as? String == "staged")
            #expect(staging["reviewNeeded"] as? Bool == true)
            #expect(projectReference["needsIntentApproval"] as? Bool == true)
            #expect(projectReference["recommendedNextAction"] as? String == "review_intent")

            let recipeReference = try service.addBookmarkCapture(
                urlString: "https://www.allrecipes.com/recipe/24074/alysias-basic-meat-lasagna/",
                title: "Alysia's Basic Meat Lasagna Recipe",
                folderID: nil
            ).toDictionary()
            let recipeIntent = try #require(recipeReference["spaceIntent"] as? [String: Any])
            #expect(recipeIntent["spaceName"] as? String == "Recipes")
            #expect(recipeIntent["rootRelativePath"] as? String == "Spaces/Recipes")
            #expect(recipeIntent["storageDestination"] as? String == "Inbox/Bookmarks")
        }
    }

    @Test("url capture immediately indexes searchable chunks")
    func urlCaptureImmediatelyIndexesSearchableChunks() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )

            let result = try service.add("https://example.com/immediate-bookmark-index-token")

            let matches = try SecondBrainStore(database: db).searchChunks(
                query: "immediate-bookmark-index-token",
                limit: 5
            )
            #expect(matches.first?.owner == SecondBrainOwnerRef(ownerType: "bookmark", ownerID: result.item.id.uuidString))
        }
    }

    @Test("capture add returns duplicate state for an existing URL")
    func captureAddReportsDuplicate() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let first = try service.add("https://example.com/duplicate")
            let second = try service.add("https://example.com/duplicate")

            #expect(bookmarks.bookmarks.count == 1)
            #expect(second.item.id == first.item.id)
            #expect(second.duplicate.status == "duplicate")
            #expect(second.duplicate.existingItemID == first.item.id)
            #expect(second.routing.reviewNeeded == true)
            #expect(second.nextSafeAction == "inspect_existing_item")
            try expectDuplicateInspectionCommand(for: second, existingItemID: first.item.id)

            let auditEntries = MutationAuditService(database: db).loadEntries()
            let duplicateAudit = auditEntries.first {
                $0.itemID == first.item.id && $0.action == "deduplicate_url_capture"
            }
            #expect(duplicateAudit?.itemType == "bookmark")
            #expect(duplicateAudit?.metadata["incomingURL"] == "https://example.com/duplicate")
            #expect(duplicateAudit?.metadata["canonicalURL"] == "https://example.com/duplicate")
        }
    }

    @Test("todo capture reuses an existing open todo with the same title")
    func todoCaptureReusesExistingOpenTodoWithSameTitle() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let title = "Pay Labcorp bill — invoice 91885413 ($5.78)"
            let first = try service.addTodoCapture(
                title: title,
                sourceText: "Labcorp bill from screenshot.",
                dueDate: nil,
                priority: nil,
                folderID: nil
            )
            let second = try service.addTodoCapture(
                title: title,
                sourceText: "Pay Labcorp bill",
                dueDate: nil,
                priority: nil,
                folderID: nil
            )

            #expect(todos.todoCards.count == 1)
            #expect(second.item.id == first.item.id)
            #expect(second.duplicate.status == "duplicate")
            #expect(second.duplicate.existingItemID == first.item.id)
            #expect(second.nextSafeAction == "inspect_existing_item")

            let duplicateFiles = try FileManager.default.contentsOfDirectory(
                at: StoragePaths.cachedInboxSubdirectoryURL(for: .todos),
                includingPropertiesForKeys: nil
            )
            .filter { $0.pathExtension == "ics" }
            #expect(duplicateFiles.count == 1)
        }
    }

    @Test("capture result dictionary refreshes bookmark enrichment from final stored item")
    func captureResultDictionaryRefreshesBookmarkEnrichment() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let result = try service.add("https://example.com/enriched")
            let enrichedAt = Date(timeIntervalSince1970: 1_775_000_000)
            let finalBookmark = Bookmark(
                id: result.item.id,
                title: "Enriched Capture Title",
                urlString: "https://example.com/enriched",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/Enriched Capture Title.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )

            let dict = result.toDictionary(finalBookmark: finalBookmark)
            let item = try #require(dict["item"] as? [String: Any])
            let enrichment = try #require(dict["enrichment"] as? [String: Any])

            #expect(item["title"] as? String == "Enriched Capture Title")
            #expect(item["relativePath"] as? String == "Inbox/Bookmarks/Enriched Capture Title.webloc")
            #expect(enrichment["status"] as? String == "complete")
            #expect(enrichment["isEnriching"] as? Bool == false)
            #expect(enrichment["titleState"] as? String == "enriched")
            #expect(enrichment["lastEnrichedAt"] as? String != nil)
        }
    }

    @Test("final bookmark receipt refreshes indexing and separates intent approval from enrichment")
    func finalBookmarkReceiptRefreshesIndexingAndSeparatesIntentApprovalFromEnrichment() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let result = try service.add(
                "https://www.tiktok.com/@maker/video/12345",
                title: "Tiktok.Com"
            )
            let thumbnailPath = ".thumbnails/tiktok-modular-shelf.png"
            let thumbnailURL = StoragePaths.cachedDirectoryURL(for: .bookmarks)
                .appendingPathComponent(thumbnailPath)
            try FileManager.default.createDirectory(
                at: thumbnailURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("thumbnail".utf8).write(to: thumbnailURL)
            let enrichedAt = Date(timeIntervalSince1970: 1_775_000_000)
            let finalBookmark = Bookmark(
                id: result.item.id,
                title: "3D printed modular shelf for Anycubic Kobra",
                urlString: "https://www.tiktok.com/@maker/video/12345",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                notes: "3D printed modular shelf for Anycubic Kobra\n\nBy maker\nVia TikTok",
                tags: ["tiktok", "3d-printing"],
                thumbnailRemoteURLString: "https://example.com/tiktok.jpg",
                thumbnailRelativePath: thumbnailPath,
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/3D printed modular shelf for Anycubic Kobra.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )

            let dict = result.toDictionary(finalBookmark: finalBookmark)
            let indexing = try #require(dict["indexing"] as? [String: Any])
            let chunks = try #require(indexing["chunks"] as? [[String: Any]])
            let safeNextCommands = try #require(dict["safeNextCommands"] as? [String])

            #expect(dict["needsEnrichment"] as? Bool == false)
            #expect(dict["needsIntentApproval"] as? Bool == true)
            #expect(dict["recommendedNextAction"] as? String == "review_intent")
            #expect(chunks.first?["title"] as? String == "3D printed modular shelf for Anycubic Kobra")
            #expect(chunks.allSatisfy { $0["title"] as? String != "Tiktok.Com" })
            #expect(safeNextCommands.contains("cider-cli item apply-intent bookmark \(result.item.id.uuidString) --intent space --json"))
        }
    }

    @Test("capture result dictionary reports visible bookmark quality")
    func captureResultDictionaryReportsVisibleBookmarkQuality() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let result = try service.add("https://github.com/nodes-app/swift-markdown-engine")
            let enrichedAt = Date(timeIntervalSince1970: 1_775_000_000)
            let degradedBookmark = Bookmark(
                id: result.item.id,
                title: "Github.Com",
                urlString: "https://github.com/nodes-app/swift-markdown-engine",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/Github.Com.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )
            let degradedDict = result.toDictionary(finalBookmark: degradedBookmark)
            let degradedQuality = try #require(degradedDict["captureQuality"] as? [String: Any])
            let degradedReasons = try #require(degradedQuality["degradedReasons"] as? [String])
            let degradedSafeNextCommands = try #require(degradedDict["safeNextCommands"] as? [String])

            #expect(degradedQuality["metadataComplete"] as? Bool == true)
            #expect(degradedQuality["cardComplete"] as? Bool == false)
            #expect(degradedQuality["semanticStatus"] as? String == "degraded")
            #expect(degradedQuality["titleQuality"] as? String == "generic")
            #expect(degradedQuality["thumbnailStatus"] as? String == "missing")
            #expect(degradedQuality["pathStatus"] as? String == "current")
            #expect(degradedQuality["visibleCardCurrent"] as? Bool == false)
            #expect(degradedReasons.contains("title_generic"))
            #expect(degradedReasons.contains("card_image_missing"))
            #expect(degradedSafeNextCommands.contains("cider-cli review enrich \(result.item.id.uuidString) --actor agent --timeout 20 --json"))
            #expect(degradedSafeNextCommands.contains("cider-cli item rebuild-chunks bookmark \(result.item.id.uuidString) --json"))

            let stalePathBookmark = Bookmark(
                id: result.item.id,
                title: "GitHub - nodes-app/swift-markdown-engine",
                urlString: "https://github.com/nodes-app/swift-markdown-engine",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                thumbnailRelativePath: ".thumbnails/swift-markdown-engine.jpg",
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/Github.Com (2).webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )
            let stalePathDict = result.toDictionary(finalBookmark: stalePathBookmark)
            let stalePathQuality = try #require(stalePathDict["captureQuality"] as? [String: Any])
            let stalePathReasons = try #require(stalePathQuality["degradedReasons"] as? [String])

            #expect(stalePathQuality["semanticStatus"] as? String == "degraded")
            #expect(stalePathQuality["pathStatus"] as? String == "stale_or_generic")
            #expect(stalePathQuality["visibleCardCurrent"] as? Bool == false)
            #expect(stalePathReasons.contains("path_stale_or_generic"))

            let missingThumbnailBookmark = Bookmark(
                id: result.item.id,
                title: "GitHub - nodes-app/swift-markdown-engine",
                urlString: "https://github.com/nodes-app/swift-markdown-engine",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                thumbnailRelativePath: ".thumbnails/missing-swift-markdown-engine.jpg",
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/GitHub - nodes-app-swift-markdown-engine.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )
            let emptyThumbnailURL = StoragePaths.cachedVaultDirectoryURL
                .appendingPathComponent(".thumbnails/missing-swift-markdown-engine.jpg")
            try FileManager.default.createDirectory(
                at: emptyThumbnailURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: emptyThumbnailURL)
            let missingThumbnailDict = result.toDictionary(finalBookmark: missingThumbnailBookmark)
            let missingThumbnailQuality = try #require(missingThumbnailDict["captureQuality"] as? [String: Any])
            let missingThumbnailReasons = try #require(missingThumbnailQuality["degradedReasons"] as? [String])

            #expect(missingThumbnailQuality["semanticStatus"] as? String == "degraded")
            #expect(missingThumbnailQuality["thumbnailStatus"] as? String == "missing")
            #expect(missingThumbnailQuality["visibleCardCurrent"] as? Bool == false)
            #expect(missingThumbnailReasons.contains("card_image_missing"))

            let remoteOnlyThumbnailBookmark = Bookmark(
                id: result.item.id,
                title: "GitHub - nodes-app/swift-markdown-engine",
                urlString: "https://github.com/nodes-app/swift-markdown-engine",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                thumbnailRemoteURLString: "https://example.com/remote-only-thumbnail.jpg",
                thumbnailRelativePath: ".thumbnails/remote-only-swift-markdown-engine.jpg",
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/GitHub - nodes-app-swift-markdown-engine.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )
            let remoteOnlyThumbnailURL = StoragePaths.cachedVaultDirectoryURL
                .appendingPathComponent(".thumbnails/remote-only-swift-markdown-engine.jpg")
            try Data().write(to: remoteOnlyThumbnailURL)
            let remoteOnlyDict = result.toDictionary(finalBookmark: remoteOnlyThumbnailBookmark)
            let remoteOnlyQuality = try #require(remoteOnlyDict["captureQuality"] as? [String: Any])
            let remoteOnlyReasons = try #require(remoteOnlyQuality["degradedReasons"] as? [String])

            #expect(remoteOnlyQuality["semanticStatus"] as? String == "degraded")
            #expect(remoteOnlyQuality["thumbnailStatus"] as? String == "remote_only")
            #expect(remoteOnlyQuality["cardComplete"] as? Bool == false)
            #expect(remoteOnlyQuality["visibleCardCurrent"] as? Bool == false)
            #expect(remoteOnlyReasons.contains("card_image_not_local"))

            let cachedBookmarkThumbnailPath = ".thumbnails/cached-bookmark-swift-markdown-engine.jpg"
            let cachedBookmarkThumbnailURL = StoragePaths.cachedDirectoryURL(for: .bookmarks)
                .appendingPathComponent(cachedBookmarkThumbnailPath)
            try FileManager.default.createDirectory(
                at: cachedBookmarkThumbnailURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("cached bookmark thumbnail".utf8).write(to: cachedBookmarkThumbnailURL)
            let cachedBookmarkThumbnail = Bookmark(
                id: result.item.id,
                title: "GitHub - nodes-app/swift-markdown-engine",
                urlString: "https://github.com/nodes-app/swift-markdown-engine",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                thumbnailRemoteURLString: "https://example.com/remote-thumbnail.jpg",
                thumbnailRelativePath: cachedBookmarkThumbnailPath,
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/GitHub - nodes-app-swift-markdown-engine.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )
            let cachedThumbnailDict = result.toDictionary(finalBookmark: cachedBookmarkThumbnail)
            let cachedThumbnailQuality = try #require(cachedThumbnailDict["captureQuality"] as? [String: Any])
            let cachedThumbnailReasons = try #require(cachedThumbnailQuality["degradedReasons"] as? [String])

            #expect(cachedThumbnailQuality["thumbnailStatus"] as? String == "local")
            #expect(!cachedThumbnailReasons.contains("card_image_not_local"))

            let thumbnailURL = StoragePaths.cachedVaultDirectoryURL
                .appendingPathComponent(".thumbnails/swift-markdown-engine.jpg")
            try FileManager.default.createDirectory(
                at: thumbnailURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("thumbnail".utf8).write(to: thumbnailURL)

            let richBookmark = Bookmark(
                id: result.item.id,
                title: "GitHub - nodes-app/swift-markdown-engine",
                urlString: "https://github.com/nodes-app/swift-markdown-engine",
                createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                thumbnailRelativePath: ".thumbnails/swift-markdown-engine.jpg",
                metadataUpdatedAt: enrichedAt,
                relativePath: "Inbox/Bookmarks/GitHub - nodes-app-swift-markdown-engine.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: enrichedAt
            )
            let richDict = result.toDictionary(finalBookmark: richBookmark)
            let richQuality = try #require(richDict["captureQuality"] as? [String: Any])
            let richReasons = try #require(richQuality["degradedReasons"] as? [String])

            #expect(richQuality["metadataComplete"] as? Bool == true)
            #expect(richQuality["cardComplete"] as? Bool == true)
            #expect(richQuality["semanticStatus"] as? String == "complete")
            #expect(richQuality["titleQuality"] as? String == "rich")
            #expect(richQuality["thumbnailStatus"] as? String == "local")
            #expect(richQuality["pathStatus"] as? String == "current")
            #expect(richQuality["visibleCardCurrent"] as? Bool == true)
            #expect(richReasons.isEmpty)
        }
    }

    @Test("capture quality dogfood fixtures cover stale external bookmark receipts")
    func captureQualityDogfoodFixturesCoverStaleExternalBookmarkReceipts() throws {
        struct Fixture {
            let url: String
            let genericTitle: String
            let richTitle: String
        }

        let fixtures = [
            Fixture(
                url: "https://www.kite.video/",
                genericTitle: "Kite.Video",
                richTitle: "Kite Video Capture Platform"
            ),
            Fixture(
                url: "https://store.steampowered.com/app/1118520/Paralives/",
                genericTitle: "Store.Steampowered.Com",
                richTitle: "Paralives on Steam"
            ),
            Fixture(
                url: "https://www.8bitdo.com/",
                genericTitle: "8Bitdo.Com",
                richTitle: "8BitDo Ultimate Controller"
            ),
            Fixture(
                url: "https://store.steampowered.com/app/3060070/MyDockFinder/",
                genericTitle: "Store.Steampowered.Com",
                richTitle: "MyDockFinder on Steam"
            ),
            Fixture(
                url: "https://www.remio.ai/",
                genericTitle: "Remio.Ai",
                richTitle: "remio AI Assistant"
            ),
        ]

        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            for fixture in fixtures {
                let result = try service.add(fixture.url)
                let enrichedAt = Date(timeIntervalSince1970: 1_775_000_000)

                let staleBookmark = Bookmark(
                    id: result.item.id,
                    title: fixture.genericTitle,
                    urlString: fixture.url,
                    createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                    updatedAt: Date(timeIntervalSince1970: 1_774_999_500),
                    metadataUpdatedAt: enrichedAt,
                    relativePath: "Inbox/Bookmarks/\(fixture.genericTitle).webloc",
                    enrichmentStatus: "complete",
                    lastEnrichedAt: enrichedAt
                )
                let staleDict = result.toDictionary(finalBookmark: staleBookmark)
                let staleQuality = try #require(staleDict["captureQuality"] as? [String: Any])
                let staleReasons = try #require(staleQuality["degradedReasons"] as? [String])
                let staleSafeNextCommands = try #require(staleDict["safeNextCommands"] as? [String])

                #expect(staleQuality["semanticStatus"] as? String == "degraded")
                #expect(staleQuality["visibleCardCurrent"] as? Bool == false)
                #expect(staleReasons.contains("title_generic"))
                #expect(staleReasons.contains("card_image_missing"))
                #expect(staleSafeNextCommands.contains("cider-cli review enrich \(result.item.id.uuidString) --actor agent --timeout 20 --json"))
                #expect(staleSafeNextCommands.contains("cider-cli item rebuild-chunks bookmark \(result.item.id.uuidString) --json"))

                let thumbnailPath = ".thumbnails/\(result.item.id.uuidString).jpg"
                let thumbnailURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(thumbnailPath)
                try FileManager.default.createDirectory(
                    at: thumbnailURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("thumbnail-\(fixture.richTitle)".utf8).write(to: thumbnailURL)
                let richFilename = BookmarkFileService.shared.sanitizedFilename(fixture.richTitle)
                let richBookmark = Bookmark(
                    id: result.item.id,
                    title: fixture.richTitle,
                    urlString: fixture.url,
                    createdAt: Date(timeIntervalSince1970: 1_774_999_000),
                    updatedAt: Date(timeIntervalSince1970: 1_775_000_100),
                    thumbnailRelativePath: thumbnailPath,
                    metadataUpdatedAt: enrichedAt,
                    relativePath: "Inbox/Bookmarks/\(richFilename).webloc",
                    enrichmentStatus: "complete",
                    lastEnrichedAt: enrichedAt
                )
                let richDict = result.toDictionary(finalBookmark: richBookmark)
                let richQuality = try #require(richDict["captureQuality"] as? [String: Any])
                let richReasons = try #require(richQuality["degradedReasons"] as? [String])

                #expect(richQuality["semanticStatus"] as? String == "complete")
                #expect(richQuality["visibleCardCurrent"] as? Bool == true)
                #expect(richQuality["titleQuality"] as? String == "rich")
                #expect(richQuality["thumbnailStatus"] as? String == "local")
                #expect(richQuality["pathStatus"] as? String == "current")
                #expect(richReasons.isEmpty)
            }
        }
    }

    @Test("capture add duplicate preserves existing bookmark location when no folder is supplied")
    func captureAddDuplicatePreservesExistingLocation() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let existingFolderID = UUID()
            let existingID = UUID()
            let existing = Bookmark(
                id: existingID,
                title: "Already Routed",
                urlString: "https://example.com/already-routed",
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000),
                folderID: existingFolderID,
                relativePath: nil
            )
            let folder = VaultFolder(id: existingFolderID, relativePath: "Saved/Bookmarks")
            VaultFolderService(database: db).persistToDatabase(db, folder: folder)
            bookmarks.persistBookmarkToDatabase(db, bookmark: existing)
            bookmarks.loadBookmarksFromDatabase(db)

            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let result = try service.add("https://example.com/already-routed")

            #expect(result.duplicate.status == "duplicate")
            #expect(result.item.id == existingID)
            #expect(bookmarks.bookmarks.count == 1)
            #expect(bookmarks.bookmarks.first?.folderID == existingFolderID)

            let reloaded = VaultBookmarkService(database: db, schedulesEnrichment: false)
            reloaded.loadBookmarksFromDatabase(db)
            #expect(reloaded.bookmarks.first?.folderID == existingFolderID)
        }
    }

    @Test("duplicate URL capture does not downgrade rich canonical metadata with a generic title")
    func duplicateURLCaptureDoesNotDowngradeRichCanonicalMetadataWithGenericTitle() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let existingID = UUID()
            let existing = Bookmark(
                id: existingID,
                title: "Sharks Loved This TINY Charger",
                urlString: "https://www.tiktok.com/@wealth/video/12345?is_from_webapp=1&sender_device=pc",
                createdAt: Date(timeIntervalSince1970: 1_000),
                updatedAt: Date(timeIntervalSince1970: 2_000),
                notes: "Sharks Loved This TINY Charger\n\nBy wealth\nVia TikTok",
                tags: ["tiktok"],
                thumbnailRemoteURLString: "https://p16-sign-va.tiktokcdn.com/example.jpeg",
                metadataUpdatedAt: Date(timeIntervalSince1970: 2_000),
                relativePath: "Inbox/Bookmarks/Sharks Loved This TINY Charger.webloc",
                enrichmentStatus: "complete",
                lastEnrichedAt: Date(timeIntervalSince1970: 2_000)
            )
            bookmarks.persistBookmarkToDatabase(db, bookmark: existing)
            bookmarks.loadBookmarksFromDatabase(db)

            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let result = try service.add(
                "https://www.tiktok.com/@wealth/video/12345?sender_device=pc&is_from_webapp=1",
                title: "Tiktok.Com"
            )

            #expect(result.duplicate.status == "duplicate")
            #expect(result.item.id == existingID)
            let captured = try #require(bookmarks.bookmarks.first)
            #expect(captured.title == "Sharks Loved This TINY Charger")
            #expect(captured.notes.contains("By wealth"))
            #expect(captured.thumbnailRemoteURLString == "https://p16-sign-va.tiktokcdn.com/example.jpeg")
            #expect(captured.relativePath == "Inbox/Bookmarks/Sharks Loved This TINY Charger.webloc")

            let reloaded = VaultBookmarkService(database: db, schedulesEnrichment: false)
            reloaded.loadBookmarksFromDatabase(db)
            #expect(reloaded.bookmarks.first?.title == "Sharks Loved This TINY Charger")
        }
    }

    @Test("capture wait holds for late canonical metadata convergence")
    func captureWaitHoldsForLateCanonicalMetadataConvergence() throws {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        var state = CiderCLI.BookmarkNativeCaptureWaitState()
        let initial = Bookmark(
            id: UUID(),
            title: "Tiktok.Com",
            urlString: "https://www.tiktok.com/@wealth/video/12345?is_from_webapp=1&sender_device=pc",
            createdAt: startedAt,
            updatedAt: startedAt
        )
        let enriched = Bookmark(
            id: initial.id,
            title: "Sharks Loved This TINY Charger",
            urlString: "https://www.tiktok.com/@wealth/video/12345?sender_device=pc&is_from_webapp=1",
            createdAt: Date(timeIntervalSince1970: 2_000),
            updatedAt: Date(timeIntervalSince1970: 3_000),
            notes: "Sharks Loved This TINY Charger\n\nBy wealth\nVia TikTok",
            tags: ["tiktok"],
            thumbnailRemoteURLString: "https://p16-sign-va.tiktokcdn.com/example.jpeg",
            metadataUpdatedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Inbox/Bookmarks/Sharks Loved This TINY Charger.webloc",
            enrichmentStatus: "complete",
            lastEnrichedAt: startedAt.addingTimeInterval(1.2)
        )

        #expect(
            CiderCLI.shouldReturnNativeBookmarkCapture(
                bookmark: initial,
                state: &state,
                startedAt: startedAt,
                now: startedAt,
                timeout: 2
            ) == false
        )
        state.polls += 1

        #expect(
            CiderCLI.shouldReturnNativeBookmarkCapture(
                bookmark: enriched,
                state: &state,
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(0.7),
                timeout: 2
            ) == false
        )
        #expect(state.candidateFirstSeenAt == startedAt.addingTimeInterval(0.7))
        state.polls += 1

        #expect(
            CiderCLI.shouldReturnNativeBookmarkCapture(
                bookmark: enriched,
                state: &state,
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(1.7),
                timeout: 2
            )
        )
    }

    @Test("capture wait does not settle before enrichment completion")
    func captureWaitDoesNotSettleBeforeEnrichmentCompletion() throws {
        let startedAt = Date(timeIntervalSince1970: 10_000)
        var state = CiderCLI.BookmarkNativeCaptureWaitState(
            sawEnrichmentRunning: true,
            polls: 3
        )
        let metadataOnly = Bookmark(
            id: UUID(),
            title: "GitHub - nodes-app/swift-markdown-engine",
            urlString: "https://github.com/nodes-app/swift-markdown-engine",
            createdAt: startedAt,
            updatedAt: startedAt.addingTimeInterval(1),
            thumbnailRemoteURLString: "https://opengraph.githubassets.com/example",
            metadataUpdatedAt: startedAt.addingTimeInterval(1),
            relativePath: "Inbox/Bookmarks/Github.Com.webloc"
        )

        #expect(
            CiderCLI.shouldReturnNativeBookmarkCapture(
                bookmark: metadataOnly,
                state: &state,
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(2),
                timeout: 30
            ) == false
        )
        #expect(
            CiderCLI.shouldReturnNativeBookmarkCapture(
                bookmark: metadataOnly,
                state: &state,
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(2.5),
                timeout: 30
            ) == false
        )
    }

    @Test("capture add stores plain text as a note through the shared result shape")
    func captureAddStoresPlainTextAsNote() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )

            let result = try service.add(
                "Cider should let me throw random thoughts into one capture box.",
                title: "One capture box"
            )

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "text")
            #expect(result.source.text == "Cider should let me throw random thoughts into one capture box.")
            #expect(result.source.itemType == "note")
            #expect(result.item.type == "note")
            #expect(result.item.title == "One capture box")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Notes/") == true)
            #expect(result.enrichment.status == "not_applicable")
            #expect(result.duplicate.status == "not_checked")
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Notes")
            #expect(result.nextSafeAction == "inspect_item")
            try expectQuietCaptureSafeCommands(for: result)

            let storedNote = notes.notes.first(where: { $0.id == result.item.id })
            #expect(storedNote?.title == "One capture box")
            #expect(notes.loadContent(for: storedNote!) == "Cider should let me throw random thoughts into one capture box.")

            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.item.type == "note")
            #expect(explanation.latestDecision?.reviewState == "needs_review")
            #expect(explanation.latestDecision?.target.relativePath == "Inbox/Notes")
        }
    }

    @Test("note capture immediately indexes content chunks")
    func noteCaptureImmediatelyIndexesContentChunks() throws {
        try withIsolatedVault { db, _, notes, _, _ in
            let service = CiderCaptureService(notesStorage: notes, database: db)
            let result = try service.addNoteCapture(
                title: "Indexed capture note",
                content: "instant-capture-index-token",
                folderID: nil
            )

            let matches = try SecondBrainStore(database: db).searchChunks(
                query: "instant-capture-index-token",
                limit: 5
            )
            #expect(matches.first?.owner == SecondBrainOwnerRef(ownerType: "note", ownerID: result.item.id.uuidString))
        }
    }

    @Test("captured note is findable through UI search and item search")
    func capturedNoteIsFindableThroughUISearchAndItemSearch() async throws {
        try await withIsolatedVault { db, bookmarks, notes, _, _ in
            let service = CiderCaptureService(notesStorage: notes, database: db)
            let result = try service.addNoteCapture(
                title: "Projection parity note",
                content: "Search projection parity token prism-lantern",
                folderID: nil
            )

            let uiResults = await SearchService.search(
                query: "prism-lantern",
                bookmarks: bookmarks.bookmarks,
                notes: notes.notes
            )
            let itemResults = try CiderItemContextService(database: db).search("prism-lantern", limit: 5)

            #expect(uiResults.contains { $0.id == result.item.id && $0.type == .note })
            #expect(itemResults.contains {
                $0.owner == SecondBrainOwnerRef(ownerType: "note", ownerID: result.item.id.uuidString)
            })
        }
    }

    @Test("capture result reports canonical side effect statuses on success")
    func captureResultReportsCanonicalSideEffectStatusesOnSuccess() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )

            let result = try service.addNoteCapture(
                title: "Status contract",
                content: "capture-status-contract-token",
                folderID: nil
            )
            let dict = result.toDictionary()
            let provenance = try #require(dict["provenance"] as? [String: Any])
            let routingDict = try #require(dict["routing"] as? [String: Any])
            let indexing = try #require(dict["indexing"] as? [String: Any])
            let safeNextCommands = try #require(dict["safeNextCommands"] as? [String])

            #expect(provenance["status"] as? String == "recorded")
            #expect(provenance["captureEventID"] as? String == result.captureEventID?.uuidString)
            #expect(routingDict["status"] as? String == "recorded")
            #expect(routingDict["decisionID"] as? String == result.routing.decisionID?.uuidString)
            #expect(indexing["status"] as? String == "indexed")
            #expect(indexing["ownerType"] as? String == "note")
            #expect(indexing["ownerID"] as? String == result.item.id.uuidString)
            #expect(indexing["captureEventID"] as? String == result.captureEventID?.uuidString)
            let chunks = try #require(indexing["chunks"] as? [[String: Any]])
            #expect(chunks.count == 1)
            #expect(chunks.first?["ownerType"] as? String == "note")
            #expect(chunks.first?["ownerID"] as? String == result.item.id.uuidString)
            #expect(chunks.first?["source"] as? String == "item_index.note")
            #expect(chunks.first?["chunkIndex"] as? Int == 0)
            #expect((chunks.first?["id"] as? String)?.isEmpty == false)
            #expect((chunks.first?["title"] as? String)?.isEmpty == false)
            #expect(dict["partialSuccess"] == nil)
            #expect(result.nextSafeAction == "inspect_item")
            #expect(safeNextCommands.first == "cider-cli item get note \(result.item.id.uuidString) --json")
            #expect(!safeNextCommands.contains("cider-cli routing explain \(result.item.id.uuidString) --json"))
            #expect(!safeNextCommands.contains("cider-cli review list --item-type note --state needs_review --limit 10 --json"))
            #expect(!safeNextCommands.contains("cider-cli item get \(result.item.id.uuidString) --json"))
        }
    }

    @Test("bookmark capture safe next commands include item type")
    func bookmarkCaptureSafeNextCommandsIncludeItemType() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )

            let result = try service.addBookmarkCapture(
                urlString: "https://example.com/typed-safe-next-command",
                title: "Typed Safe Next Command",
                folderID: nil
            )
            let dict = result.toDictionary()
            let safeNextCommands = try #require(dict["safeNextCommands"] as? [String])

            #expect(safeNextCommands.first == "cider-cli item get bookmark \(result.item.id.uuidString) --json")
            #expect(!safeNextCommands.contains("cider-cli item get \(result.item.id.uuidString) --json"))
        }
    }

    @Test("capture result reports unavailable provenance routing and indexing")
    func captureResultReportsUnavailableCanonicalSideEffects() throws {
        try withIsolatedVault { _, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: nil,
                routingDecisionService: nil
            )

            let result = try service.addNoteCapture(
                title: "Status unavailable",
                content: "This capture is stored but canonical side effects cannot run.",
                folderID: nil
            )
            let dict = result.toDictionary()
            let provenance = try #require(dict["provenance"] as? [String: Any])
            let routingDict = try #require(dict["routing"] as? [String: Any])
            let indexing = try #require(dict["indexing"] as? [String: Any])
            let partialSuccess = try #require(dict["partialSuccess"] as? [String: Any])
            let safeNextCommands = try #require(dict["safeNextCommands"] as? [String])

            #expect(result.captureEventID == nil)
            #expect(provenance["status"] as? String == "unavailable")
            #expect((provenance["reason"] as? String)?.contains("database") == true)
            #expect(routingDict["status"] as? String == "unavailable")
            #expect((routingDict["statusReason"] as? String)?.contains("routing decision service") == true)
            #expect(indexing["status"] as? String == "unavailable")
            #expect((indexing["reason"] as? String)?.contains("database") == true)
            #expect(partialSuccess["status"] as? String == "canonical_side_effects_incomplete")
            #expect((partialSuccess["reason"] as? String)?.contains("provenance") == true)
            #expect(safeNextCommands.contains("cider-cli storage audit --json"))
        }
    }

    @Test("blank note quick capture still returns the shared result shape")
    func blankNoteQuickCaptureReturnsSharedResultShape() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )

            let result = try service.addNoteCapture(title: "", content: "", folderID: nil)

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "text")
            #expect(result.source.itemType == "note")
            #expect(result.item.type == "note")
            #expect(result.item.title == "Untitled")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Notes/") == true)
            #expect(result.enrichment.status == "not_applicable")
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.decisionID != nil)
            #expect(result.nextSafeAction == "inspect_item")

            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.latestDecision?.id == result.routing.decisionID)
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("note capture reports partial success when folder assignment fails")
    func noteCaptureReportsPartialSuccessWhenFolderAssignmentFails() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let requestedFolderID = UUID()
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                noteAssignmentHandler: { _, _ in false }
            )

            let result = try service.addNoteCapture(
                title: "Loose note",
                content: "This should be saved even if assignment fails.",
                folderID: requestedFolderID
            )
            let dict = result.toDictionary()
            let partialSuccess = try #require(dict["partialSuccess"] as? [String: Any])

            #expect(result.item.folderID == nil)
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.reviewState == "needs_review")
            #expect(result.nextSafeAction == "review_route")
            #expect(partialSuccess["status"] as? String == "assignment_failed")
            #expect(partialSuccess["requestedFolderID"] as? String == requestedFolderID.uuidString)
            #expect(partialSuccess["actualFolderID"] == nil)
            #expect((partialSuccess["reason"] as? String)?.contains("note folder assignment failed") == true)
        }
    }

    @Test("screen capture note capture preserves attachment markdown and returns shared result shape")
    func screenCaptureNoteCaptureReturnsSharedResultShape() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.lockFocus()
            NSColor.red.setFill()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
            image.unlockFocus()

            let result = try service.addScreenCaptureNoteCapture(
                title: "Receipt OCR",
                ocrText: "Total $42.00",
                screenshot: image,
                sourceURL: nil,
                folderID: nil
            )

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "screen_capture")
            #expect(result.source.itemType == "note")
            #expect(result.item.type == "note")
            #expect(result.item.title == "Receipt OCR")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Notes/") == true)
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Notes")
            #expect(result.nextSafeAction == "inspect_item")

            let stored = try #require(notes.notes.first(where: { $0.id == result.item.id }))
            let content = notes.loadContent(for: stored)
            #expect(content.contains("<img src=\".attachments/"))
            #expect(content.contains("Total $42.00"))
            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("note and screen capture stage Space and project intent without folder routing")
    func noteAndScreenCaptureStageSpaceAndProjectIntentWithoutFolderRouting() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )

            let gameNote = try service.addNoteCapture(
                title: "Paralives backlog",
                content: "Steam reference for Paralives and game backlog notes.",
                folderID: nil
            ).toDictionary()
            let gameIntent = try #require(gameNote["spaceIntent"] as? [String: Any])
            #expect(gameIntent["spaceName"] as? String == "Media")
            #expect(gameIntent["area"] as? String == "Games")
            #expect(gameIntent["storageDestination"] as? String == "Inbox/Notes")

            let providerURLNote = try service.addNoteCapture(
                title: "Watch later",
                content: "Save https://www.rottentomatoes.com/tv/the_vampire_lestat/s01 for TV night.",
                folderID: nil
            ).toDictionary()
            let providerIntent = try #require(providerURLNote["spaceIntent"] as? [String: Any])
            #expect(providerIntent["spaceName"] as? String == "Media")
            #expect(providerIntent["area"] as? String == "Shows")

            let projectNote = try service.addNoteCapture(
                title: "Cider iOS capture loop",
                content: "Codex iOS and Cider iOS implementation notes.",
                folderID: nil
            ).toDictionary()
            let projectIntent = try #require(projectNote["projectIntent"] as? [String: Any])
            #expect(projectIntent["projectName"] as? String == "Cider iOS")
            #expect(projectNote["recommendedNextAction"] as? String == "review_intent")

            let screen = try service.addScreenCaptureNoteCapture(
                title: "Screen grab",
                ocrText: "IMDb trailer page for Lucky and media backlog",
                screenshot: nil,
                sourceURL: "https://www.imdb.com/video/vi3463695129/",
                folderID: nil
            ).toDictionary()
            let screenIntent = try #require(screen["spaceIntent"] as? [String: Any])
            #expect(screenIntent["spaceName"] as? String == "Media")
            #expect(screenIntent["area"] as? String == "Trailers")
            let routing = try #require(screen["routing"] as? [String: Any])
            let target = try #require(routing["candidateTarget"] as? [String: Any])
            #expect(target["relativePath"] as? String == "Inbox/Notes")
        }
    }

    @Test("screen capture note capture works when OCR and screenshot are unavailable")
    func screenCaptureNoteCaptureWorksWithoutOCRAndScreenshot() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db
            )

            let result = try service.addScreenCaptureNoteCapture(
                title: "",
                ocrText: "",
                screenshot: nil,
                sourceURL: nil,
                folderID: nil
            )

            #expect(result.source.kind == "screen_capture")
            #expect(result.item.title == "Screen Capture")
            #expect(result.routing.reviewNeeded == true)
            let stored = try #require(notes.notes.first(where: { $0.id == result.item.id }))
            #expect(notes.loadContent(for: stored).isEmpty)
        }
    }

    @Test("screen capture note capture reports partial success when folder assignment fails")
    func screenCaptureNoteCaptureReportsPartialSuccessWhenFolderAssignmentFails() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let requestedFolderID = UUID()
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                noteAssignmentHandler: { _, _ in false }
            )

            let result = try service.addScreenCaptureNoteCapture(
                title: "Captured thing",
                ocrText: "body",
                screenshot: nil,
                sourceURL: nil,
                folderID: requestedFolderID
            )
            let partialSuccess = try #require(result.toDictionary()["partialSuccess"] as? [String: Any])

            #expect(result.item.folderID == nil)
            #expect(result.routing.reviewNeeded == true)
            #expect(partialSuccess["status"] as? String == "assignment_failed")
            #expect(partialSuccess["requestedFolderID"] as? String == requestedFolderID.uuidString)
        }
    }

    @Test("image bookmark capture assigns thumbnail and returns shared result shape")
    func imageBookmarkCaptureReturnsSharedResultShape() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.lockFocus()
            NSColor.green.setFill()
            NSRect(x: 0, y: 0, width: 4, height: 4).fill()
            image.unlockFocus()
            let data = try #require(image.tiffRepresentation)

            let result = try service.addImageBookmarkCapture(
                title: "Paralives on Steam screenshot",
                imageData: data,
                preferredFileExtension: "png",
                sourceFile: nil
            )

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "image")
            #expect(result.source.itemType == "bookmark")
            #expect(result.item.type == "bookmark")
            #expect(result.item.title == "Paralives on Steam screenshot")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Bookmarks/") == true)
            #expect(result.enrichment.status == "not_applicable")
            #expect(result.duplicate.status == "not_checked")
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Bookmarks")
            #expect(result.nextSafeAction == "inspect_item")
            #expect(result.partialSuccess == nil)
            let dict = result.toDictionary()
            let spaceIntent = try #require(dict["spaceIntent"] as? [String: Any])
            #expect(spaceIntent["spaceName"] as? String == "Media")
            #expect(spaceIntent["area"] as? String == "Games")
            #expect(spaceIntent["storageDestination"] as? String == "Inbox/Bookmarks")
            #expect((dict["routing"] as? [String: Any]).flatMap { $0["candidateTarget"] as? [String: Any] }?["relativePath"] as? String == "Inbox/Bookmarks")

            let stored = try #require(bookmarks.bookmarks.first(where: { $0.id == result.item.id }))
            #expect(stored.thumbnailRelativePath != nil)
            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("image bookmark capture records provenance relation and indexing trace")
    func imageBookmarkCaptureRecordsProvenanceRelationAndIndexingTrace() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db),
                thumbnailAssignmentHandler: { _, _, _ in true }
            )
            let sourcePath = "/tmp/cider-copied-image.png"
            let result = try service.addImageBookmarkCapture(
                title: "Clipboard provenance image",
                imageData: Data([0x89, 0x50, 0x4E, 0x47]),
                preferredFileExtension: "png",
                sourceFile: sourcePath,
                sourceContext: CaptureSourceContext(
                    surface: "clipboard_viewer",
                    channel: "pasteboard",
                    attachments: [
                        CaptureSourceContext.Attachment(
                            filename: "cider-copied-image.png",
                            mimeType: "image/png",
                            localPath: sourcePath
                        )
                    ]
                )
            )

            let eventID = try #require(result.captureEventID)
            let dict = result.toDictionary()
            let indexing = try #require(dict["indexing"] as? [String: Any])
            #expect(indexing["status"] as? String == "indexed")
            #expect(indexing["ownerType"] as? String == "bookmark")
            #expect(indexing["ownerID"] as? String == result.item.id.uuidString)
            #expect(indexing["captureEventID"] as? String == eventID.uuidString)

            let event = try db.prepare("""
                SELECT source_kind, surface, channel, source_file, attachment_count
                FROM capture_events
                WHERE id = ?;
                """)
            event.bind(eventID.uuidString, at: 1)
            #expect(try event.step())
            #expect(event.string(at: 0) == "image")
            #expect(event.string(at: 1) == "clipboard_viewer")
            #expect(event.string(at: 2) == "pasteboard")
            #expect(event.string(at: 3) == sourcePath)
            #expect(event.int(at: 4) == 1)

            let relations = try SecondBrainStore(database: db).outgoingRelations(
                for: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
            )
            #expect(relations.contains { relation in
                relation.relationType == "produced_item" &&
                    relation.targetOwner == SecondBrainOwnerRef(ownerType: "bookmark", ownerID: result.item.id.uuidString)
            })
            #expect(relations.contains { $0.relationType == "had_attachment" })

            let matches = try SecondBrainStore(database: db).searchChunks(
                query: "Clipboard provenance image",
                limit: 5
            )
            #expect(matches.first?.owner == SecondBrainOwnerRef(ownerType: "bookmark", ownerID: result.item.id.uuidString))
        }
    }

    @Test("image bookmark capture reports partial success when thumbnail assignment fails")
    func imageBookmarkCaptureReportsPartialSuccessWhenThumbnailAssignmentFails() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                thumbnailAssignmentHandler: { _, _, _ in false }
            )

            let result = try service.addImageBookmarkCapture(
                title: "Dropped Image",
                imageData: Data("not image data".utf8),
                preferredFileExtension: "png",
                sourceFile: "/tmp/Dropped.png"
            )
            let partialSuccess = try #require(result.toDictionary()["partialSuccess"] as? [String: Any])

            #expect(result.source.kind == "image")
            #expect(result.source.file == "/tmp/Dropped.png")
            #expect(result.item.title == "Dropped Image")
            #expect(partialSuccess["status"] as? String == "thumbnail_assignment_failed")
            #expect((partialSuccess["reason"] as? String)?.contains("thumbnail") == true)
        }
    }

    @Test("capture add stores task-like text as a todo through the shared result shape")
    func captureAddStoresTaskTextAsTodo() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )

            let result = try service.add("todo: Call the dentist next week")

            #expect(result.source.kind == "text")
            #expect(result.source.itemType == "todo")
            #expect(result.item.type == "todo")
            #expect(result.item.title == "Call the dentist next week")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Todos/") == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Todos")
            #expect(result.nextSafeAction == "inspect_item")
            try expectQuietCaptureSafeCommands(for: result)

            let storedTodo = todos.todoCards.first(where: { $0.id == result.item.id })
            #expect(storedTodo?.title == "Call the dentist next week")
            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.item.type == "todo")
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("todo capture reports partial success when folder update fails")
    func todoCaptureReportsPartialSuccessWhenFolderUpdateFails() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let requestedFolderID = UUID()
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                todoUpdateHandler: { _ in false }
            )

            let result = try service.addTodoCapture(
                title: "Call dentist",
                sourceText: "todo: Call dentist",
                dueDate: nil,
                priority: nil,
                folderID: requestedFolderID
            )
            let dict = result.toDictionary()
            let partialSuccess = try #require(dict["partialSuccess"] as? [String: Any])

            #expect(result.item.folderID == nil)
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.reviewState == "needs_review")
            #expect(result.nextSafeAction == "review_route")
            #expect(partialSuccess["status"] as? String == "assignment_failed")
            #expect(partialSuccess["requestedFolderID"] as? String == requestedFolderID.uuidString)
            #expect(partialSuccess["actualFolderID"] == nil)
            #expect((partialSuccess["reason"] as? String)?.contains("todo folder assignment failed") == true)
        }
    }

    @Test("event quick capture returns the shared result shape")
    func eventQuickCaptureReturnsSharedResultShape() throws {
        try withIsolatedVaultDomains { db, bookmarks, notes, todos, dateCards, contacts, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                dateCardStorage: dateCards,
                contactStorage: contacts,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )
            let startAt = Date(timeIntervalSince1970: 1_779_000_000)

            let result = try service.addDateCardCapture(
                title: "Design review",
                sourceText: nil,
                startAt: startAt,
                endAt: nil,
                allDay: false,
                location: "Studio",
                folderID: nil
            )

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "text")
            #expect(result.source.itemType == "event")
            #expect(result.item.type == "event")
            #expect(result.item.title == "Design review")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Date Cards/") == true)
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Date Cards")
            #expect(result.nextSafeAction == "inspect_item")
            try expectQuietCaptureSafeCommands(for: result)

            let stored = dateCards.dateCards.first(where: { $0.id == result.item.id })
            #expect(stored?.location == "Studio")
            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.item.type == "event")
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("event capture stages Space and project intent without folder routing")
    func eventCaptureStagesSpaceAndProjectIntentWithoutFolderRouting() throws {
        try withIsolatedVaultDomains { db, bookmarks, notes, todos, dateCards, contacts, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                dateCardStorage: dateCards,
                contactStorage: contacts,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )
            let startAt = Date(timeIntervalSince1970: 1_779_000_000)

            let watchParty = try service.addDateCardCapture(
                title: "The Vampire Lestat watch party",
                sourceText: "TV premiere night and Rotten Tomatoes discussion.",
                startAt: startAt,
                endAt: nil,
                allDay: false,
                location: "Living room",
                folderID: nil
            ).toDictionary()
            let watchIntent = try #require(watchParty["spaceIntent"] as? [String: Any])
            #expect(watchIntent["spaceName"] as? String == "Media")
            #expect(watchIntent["area"] as? String == "Shows")
            #expect(watchIntent["storageDestination"] as? String == "Inbox/Date Cards")

            let projectMeeting = try service.addDateCardCapture(
                title: "Cider iOS planning meeting",
                sourceText: "Codex iOS capture loop review.",
                startAt: startAt.addingTimeInterval(3600),
                endAt: nil,
                allDay: false,
                location: nil,
                folderID: nil
            ).toDictionary()
            let projectIntent = try #require(projectMeeting["projectIntent"] as? [String: Any])
            #expect(projectIntent["projectName"] as? String == "Cider iOS")
            #expect(projectIntent["storageDestination"] as? String == "Inbox/Date Cards")
            #expect(projectMeeting["recommendedNextAction"] as? String == "review_intent")

            let appointment = try service.addDateCardCapture(
                title: "Dentist appointment",
                sourceText: "Routine cleaning.",
                startAt: startAt.addingTimeInterval(7200),
                endAt: nil,
                allDay: false,
                location: "Dental office",
                folderID: nil
            ).toDictionary()
            #expect(appointment["intentStaging"] == nil)
            #expect(appointment["spaceIntent"] == nil)
            #expect(appointment["projectIntent"] == nil)
            #expect(appointment["recommendedNextAction"] as? String == "review_route")
            let routing = try #require(appointment["routing"] as? [String: Any])
            let target = try #require(routing["candidateTarget"] as? [String: Any])
            #expect(target["relativePath"] as? String == "Inbox/Date Cards")
        }
    }

    @Test("contact quick capture returns the shared result shape")
    func contactQuickCaptureReturnsSharedResultShape() throws {
        try withIsolatedVaultDomains { db, bookmarks, notes, todos, dateCards, contacts, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                dateCardStorage: dateCards,
                contactStorage: contacts,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )

            let result = try service.addContactCapture(
                displayName: "Avery Stone",
                sourceText: nil,
                relationshipLabel: "Designer",
                email: "avery@example.com",
                phone: "555-0100",
                folderID: nil
            )

            #expect(result.command == "capture.add")
            #expect(result.source.kind == "text")
            #expect(result.source.itemType == "contact")
            #expect(result.item.type == "contact")
            #expect(result.item.title == "Avery Stone")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Contacts/") == true)
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Contacts")
            #expect(result.nextSafeAction == "inspect_item")
            try expectQuietCaptureSafeCommands(for: result)

            let stored = contacts.contacts.first(where: { $0.id == result.item.id })
            #expect(stored?.relationshipLabel == "Designer")
            #expect(stored?.email == "avery@example.com")
            #expect(stored?.phone == "555-0100")
            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.item.type == "contact")
            #expect(explanation.latestDecision?.source == "capture.add")
        }
    }

    @Test("contact capture stages project intent without over-routing people to Spaces")
    func contactCaptureStagesProjectIntentWithoutOverRoutingPeopleToSpaces() throws {
        try withIsolatedVaultDomains { db, bookmarks, notes, todos, dateCards, contacts, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                dateCardStorage: dateCards,
                contactStorage: contacts,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )

            let collaborator = try service.addContactCapture(
                displayName: "Jordan Lee",
                sourceText: "Cider iOS collaborator from the Codex iOS capture loop.",
                relationshipLabel: "Cider iOS collaborator",
                email: "jordan@example.com",
                phone: nil,
                folderID: nil
            ).toDictionary()
            let projectIntent = try #require(collaborator["projectIntent"] as? [String: Any])
            #expect(projectIntent["projectName"] as? String == "Cider iOS")
            #expect(projectIntent["storageDestination"] as? String == "Inbox/Contacts")
            #expect(collaborator["spaceIntent"] == nil)
            #expect(collaborator["recommendedNextAction"] as? String == "review_intent")

            let generic = try service.addContactCapture(
                displayName: "Avery Stone",
                sourceText: "Met at the neighborhood coffee meetup.",
                relationshipLabel: "Friend",
                email: "avery@example.com",
                phone: "555-0100",
                folderID: nil
            ).toDictionary()
            #expect(generic["intentStaging"] == nil)
            #expect(generic["spaceIntent"] == nil)
            #expect(generic["projectIntent"] == nil)
            #expect(generic["recommendedNextAction"] as? String == "review_route")

            let hobby = try service.addContactCapture(
                displayName: "Sam Patel",
                sourceText: "Likes Steam games and Paralives.",
                relationshipLabel: "Friend",
                email: "sam@example.com",
                phone: nil,
                folderID: nil
            ).toDictionary()
            #expect(hobby["intentStaging"] == nil)
            #expect(hobby["spaceIntent"] == nil)
            #expect(hobby["projectIntent"] == nil)
            let routing = try #require(hobby["routing"] as? [String: Any])
            let target = try #require(routing["candidateTarget"] as? [String: Any])
            #expect(target["relativePath"] as? String == "Inbox/Contacts")
        }
    }

    @Test("event capture reports partial success when folder update fails")
    func eventCaptureReportsPartialSuccessWhenFolderUpdateFails() throws {
        try withIsolatedVaultDomains { db, bookmarks, notes, todos, dateCards, contacts, files in
            let requestedFolderID = UUID()
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                dateCardStorage: dateCards,
                contactStorage: contacts,
                vaultFileStorage: files,
                database: db,
                dateCardUpdateHandler: { _ in false }
            )

            let result = try service.addDateCardCapture(
                title: "Calendar thing",
                sourceText: nil,
                startAt: Date(timeIntervalSince1970: 1_779_100_000),
                endAt: nil,
                allDay: true,
                location: nil,
                folderID: requestedFolderID
            )
            let partialSuccess = try #require(result.toDictionary()["partialSuccess"] as? [String: Any])

            #expect(result.item.folderID == nil)
            #expect(result.routing.reviewNeeded == true)
            #expect(partialSuccess["status"] as? String == "assignment_failed")
            #expect(partialSuccess["requestedFolderID"] as? String == requestedFolderID.uuidString)
            #expect((partialSuccess["reason"] as? String)?.contains("event folder assignment failed") == true)
        }
    }

    @Test("contact capture reports partial success when folder update fails")
    func contactCaptureReportsPartialSuccessWhenFolderUpdateFails() throws {
        try withIsolatedVaultDomains { db, bookmarks, notes, todos, dateCards, contacts, files in
            let requestedFolderID = UUID()
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                dateCardStorage: dateCards,
                contactStorage: contacts,
                vaultFileStorage: files,
                database: db,
                contactUpdateHandler: { _ in false }
            )

            let result = try service.addContactCapture(
                displayName: "Morgan",
                sourceText: nil,
                relationshipLabel: nil,
                email: nil,
                phone: nil,
                folderID: requestedFolderID
            )
            let partialSuccess = try #require(result.toDictionary()["partialSuccess"] as? [String: Any])

            #expect(result.item.folderID == nil)
            #expect(result.routing.reviewNeeded == true)
            #expect(partialSuccess["status"] as? String == "assignment_failed")
            #expect(partialSuccess["requestedFolderID"] as? String == requestedFolderID.uuidString)
            #expect((partialSuccess["reason"] as? String)?.contains("contact folder assignment failed") == true)
        }
    }

    @Test("capture add imports an existing file into Inbox files through the shared result shape")
    func captureAddImportsExistingFile() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-capture-source-\(UUID().uuidString).png")
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sourceURL)
            defer { try? FileManager.default.removeItem(at: sourceURL) }

            let result = try service.add(sourceURL.path, title: "Receipt photo")

            #expect(result.source.kind == "file")
            #expect(result.source.file == sourceURL.path)
            #expect(result.source.itemType == "vaultFile")
            #expect(result.item.type == "vaultFile")
            #expect(result.item.title == "Receipt photo")
            #expect(result.item.relativePath?.hasPrefix("Inbox/Images/") == true)
            #expect(result.routing.candidateTarget?.relativePath == "Inbox/Images")
            #expect(result.nextSafeAction == "inspect_item")
            try expectQuietCaptureSafeCommands(for: result)

            let copiedPath = try #require(result.item.relativePath)
            let copiedURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(copiedPath)
            #expect(FileManager.default.fileExists(atPath: copiedURL.path))

            let itemStatement = try db.prepare("SELECT type, title, relative_path FROM items WHERE id = ?;")
            itemStatement.bind(result.item.id.uuidString, at: 1)
            #expect(try itemStatement.step())
            #expect(itemStatement.string(at: 0) == "vaultFile")
            #expect(itemStatement.string(at: 1) == "Receipt photo")
            #expect(itemStatement.string(at: 2).hasPrefix("Inbox/Images/"))
        }
    }

    @Test("file capture records vault file create audit entry")
    func fileCaptureRecordsVaultFileCreateAuditEntry() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let routing = CiderRoutingDecisionService(database: db)
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: routing
            )
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-capture-audit-\(UUID().uuidString).pdf")
            try Data([0x25, 0x50, 0x44, 0x46]).write(to: sourceURL)
            defer { try? FileManager.default.removeItem(at: sourceURL) }

            let result = try service.addFileCapture(
                sourcePath: sourceURL.path,
                title: "Audited receipt",
                folderID: nil
            )

            let entries = MutationAuditService(database: db).loadEntries()
            let audit = entries.first { $0.itemID == result.item.id && $0.action == "create" }

            #expect(result.item.type == "vaultFile")
            #expect(result.routing.decisionID != nil)
            #expect(audit?.itemType == "vaultFile")
            #expect(audit?.afterState["title"] == "Audited receipt")
            #expect(audit?.afterState["relativePath"] == result.item.relativePath)
            #expect(audit?.metadata["source"] == "capture.add")
        }
    }

    @Test("file capture stages Space and project intent without folder routing")
    func fileCaptureStagesSpaceAndProjectIntentWithoutFolderRouting() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )

            let projectSource = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-ios-codex-loop-\(UUID().uuidString).txt")
            try Data("Notes for the Cider iOS Codex loop and review backlog.".utf8).write(to: projectSource)
            defer { try? FileManager.default.removeItem(at: projectSource) }

            let projectResult = try service.addFileCapture(
                sourcePath: projectSource.path,
                title: "Cider iOS Codex loop notes",
                folderID: nil
            ).toDictionary()
            let projectIntent = try #require(projectResult["projectIntent"] as? [String: Any])
            #expect(projectIntent["projectName"] as? String == "Cider iOS")
            #expect(projectIntent["storageDestination"] as? String == "Inbox/Files")
            #expect(projectResult["recommendedNextAction"] as? String == "review_intent")

            let gameSource = FileManager.default.temporaryDirectory
                .appendingPathComponent("paralives-steam-reference-\(UUID().uuidString).txt")
            try Data("Steam page notes for Paralives and the game backlog.".utf8).write(to: gameSource)
            defer { try? FileManager.default.removeItem(at: gameSource) }

            let gameResult = try service.addFileCapture(
                sourcePath: gameSource.path,
                title: nil,
                folderID: nil
            ).toDictionary()
            let gameIntent = try #require(gameResult["spaceIntent"] as? [String: Any])
            #expect(gameIntent["spaceName"] as? String == "Media")
            #expect(gameIntent["area"] as? String == "Games")
            #expect(gameIntent["storageDestination"] as? String == "Inbox/Files")

            let recipeSource = FileManager.default.temporaryDirectory
                .appendingPathComponent("lasagna-recipe-\(UUID().uuidString).md")
            try Data("Ingredients: pasta, tomato, cheese. Recipe steps go here.".utf8).write(to: recipeSource)
            defer { try? FileManager.default.removeItem(at: recipeSource) }

            let recipeResult = try service.addFileCapture(
                sourcePath: recipeSource.path,
                title: "Lasagna recipe draft",
                folderID: nil
            ).toDictionary()
            let recipeIntent = try #require(recipeResult["spaceIntent"] as? [String: Any])
            #expect(recipeIntent["spaceName"] as? String == "Recipes")
            #expect(recipeIntent["storageDestination"] as? String == "Inbox/Files")

            let routing = try #require(gameResult["routing"] as? [String: Any])
            let target = try #require(routing["candidateTarget"] as? [String: Any])
            #expect(target["relativePath"] as? String == "Inbox/Files")
            let commands = try #require(gameResult["safeNextCommands"] as? [String])
            #expect(commands.allSatisfy { !$0.contains(" item move ") && !$0.contains("--folder") })
        }
    }

    @Test("file capture records canonical provenance relation and indexing trace")
    func fileCaptureRecordsCanonicalProvenanceRelationAndIndexingTrace() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-contract-\(UUID().uuidString).pdf")
            try Data([0x25, 0x50, 0x44, 0x46]).write(to: sourceURL)
            defer { try? FileManager.default.removeItem(at: sourceURL) }

            let result = try service.addFileCapture(
                sourcePath: sourceURL.path,
                title: "Canonical provenance PDF",
                folderID: nil,
                sourceContext: CaptureSourceContext(
                    surface: "drop_zone",
                    attachments: [
                        CaptureSourceContext.Attachment(
                            filename: sourceURL.lastPathComponent,
                            mimeType: "application/pdf",
                            localPath: sourceURL.path
                        )
                    ]
                )
            )

            let eventID = try #require(result.captureEventID)
            let dict = result.toDictionary()
            let indexing = try #require(dict["indexing"] as? [String: Any])
            #expect(result.item.type == "vaultFile")
            #expect(result.routing.reviewNeeded == true)
            #expect(result.routing.reviewState == "needs_review")
            #expect(indexing["status"] as? String == "indexed")
            #expect(indexing["ownerType"] as? String == "vaultFile")
            #expect(indexing["ownerID"] as? String == result.item.id.uuidString)
            #expect(indexing["captureEventID"] as? String == eventID.uuidString)

            let itemStatement = try db.prepare("""
                SELECT i.type, i.title, i.relative_path, vf.filename, vf.file_type
                FROM items i JOIN vault_files vf ON vf.item_id = i.id
                WHERE i.id = ?;
                """)
            itemStatement.bind(result.item.id.uuidString, at: 1)
            #expect(try itemStatement.step())
            #expect(itemStatement.string(at: 0) == "vaultFile")
            #expect(itemStatement.string(at: 1) == "Canonical provenance PDF")
            #expect(itemStatement.string(at: 2).hasPrefix("Inbox/Files/"))
            #expect(itemStatement.string(at: 3).hasSuffix(".pdf"))
            #expect(itemStatement.string(at: 4) == "pdf")

            let event = try db.prepare("""
                SELECT source_kind, surface, source_file, attachment_count
                FROM capture_events
                WHERE id = ?;
                """)
            event.bind(eventID.uuidString, at: 1)
            #expect(try event.step())
            #expect(event.string(at: 0) == "file")
            #expect(event.string(at: 1) == "drop_zone")
            #expect(event.string(at: 2) == sourceURL.path)
            #expect(event.int(at: 3) == 1)

            let relations = try SecondBrainStore(database: db).outgoingRelations(
                for: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString)
            )
            #expect(relations.contains { relation in
                relation.relationType == "produced_item" &&
                    relation.targetOwner == SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: result.item.id.uuidString)
            })
            #expect(relations.contains { $0.relationType == "had_attachment" })

            let matches = try SecondBrainStore(database: db).searchChunks(
                query: "Canonical provenance PDF",
                limit: 5
            )
            #expect(matches.first?.owner == SecondBrainOwnerRef(ownerType: "vaultFile", ownerID: result.item.id.uuidString))
        }
    }

    @Test("DOCX file capture reports semantic indexing gap explicitly")
    func docxFileCaptureReportsSemanticIndexingGapExplicitly() throws {
        try withIsolatedVault { db, bookmarks, notes, todos, files in
            let service = CiderCaptureService(
                bookmarkService: bookmarks,
                notesStorage: notes,
                todoStorage: todos,
                vaultFileStorage: files,
                database: db,
                routingDecisionService: CiderRoutingDecisionService(database: db)
            )
            let sourceURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-ai-strategy-\(UUID().uuidString).docx")
            try Data([0x50, 0x4B, 0x03, 0x04]).write(to: sourceURL)
            defer { try? FileManager.default.removeItem(at: sourceURL) }

            let result = try service.addFileCapture(
                sourcePath: sourceURL.path,
                title: "Cider AI Strategy",
                folderID: nil
            )
            let dict = result.toDictionary()

            let item = try #require(dict["item"] as? [String: Any])
            #expect(item["title"] as? String == "Cider AI Strategy")

            let duplicate = try #require(dict["duplicate"] as? [String: Any])
            #expect(duplicate["status"] as? String == "unsupported")
            #expect(duplicate["reason"] as? String == "duplicate_check_not_implemented_for_file_capture")

            let quality = try #require(dict["captureQuality"] as? [String: Any])
            #expect(quality["semanticStatus"] as? String == "degraded")
            #expect(quality["bodyExtractionStatus"] as? String == "unsupported")
            #expect(quality["bodyIndexed"] as? Bool == false)
            #expect(quality["indexedTextStatus"] as? String == "metadata_only")
            #expect(quality["safeNextAction"] as? String == "report_file_indexing_gap")
            #expect(quality["duplicateStatus"] as? String == "unsupported")
            let degradedReasons = try #require(quality["degradedReasons"] as? [String])
            #expect(degradedReasons.contains("file_body_not_extracted"))
            #expect(degradedReasons.contains("file_body_not_indexed"))

            #expect(dict["saved"] as? Bool == true)
            #expect(dict["useful"] as? Bool == false)
            #expect(dict["needsEnrichment"] as? Bool == true)
            #expect(dict["recommendedNextAction"] as? String == "report_file_indexing_gap")
            let blockingIssues = try #require(dict["blockingIssues"] as? [String])
            #expect(blockingIssues.contains("file_body_not_extracted"))
            #expect(blockingIssues.contains("file_body_not_indexed"))

            let commands = try #require(dict["safeNextCommands"] as? [String])
            #expect(commands == ["cider-cli item get vaultFile \(result.item.id.uuidString) --json"])
        }
    }
}
