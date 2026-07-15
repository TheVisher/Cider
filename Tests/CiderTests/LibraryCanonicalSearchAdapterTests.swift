import Foundation
import Testing
@testable import Cider

@Suite("Library Canonical Search Adapter Tests")
@MainActor
struct LibraryCanonicalSearchAdapterTests {
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-library-query-\(UUID().uuidString).db")
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
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        into db: CiderDatabase
    ) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, ?, NULL);
            """)
        stmt.bind(id.uuidString, at: 1)
            .bind(type, at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(updatedAt), at: 4)
            .bind(DatabaseHelpers.encode(updatedAt), at: 5)
            .bind(folderID?.uuidString, at: 6)
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
                    source: "library-canonical-query-test",
                    title: title,
                    body: body,
                    chunkIndex: 0
                )
            ]
        )
    }

    @Test("Library, Search Palette, and item search resolve the same canonical indexed body ID")
    func crossSurfaceCanonicalIDParity() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        try insertItem(id: noteID, type: "note", title: "Library parity note", into: db)
        let store = SecondBrainStore(database: db)
        try index(
            itemID: noteID,
            ownerType: "note",
            title: "Library parity note",
            body: "Indexed-only library token amber-cascade",
            store: store
        )
        let service = CiderItemContextService(database: db, secondBrainStore: store)
        let note = Note(
            id: noteID,
            title: "Library parity note",
            content: "The visible projection intentionally omits the indexed token."
        )

        let library = await LibraryCanonicalSearchAdapter(contextService: service).search(
            items: [.note(note)],
            filter: LibraryFilterSpec(textQuery: "amber-cascade"),
            sort: LibrarySortSpec(mode: .titleAscending),
            folders: [],
            labels: []
        )
        let palette = await SearchPaletteCanonicalSearchAdapter(contextService: service).search(
            snapshot: SearchService.Snapshot(
                query: "amber-cascade",
                bookmarks: [],
                notes: [note],
                dateCards: [],
                contacts: [],
                todos: [],
                vaultFiles: [],
                folders: [],
                labels: []
            )
        )
        let existingRecall = try service.search("amber-cascade", limit: 10)

        #expect(library.items.map(\.canonicalEntityID) == [noteID])
        #expect(library.canonicalItemIDs == [noteID])
        #expect(Set(library.canonicalItemIDs) == Set(palette.results.map(\.id)))
        #expect(Set(library.canonicalItemIDs) == Set(existingRecall.compactMap(\.item?.id)))
        #expect(library.canonical?.results.first?.kind == .chunk)
    }

    @Test("Library fails closed for unresolved and conflicting scopes")
    func unresolvedAndConflictingScopesFailClosed() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let service = CiderItemContextService(database: db)
        let bookmark = Bookmark(title: "Needle", urlString: "https://example.com/needle")
        let adapter = LibraryCanonicalSearchAdapter(contextService: service)

        let unresolved = await adapter.search(
            items: [.bookmark(bookmark)],
            filter: LibraryFilterSpec(textQuery: "needle @tag:Missing"),
            sort: LibrarySortSpec(),
            folders: [],
            labels: []
        )
        let conflicting = await adapter.search(
            items: [.bookmark(bookmark)],
            filter: LibraryFilterSpec(entityTypes: [.bookmark], textQuery: "needle @notes"),
            sort: LibrarySortSpec(),
            folders: [],
            labels: []
        )
        let routeFolderID = UUID()
        let otherFolderID = UUID()
        let folderConflict = await adapter.search(
            items: [.bookmark(bookmark)],
            filter: LibraryFilterSpec(textQuery: "needle @folder:Other"),
            sort: LibrarySortSpec(),
            folders: [
                Folder(id: routeFolderID, name: "Route"),
                Folder(id: otherFolderID, name: "Other"),
            ],
            labels: [],
            folderScopeIDs: [routeFolderID]
        )
        let emptyEntityScope = await adapter.search(
            items: [.bookmark(bookmark)],
            filter: LibraryFilterSpec(entityTypes: [], textQuery: "needle"),
            sort: LibrarySortSpec(),
            folders: [],
            labels: []
        )
        let emptyFolderScope = await adapter.search(
            items: [.bookmark(bookmark)],
            filter: LibraryFilterSpec(textQuery: "needle"),
            sort: LibrarySortSpec(),
            folders: [],
            labels: [],
            folderScopeIDs: []
        )

        #expect(unresolved.status == .failedClosed(["Tag 'Missing' was not found."]))
        #expect(unresolved.canonical == nil)
        #expect(unresolved.emptyStateMessage?.contains("not broadened") == true)
        #expect(conflicting.status == .failedClosed(["The requested item scope does not overlap the current Library route or facet."]))
        #expect(conflicting.canonical == nil)
        #expect(folderConflict.status == .failedClosed(["The requested folder does not match the current Library route."]))
        #expect(folderConflict.canonical == nil)
        #expect(emptyEntityScope.status == .failedClosed(["The current Library route has no supported item scope."]))
        #expect(emptyEntityScope.canonical == nil)
        #expect(emptyFolderScope.status == .failedClosed(["The current Library folder scope is empty."]))
        #expect(emptyFolderScope.canonical == nil)
    }

    @Test("Library maps a single selected tag into the canonical query")
    func singleSelectedTagMapsCanonically() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let tagID = UUID()
        let includedID = UUID()
        let excludedID = UUID()
        let tag = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
        tag.bind(tagID.uuidString, at: 1).bind("Focus", at: 2)
        try tag.step()
        try insertItem(id: includedID, type: "note", title: "Included", into: db)
        try insertItem(id: excludedID, type: "note", title: "Excluded", into: db)
        let itemTag = try db.prepare("INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?);")
        itemTag.bind(includedID.uuidString, at: 1).bind(tagID.uuidString, at: 2)
        try itemTag.step()
        let store = SecondBrainStore(database: db)
        try index(itemID: includedID, ownerType: "note", title: "Included", body: "shared needle", store: store)
        try index(itemID: excludedID, ownerType: "note", title: "Excluded", body: "shared needle", store: store)

        let response = await LibraryCanonicalSearchAdapter(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        ).search(
            items: [
                .note(Note(id: includedID, title: "Included", content: "", labelIDs: [tagID])),
                .note(Note(id: excludedID, title: "Excluded", content: "")),
            ],
            filter: LibraryFilterSpec(labelIDs: [tagID], textQuery: "needle"),
            sort: LibrarySortSpec(),
            folders: [],
            labels: [CardLabel(id: tagID, name: "Focus")]
        )

        #expect(response.canonical?.query.facets.tagIDs == [tagID])
        #expect(response.canonicalItemIDs == [includedID])
        #expect(response.items.map(\.canonicalEntityID) == [includedID])
    }

    @Test("Library preserves folder, selected-tag OR, completion, and sorting policy outside canonical identity")
    func libraryLocalFacetAndSortPolicyIsPreserved() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let folderID = UUID()
        let firstTagID = UUID()
        let secondTagID = UUID()
        let firstID = UUID()
        let secondID = UUID()
        let excludedID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let folderStmt = try db.prepare("INSERT INTO folders (id, relative_path, created_at, updated_at) VALUES (?, ?, ?, ?);")
        folderStmt.bind(folderID.uuidString, at: 1)
            .bind("Work", at: 2)
            .bind(DatabaseHelpers.encode(now), at: 3)
            .bind(DatabaseHelpers.encode(now), at: 4)
        try folderStmt.step()
        for (id, name) in [(firstTagID, "First"), (secondTagID, "Second")] {
            let tag = try db.prepare("INSERT INTO tags (id, name) VALUES (?, ?);")
            tag.bind(id.uuidString, at: 1).bind(name, at: 2)
            try tag.step()
        }
        for (id, title) in [(firstID, "Zulu"), (secondID, "Alpha"), (excludedID, "Middle")] {
            try insertItem(id: id, type: "todo", title: title, folderID: folderID, into: db)
        }
        for (itemID, tagID) in [(firstID, firstTagID), (secondID, secondTagID)] {
            let itemTag = try db.prepare("INSERT INTO item_tags (item_id, tag_id) VALUES (?, ?);")
            itemTag.bind(itemID.uuidString, at: 1).bind(tagID.uuidString, at: 2)
            try itemTag.step()
        }
        let store = SecondBrainStore(database: db)
        for (id, title) in [(firstID, "Zulu"), (secondID, "Alpha"), (excludedID, "Middle")] {
            try index(itemID: id, ownerType: "todo", title: title, body: "shared needle", store: store)
        }
        let first = TodoCard(id: firstID, title: "Zulu", labelIDs: [firstTagID], folderID: folderID)
        let second = TodoCard(id: secondID, title: "Alpha", labelIDs: [secondTagID], folderID: folderID)
        let excluded = TodoCard(id: excludedID, title: "Middle", folderID: folderID)

        let response = await LibraryCanonicalSearchAdapter(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        ).search(
            items: [.todo(first), .todo(second), .todo(excluded)],
            filter: LibraryFilterSpec(
                entityTypes: [.todo],
                labelIDs: [firstTagID, secondTagID],
                folderID: folderID,
                includeCompleted: false,
                textQuery: "needle"
            ),
            sort: LibrarySortSpec(mode: .titleAscending),
            folders: [Folder(id: folderID, name: "Work")],
            labels: [
                CardLabel(id: firstTagID, name: "First"),
                CardLabel(id: secondTagID, name: "Second"),
            ]
        )

        #expect(response.items.map(\.title) == ["Alpha", "Zulu"])
        #expect(response.canonical?.query.facets.folder == .folderIDs([folderID]))
        #expect(response.canonical?.query.facets.tagIDs.isEmpty == true)
        #expect(Set(response.canonicalItemIDs) == [firstID, secondID, excludedID])
    }

    @Test("Library reports canonical matches that its current snapshot cannot project")
    func unprojectedCanonicalMatchIsTruthful() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let noteID = UUID()
        try insertItem(id: noteID, type: "note", title: "Missing projection", into: db)
        let store = SecondBrainStore(database: db)
        try index(itemID: noteID, ownerType: "note", title: "Missing projection", body: "violet horizon", store: store)

        let response = await LibraryCanonicalSearchAdapter(
            contextService: CiderItemContextService(database: db, secondBrainStore: store)
        ).search(
            items: [],
            filter: LibraryFilterSpec(textQuery: "violet horizon"),
            sort: LibrarySortSpec(),
            folders: [],
            labels: []
        )

        #expect(response.items.isEmpty)
        #expect(response.canonicalItemIDs == [noteID])
        #expect(response.unprojectedCanonicalItemIDs == [noteID])
        #expect(response.emptyStateMessage?.contains("cannot be presented") == true)
    }

    @Test("cancelled Library work and superseded requests cannot publish")
    func cancellationAndSupersededPublishPolicy() async throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let task = Task { @MainActor in
            await LibraryCanonicalSearchAdapter(
                contextService: CiderItemContextService(database: db)
            ).search(
                items: [],
                filter: LibraryFilterSpec(textQuery: "needle"),
                sort: LibrarySortSpec(),
                folders: [],
                labels: []
            )
        }
        task.cancel()
        let response = await task.value
        let oldID = UUID()
        let currentID = UUID()

        #expect(response.status == .cancelled)
        #expect(response.items.isEmpty)
        #expect(!LibrarySearchPublishPolicy.canPublish(
            requestID: oldID,
            activeRequestID: currentID,
            isCancelled: false
        ))
        #expect(!LibrarySearchPublishPolicy.canPublish(
            requestID: currentID,
            activeRequestID: currentID,
            isCancelled: true
        ))
        #expect(LibrarySearchPublishPolicy.canPublish(
            requestID: currentID,
            activeRequestID: currentID,
            isCancelled: false
        ))
    }
}
