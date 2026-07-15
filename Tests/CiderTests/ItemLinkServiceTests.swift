import Foundation
import Testing
@testable import Cider

@Suite("Item Link Service Tests")
@MainActor
struct ItemLinkServiceTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-links-\(UUID().uuidString).db")
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

    private func insertItem(_ ref: LibraryEntityRef, title: String, into db: CiderDatabase) throws {
        let stmt = try db.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, ?, ?, ?, ?, NULL, NULL);
            """)
        stmt.bind(DatabaseHelpers.encode(ref.entityID), at: 1)
            .bind(ItemLinkService.databaseItemType(for: ref.type), at: 2)
            .bind(title, at: 3)
            .bind(DatabaseHelpers.encode(Date()), at: 4)
            .bind(DatabaseHelpers.encode(Date()), at: 5)
        try stmt.step()
    }

    @Test("Type parser accepts aliases and rejects legacy types")
    func typeParserAcceptsAliasesAndRejectsLegacyTypes() throws {
        #expect(try ItemLinkService.entityType(from: "bookmark") == .bookmark)
        #expect(try ItemLinkService.entityType(from: "date") == .dateCard)
        #expect(try ItemLinkService.entityType(from: "event") == .dateCard)
        #expect(try ItemLinkService.entityType(from: "file") == .vaultFile)

        #expect(throws: ItemLinkService.LinkError.self) {
            try ItemLinkService.entityType(from: "session")
        }
    }

    @Test("Direct links round trip through SQLite")
    func directLinksRoundTripThroughSQLite() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = ItemLinkService(database: db)
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let contact = LibraryEntityRef(type: .contact, entityID: UUID())
        try insertItem(bookmark, title: "Gift idea", into: db)
        try insertItem(contact, title: "Baine", into: db)

        try service.addDirectLink(from: bookmark, to: contact)

        #expect(try service.outgoingRefs(for: bookmark) == [contact])
        #expect(try service.backlinkRefs(for: contact) == [bookmark])
    }

    @Test("Duplicate links collapse in related refs")
    func duplicateLinksCollapseInRelatedRefs() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = ItemLinkService(database: db)
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let contact = LibraryEntityRef(type: .contact, entityID: UUID())
        try insertItem(bookmark, title: "Gift idea", into: db)
        try insertItem(contact, title: "Baine", into: db)

        try service.addDirectLink(from: bookmark, to: contact)
        try service.addDirectLink(from: contact, to: bookmark)
        try service.addDirectLink(from: bookmark, to: contact)

        #expect(try service.relatedRefs(for: contact) == [bookmark])
    }

    @Test("Direct link removal deletes the row")
    func directLinkRemovalDeletesTheRow() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = ItemLinkService(database: db)
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let contact = LibraryEntityRef(type: .contact, entityID: UUID())
        try insertItem(bookmark, title: "Gift idea", into: db)
        try insertItem(contact, title: "Baine", into: db)

        try service.addDirectLink(from: bookmark, to: contact)
        try service.removeDirectLink(from: bookmark, to: contact)

        #expect(try service.outgoingRefs(for: bookmark).isEmpty)
        #expect(try service.backlinkRefs(for: contact).isEmpty)
    }

    @Test("Link mutations record audit entries")
    func linkMutationsRecordAuditEntries() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = ItemLinkService(database: db)
        let bookmark = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let contact = LibraryEntityRef(type: .contact, entityID: UUID())
        try insertItem(bookmark, title: "Gift idea", into: db)
        try insertItem(contact, title: "Baine", into: db)

        try service.addDirectLink(from: bookmark, to: contact)
        try service.removeDirectLink(from: bookmark, to: contact)

        let entries = MutationAuditService(database: db).loadEntries()
        let added = entries.first { $0.itemID == bookmark.entityID && $0.action == "add_link" }
        let removed = entries.first { $0.itemID == bookmark.entityID && $0.action == "remove_link" }

        #expect(added?.itemType == "bookmark")
        #expect(added?.metadata["targetType"] == "contact")
        #expect(added?.metadata["targetID"] == contact.entityID.uuidString)

        #expect(removed?.itemType == "bookmark")
        #expect(removed?.metadata["targetType"] == "contact")
        #expect(removed?.metadata["targetID"] == contact.entityID.uuidString)
    }

    @Test("Canonical selector resolution returns one exact note and fails closed for duplicate or missing titles")
    func canonicalSelectorResolutionIsUniqueOrFailsClosed() throws {
        let (db, url) = try makeTestDB()
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-item-link-resolution-\(UUID().uuidString)", isDirectory: true)
        defer {
            db.close()
            cleanup(url)
            try? FileManager.default.removeItem(at: vaultRoot)
        }
        let notesRoot = vaultRoot.appendingPathComponent("Inbox/Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesRoot, withIntermediateDirectories: true)
        let notes = NotesStorage(
            database: db,
            notesDirectoryURL: notesRoot,
            vaultRootURL: vaultRoot
        )
        let first = notes.createNew(initialContent: "Synthetic fixture one")
        notes.rename(note: first, to: "Journal target alpha")
        let service = ItemLinkService(database: db, notes: notes)

        #expect(try service.resolve(type: .note, ref: "Journal target alpha") == .init(type: .note, entityID: first.id))

        let duplicate = notes.createNew(initialContent: "Synthetic fixture two")
        notes.rename(note: duplicate, to: "Journal target beta")
        #expect(throws: ItemLinkService.LinkError.self) {
            try service.resolve(type: .note, ref: "Journal target")
        }
        #expect(throws: ItemLinkService.LinkError.self) {
            try service.resolve(type: .note, ref: "No such note")
        }
    }
}
