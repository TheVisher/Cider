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
            #expect(result.nextSafeAction == "review_route")

            let storedNote = notes.notes.first(where: { $0.id == result.item.id })
            #expect(storedNote?.title == "One capture box")
            #expect(notes.loadContent(for: storedNote!) == "Cider should let me throw random thoughts into one capture box.")

            let explanation = try routing.explain(itemID: result.item.id)
            #expect(explanation.item.type == "note")
            #expect(explanation.latestDecision?.reviewState == "needs_review")
            #expect(explanation.latestDecision?.target.relativePath == "Inbox/Notes")
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
            #expect(result.nextSafeAction == "review_route")

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
            #expect(result.nextSafeAction == "review_route")

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
            #expect(result.nextSafeAction == "review_route")

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
}
