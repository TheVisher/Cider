import Foundation
import Testing
@testable import Cider

@Suite("Cider Canonical Query Adapter Tests")
@MainActor
struct CiderCanonicalQueryAdapterTests {
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-canonical-query-\(UUID().uuidString).db")
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
    }

    private func insertItem(
        id: UUID,
        type: String,
        title: String,
        folderID: UUID? = nil,
        relativePath: String? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        into db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(updatedAt), at: 4)
            .bind(DatabaseHelpers.encode(updatedAt), at: 5)
            .bind(folderID.map(DatabaseHelpers.encode), at: 6)
            .bind(relativePath, at: 7)
        try stmt.step()
    }

    private func index(
        itemID: UUID,
        ownerType: String,
        title: String,
        body: String,
        store: SecondBrainStore
    ) throws {
        try store.replaceChunks(
            owner: SecondBrainOwnerRef(ownerType: ownerType, ownerID: itemID.uuidString),
            chunks: [
                SecondBrainChunkDraft(
                    sectionID: nil,
                    itemID: itemID.uuidString,
                    source: "canonical-query-test",
                    title: title,
                    body: body,
                    chunkIndex: 0
                )
            ]
        )
    }

    @Test("Search Palette and existing item search resolve the same canonical indexed body ID")
    func paletteAndItemSearchResolveSameCanonicalIndexedBodyID() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        try insertItem(
            id: noteID,
            type: "note",
            title: "Projection parity note",
            relativePath: "Inbox/Notes/Projection parity note.md",
            into: db
        )
        let store = SecondBrainStore(database: db)
        try index(
            itemID: noteID,
            ownerType: "note",
            title: "Projection parity note",
            body: "Indexed-only body token cobalt-orchid",
            store: store
        )
        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let note = Note(
            id: noteID,
            title: "Projection parity note",
            content: "The in-memory projection intentionally omits the indexed token.",
            relativePath: "Inbox/Notes/Projection parity note.md"
        )
        let snapshot = SearchService.Snapshot(
            query: "cobalt-orchid",
            bookmarks: [],
            notes: [note],
            dateCards: [],
            contacts: [],
            todos: [],
            vaultFiles: [],
            folders: [],
            labels: []
        )

        let palette = await SearchPaletteCanonicalSearchAdapter(contextService: service).search(snapshot: snapshot)
        let existingRecall = try service.search("cobalt-orchid", limit: 10)

        #expect(palette.results.map(\.id) == [noteID])
        #expect(Set(palette.results.map(\.id)) == Set(existingRecall.compactMap(\.item?.id)))
        #expect(palette.canonical?.results.first?.kind == .chunk)
        #expect(palette.canonical?.indexState.status == .current)
        #expect(palette.canonical?.fallbackState == CiderQueryFallbackState.none)
    }

    @Test("Search Palette preserves canonical historical provenance matches")
    func palettePreservesCanonicalHistoricalProvenanceMatches() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let bookmarkID = UUID()
        let currentTitle = "Current bookmark title"
        let historicalPath = "Inbox/Bookmarks/Original-Captured-Name.webloc"
        try insertItem(
            id: bookmarkID,
            type: "bookmark",
            title: currentTitle,
            relativePath: "Bookmarks/Current bookmark title.webloc",
            into: db
        )
        let store = SecondBrainStore(database: db)
        try index(
            itemID: bookmarkID,
            ownerType: "bookmark",
            title: currentTitle,
            body: "Capture source text: \(historicalPath)",
            store: store
        )
        let eventID = UUID()
        let event = try db.prepare("""
            INSERT INTO capture_events (
                id, source_kind, surface, channel, channel_id, thread_id, message_id,
                sender_id, sender_name, source_url, source_file, source_text,
                attachment_count, metadata, created_at
            ) VALUES (?, 'bookmark', 'test', 'local', NULL, NULL, NULL,
                      NULL, NULL, NULL, NULL, ?, 0, '{}', ?);
            """)
        event.bind(eventID.uuidString, at: 1)
            .bind(historicalPath, at: 2)
            .bind(DatabaseHelpers.encode(Date()), at: 3)
        try event.step()
        try store.recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "capture_event", ownerID: eventID.uuidString),
            targetOwner: SecondBrainOwnerRef(ownerType: "bookmark", ownerID: bookmarkID.uuidString),
            relationType: "produced_item",
            evidence: "Capture produced bookmark.",
            source: "test",
            actor: "test",
            confidence: 1
        ))
        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let bookmark = Bookmark(
            id: bookmarkID,
            title: currentTitle,
            urlString: "https://example.com/current"
        )
        let snapshot = SearchService.Snapshot(
            query: "Original-Captured-Name.webloc",
            bookmarks: [bookmark],
            notes: [],
            dateCards: [],
            contacts: [],
            todos: [],
            vaultFiles: [],
            folders: [],
            labels: []
        )

        let response = await SearchPaletteCanonicalSearchAdapter(contextService: service).search(snapshot: snapshot)

        #expect(response.results.map(\.id) == [bookmarkID])
        #expect(response.canonical?.results.first?.matchProvenance.isHistoricalOnly == true)
        #expect(response.canonical?.results.first?.captureProvenance.first?.eventID == eventID.uuidString)
    }

    @Test("Search Palette maps folder and tag facets explicitly")
    func paletteMapsFolderAndTagFacetsExplicitly() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folderID = UUID()
        let tagID = UUID()
        let includedID = UUID()
        let excludedID = UUID()
        let folderStmt = try db.prepare("INSERT INTO folders (id, relative_path, created_at, updated_at) VALUES (?, ?, ?, ?);")
        folderStmt.bind(folderID.uuidString, at: 1)
            .bind("Work", at: 2)
            .bind(DatabaseHelpers.encode(Date()), at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
        try folderStmt.step()
        let tagStmt = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
        tagStmt.bind(tagID.uuidString, at: 1).bind("Focus", at: 2)
        try tagStmt.step()
        try insertItem(id: includedID, type: "note", title: "Needle included", folderID: folderID, into: db)
        try insertItem(id: excludedID, type: "note", title: "Needle excluded", into: db)
        let itemTag = try db.prepare("INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?);")
        itemTag.bind(includedID.uuidString, at: 1).bind(tagID.uuidString, at: 2)
        try itemTag.step()
        let store = SecondBrainStore(database: db)
        try index(itemID: includedID, ownerType: "note", title: "Needle included", body: "needle", store: store)
        try index(itemID: excludedID, ownerType: "note", title: "Needle excluded", body: "needle", store: store)
        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let included = Note(id: includedID, title: "Needle included", content: "needle", folderID: folderID)
        let excluded = Note(id: excludedID, title: "Needle excluded", content: "needle")
        let snapshot = SearchService.Snapshot(
            query: "needle @folder:Work @tag:Focus",
            bookmarks: [],
            notes: [included, excluded],
            dateCards: [],
            contacts: [],
            todos: [],
            vaultFiles: [],
            folders: [Folder(id: folderID, name: "Work")],
            labels: [CardLabel(id: tagID, name: "Focus")]
        )

        let response = await SearchPaletteCanonicalSearchAdapter(contextService: service).search(snapshot: snapshot)

        #expect(response.results.map(\.id) == [includedID])
        #expect(response.canonical?.query.facets.folder == .folderIDs([folderID]))
        #expect(response.canonical?.query.facets.tagIDs == [tagID])
    }

    @Test("Search Palette reports unresolved scope and does not broaden")
    func paletteReportsUnresolvedScopeAndDoesNotBroaden() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let bookmark = Bookmark(title: "Needle", urlString: "https://example.com/needle")
        let response = await SearchPaletteCanonicalSearchAdapter(
            contextService: CiderItemContextService(database: db)
        ).search(snapshot: SearchService.Snapshot(
            query: "needle @tag:Missing",
            bookmarks: [bookmark],
            notes: [],
            dateCards: [],
            contacts: [],
            todos: [],
            vaultFiles: [],
            folders: [],
            labels: []
        ))

        #expect(response.results.isEmpty)
        #expect(response.canonical == nil)
        #expect(response.status == .failedClosed(["Tag 'Missing' was not found."]))
        #expect(response.emptyStateMessage?.contains("Search was not broadened") == true)
    }

    @Test("incomplete canonical index does not claim a complete no match")
    func incompleteIndexDoesNotClaimCompleteNoMatch() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        try insertItem(id: UUID(), type: "note", title: "Unindexed note", into: db)
        let response = try CiderItemContextService(database: db).query(CiderQuery(
            text: "definitely-absent",
            facets: CiderQueryFacets(entityTypes: [.note]),
            limit: 10
        ))

        #expect(response.results.isEmpty)
        #expect(response.indexState.status == .incomplete)
        #expect(response.indexState.missingItemCount == 1)
        #expect(response.classification == .indeterminate)
    }

    @Test("stale canonical index reports lag without claiming a complete no match")
    func staleIndexReportsLagWithoutClaimingCompleteNoMatch() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        try insertItem(
            id: noteID,
            type: "note",
            title: "Future-updated note",
            updatedAt: Date().addingTimeInterval(3_600),
            into: db
        )
        let store = SecondBrainStore(database: db)
        try index(itemID: noteID, ownerType: "note", title: "Future-updated note", body: "older indexed body", store: store)
        let response = try CiderItemContextService(database: db, secondBrainStore: store).query(CiderQuery(
            text: "definitely-absent",
            facets: CiderQueryFacets(entityTypes: [.note]),
            limit: 10
        ))

        #expect(response.results.isEmpty)
        #expect(response.indexState.status == .lagging)
        #expect(response.indexState.staleItemCount == 1)
        #expect(response.classification == .indeterminate)
    }

    @Test("canonical field fallback is explicit when FTS is unavailable")
    func canonicalFieldFallbackIsExplicitWhenFTSIsUnavailable() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        try insertItem(id: noteID, type: "note", title: "Fallback Needle", into: db)
        let drop = try db.prepare("DROP TABLE content_chunks_fts;")
        try drop.step()

        let response = try CiderItemContextService(database: db).query(CiderQuery(
            text: "Fallback Needle",
            facets: CiderQueryFacets(entityTypes: [.note]),
            limit: 10
        ))

        #expect(response.results.first?.item?.id == noteID)
        #expect(response.fallbackState == .canonicalFieldsOnly)
        #expect(response.classification == .matches)
        #expect(response.warnings.contains { $0.contains("canonical title and path") })
    }

    @Test("cancelled Search Palette adapter work publishes no results")
    func cancelledPaletteAdapterWorkPublishesNoResults() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let adapter = SearchPaletteCanonicalSearchAdapter(
            contextService: CiderItemContextService(database: db)
        )
        let task = Task { @MainActor in
            await adapter.search(snapshot: SearchService.Snapshot(
                query: "needle",
                bookmarks: [],
                notes: [],
                dateCards: [],
                contacts: [],
                todos: [],
                vaultFiles: [],
                folders: [],
                labels: []
            ))
        }
        task.cancel()
        let response = await task.value

        #expect(response.status == .cancelled)
        #expect(response.results.isEmpty)
    }
}
