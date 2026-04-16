import Foundation
import Testing
@testable import Cider

@Suite("Notes SQLite Tests")
@MainActor
struct NotesSQLiteTests {

    /// Create a temporary database URL for isolated testing.
    private func makeTempDBURL() -> URL {
        let dir = FileManager.default.temporaryDirectory
        let filename = "cider-note-test-\(UUID().uuidString).db"
        return dir.appendingPathComponent(filename)
    }

    /// Remove a temporary database file and its WAL/SHM companions.
    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let path = url.path
        try? fm.removeItem(atPath: path + "-wal")
        try? fm.removeItem(atPath: path + "-shm")
    }

    /// Create and open a fresh database for testing.
    private func makeTestDB() throws -> (CiderDatabase, URL) {
        let url = makeTempDBURL()
        let db = CiderDatabase()
        try db.open(at: url)
        return (db, url)
    }

    /// Create NotesStorage wired to the test database.
    private func makeService(_ db: CiderDatabase) -> NotesStorage {
        NotesStorage(database: db)
    }

    // MARK: - Basic Round-Trip

    @Test("addTag via service persists to item_tags (CLI flow)")
    func addTagViaServicePersists() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let note = Note(
            title: "CLI-flow Note",
            content: "body",
            relativePath: "Inbox/Notes/CLI-flow Note.md"
        )
        // Seed via persist path (mimics post-load state with empty tags).
        service.persistNoteToDatabase(db, note: note)

        // Fresh service reads notes from DB.
        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)
        #expect(service2.notes.count == 1)
        #expect(service2.notes[0].tags.isEmpty)

        // This is the exact path the CLI takes.
        let ok = service2.addTag(note.id, tag: "architecture")
        #expect(ok)
        let ok2 = service2.addTag(note.id, tag: "cider")
        #expect(ok2)

        // Inspect item_tags directly.
        let stmt = try db.prepare("""
            SELECT t.name FROM item_tags it
            JOIN tags t ON t.id = it.tag_id
            WHERE it.item_id = ?
            ORDER BY t.name;
            """)
        stmt.bind(DatabaseHelpers.encode(note.id), at: 1)
        var names: [String] = []
        while try stmt.step() {
            names.append(stmt.string(at: 0))
        }
        #expect(names == ["architecture", "cider"])
    }

    @Test("Note tags round-trip through item_tags join table")
    func noteTagsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        var note = Note(
            title: "Tagged Note",
            content: "body",
            relativePath: "Inbox/Notes/Tagged Note.md"
        )
        note.tags = ["architecture", "cider"]

        service.persistNoteToDatabase(db, note: note)

        // Verify item_tags rows landed
        let stmt = try db.prepare("""
            SELECT t.name FROM item_tags it
            JOIN tags t ON t.id = it.tag_id
            WHERE it.item_id = ?
            ORDER BY t.name;
            """)
        stmt.bind(DatabaseHelpers.encode(note.id), at: 1)
        var names: [String] = []
        while try stmt.step() {
            names.append(stmt.string(at: 0))
        }
        #expect(names == ["architecture", "cider"])

        // And that load rehydrates them
        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)
        let loaded = service2.notes.first { $0.id == note.id }
        #expect(loaded?.tags.sorted() == ["architecture", "cider"])
    }

    @Test("Note round-trips through SQLite: persist and load")
    func noteRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let note = Note(
            title: "Test Note",
            content: "Hello, world!",
            relativePath: "Inbox/Notes/Test Note.md"
        )

        service.persistNoteToDatabase(db, note: note)

        // Load into a fresh service
        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 1)
        let loaded = service2.notes[0]
        #expect(loaded.id == note.id)
        #expect(loaded.title == "Test Note")
        #expect(loaded.content == "Hello, world!")
        #expect(loaded.relativePath == "Inbox/Notes/Test Note.md")
    }

    // MARK: - All Fields

    @Test("Note with all fields round-trips correctly")
    func noteAllFields() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        // Create labels first (FK constraint)
        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "Work", colorHex: "#3B82F6")
        let label2 = labelStorage.createLabel(name: "Personal", colorHex: "#22C55E")

        // Create a folder (FK constraint)
        let folder = VaultFolder(relativePath: "Projects")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)

        let note = Note(
            title: "Full Note",
            content: "# Heading\n\nSome content here.",
            relativePath: "Projects/Full Note.md",
            labelIDs: [label1.id, label2.id],
            folderID: folder.id,
            isPinned: true
        )

        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 1)
        let loaded = service2.notes[0]
        #expect(loaded.title == "Full Note")
        #expect(loaded.content == "# Heading\n\nSome content here.")
        #expect(loaded.isPinned == true)
        #expect(loaded.folderID == folder.id)
        #expect(Set(loaded.labelIDs) == Set([label1.id, label2.id]))
    }

    @Test("Note summary round-trips through SQLite")
    func noteSummaryRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let note = Note(
            title: "Summarized",
            content: "Longer note body",
            summary: "Short summary for card display",
            relativePath: "Inbox/Notes/Summarized.md"
        )

        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 1)
        #expect(service2.notes[0].summary == "Short summary for card display")
    }

    // MARK: - Update

    @Test("Updating an existing note replaces its data")
    func updateNote() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        var note = Note(
            title: "Original Title",
            content: "Original content"
        )

        service.persistNoteToDatabase(db, note: note)

        // Update
        note.title = "Updated Title"
        note.content = "Updated content"
        note.isPinned = true
        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 1)
        let loaded = service2.notes[0]
        #expect(loaded.title == "Updated Title")
        #expect(loaded.content == "Updated content")
        #expect(loaded.isPinned == true)
    }

    // MARK: - Delete

    @Test("Delete note removes from items (CASCADE cleans detail + join tables)")
    func deleteNote() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "ToDelete")

        let service = makeService(db)

        let note = Note(
            title: "Doomed",
            content: "This will be deleted",
            labelIDs: [label.id]
        )

        service.persistNoteToDatabase(db, note: note)

        // Verify it exists
        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)
        #expect(service2.notes.count == 1)

        // Delete it
        service.deleteNoteFromDatabase(db, noteID: note.id)

        // Verify all traces are gone
        let service3 = makeService(db)
        service3.loadNotesFromDatabase(db)
        #expect(service3.notes.isEmpty)

        // Verify join tables are cleaned up via CASCADE
        let labelsStmt = try db.prepare("SELECT count(*) FROM item_labels WHERE item_id = ?;")
        labelsStmt.bind(DatabaseHelpers.encode(note.id), at: 1)
        try labelsStmt.step()
        #expect(labelsStmt.int(at: 0) == 0)

        // Verify the notes detail row is gone
        let noteStmt = try db.prepare("SELECT count(*) FROM notes WHERE item_id = ?;")
        noteStmt.bind(DatabaseHelpers.encode(note.id), at: 1)
        try noteStmt.step()
        #expect(noteStmt.int(at: 0) == 0)
    }

    // MARK: - Multiple Notes

    @Test("Multiple notes persist and load correctly")
    func multipleNotes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let n1 = Note(title: "First", content: "Content 1")
        let n2 = Note(title: "Second", content: "Content 2")
        let n3 = Note(title: "Third", content: "Content 3")

        service.persistNoteToDatabase(db, note: n1)
        service.persistNoteToDatabase(db, note: n2)
        service.persistNoteToDatabase(db, note: n3)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 3)
        let titles = Set(service2.notes.map(\.title))
        #expect(titles == Set(["First", "Second", "Third"]))
    }

    // MARK: - Label IDs

    @Test("Label IDs round-trip through item_labels join table")
    func labelIDsRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        // Insert labels first (FK constraint)
        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "Work", colorHex: "#3B82F6")
        let label2 = labelStorage.createLabel(name: "Personal", colorHex: "#22C55E")

        let service = makeService(db)

        let note = Note(
            title: "Labeled",
            content: "A labeled note",
            labelIDs: [label1.id, label2.id]
        )

        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        let loaded = service2.notes[0]
        #expect(Set(loaded.labelIDs) == Set([label1.id, label2.id]))
    }

    @Test("Updating labels replaces old label assignments")
    func labelIDsUpdate() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label1 = labelStorage.createLabel(name: "L1")
        let label2 = labelStorage.createLabel(name: "L2")
        let label3 = labelStorage.createLabel(name: "L3")

        let service = makeService(db)

        var note = Note(
            title: "Label Update",
            content: "Testing label updates",
            labelIDs: [label1.id, label2.id]
        )

        service.persistNoteToDatabase(db, note: note)

        // Update to different labels
        note.labelIDs = [label2.id, label3.id]
        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        let loaded = service2.notes[0]
        #expect(Set(loaded.labelIDs) == Set([label2.id, label3.id]))
    }

    // MARK: - Folder Assignment

    @Test("Note with folder ID round-trips")
    func noteWithFolder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        // Create a folder first (FK constraint)
        let folder = VaultFolder(relativePath: "Work")
        let folderService = VaultFolderService(database: db)
        folderService.persistToDatabase(db, folder: folder)

        let service = makeService(db)

        let note = Note(
            title: "In Folder",
            content: "A note in a folder",
            relativePath: "Work/In Folder.md",
            folderID: folder.id
        )

        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        let loaded = service2.notes[0]
        #expect(loaded.folderID == folder.id)
    }

    // MARK: - Empty Database

    @Test("Empty database loads empty notes array")
    func emptyDatabaseLoadsEmpty() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        service.loadNotesFromDatabase(db)

        #expect(service.notes.isEmpty)
    }

    // MARK: - Date Precision

    @Test("Date fields survive round-trip with reasonable precision")
    func datePrecision() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let now = Date()
        let note = Note(
            title: "Timed",
            content: "Date test",
            createdAt: now,
            modifiedAt: now
        )

        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        let loaded = service2.notes[0]
        #expect(abs(loaded.createdAt.timeIntervalSince(now)) < 0.001)
        #expect(abs(loaded.modifiedAt.timeIntervalSince(now)) < 0.001)
    }

    // MARK: - Pin Toggle

    @Test("Pin toggle persists through database")
    func pinToggle() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let note = Note(
            title: "Pin Test",
            content: "Not pinned",
            isPinned: false
        )

        service.persistNoteToDatabase(db, note: note)

        // Toggle pin
        var updated = note
        updated.isPinned = true
        service.persistNoteToDatabase(db, note: updated)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        let loaded = service2.notes[0]
        #expect(loaded.isPinned == true)
    }

    // MARK: - Sort Order

    // MARK: - Index Rehydration (Regression: C1)

    @Test("loadNotesFromDatabase rehydrates self.index so mutations don't no-op")
    func loadRehydratesIndex() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let note = Note(
            title: "Indexed",
            content: "Has an index entry",
            relativePath: "Inbox/Notes/Indexed.md"
        )
        service.persistNoteToDatabase(db, note: note)

        // Fresh service loading from DB — index must be non-empty after load.
        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 1)
        #expect(service2.indexEntryCount == 1)
        #expect(service2.indexFilename(for: note.id) == "Indexed.md")
    }

    @Test("togglePin through high-level API persists after DB-first load")
    func togglePinRoundTripAfterDBLoad() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let initial = makeService(db)
        let note = Note(
            title: "PinMe",
            content: "Body",
            relativePath: "Inbox/Notes/PinMe.md",
            isPinned: false
        )
        initial.persistNoteToDatabase(db, note: note)

        // Fresh service loads from SQLite (simulates cold launch)
        let service = makeService(db)
        service.loadNotesFromDatabase(db)
        #expect(service.indexEntryCount == 1)

        // Mutate via high-level API. This would silently fail if C1 regressed
        // (empty index means `if var entry = index[noteID]` never fires, but
        // DB persistence would still succeed via the notes array path).
        let toggled = service.togglePin(note.id)
        #expect(toggled == true)

        // Reload in another fresh service; pin state must have persisted.
        let verify = makeService(db)
        verify.loadNotesFromDatabase(db)
        #expect(verify.notes.count == 1)
        #expect(verify.notes[0].isPinned == true)
        #expect(verify.indexEntryCount == 1)
    }

    @Test("assignLabel through high-level API persists after DB-first load")
    func assignLabelRoundTripAfterDBLoad() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let labelStorage = CardLabelStorage(database: db)
        let label = labelStorage.createLabel(name: "AfterLoad", colorHex: "#FF0000")

        let initial = makeService(db)
        let note = Note(
            title: "Taggable",
            content: "Body",
            relativePath: "Inbox/Notes/Taggable.md"
        )
        initial.persistNoteToDatabase(db, note: note)

        // Fresh service loads from SQLite
        let service = makeService(db)
        service.loadNotesFromDatabase(db)
        #expect(service.indexEntryCount == 1)

        let assigned = service.assignLabel(note.id, labelID: label.id)
        #expect(assigned == true)

        // Reload — label must have persisted to join table.
        let verify = makeService(db)
        verify.loadNotesFromDatabase(db)
        #expect(verify.notes.count == 1)
        #expect(verify.notes[0].labelIDs == [label.id])
    }

    // MARK: - Empty relativePath Round-Trip (Regression: I5)

    @Test("Note with empty relativePath round-trips (NULL <-> empty string)")
    func emptyRelativePathRoundTrip() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let note = Note(
            title: "NoPath",
            content: "No relative path",
            relativePath: ""
        )
        service.persistNoteToDatabase(db, note: note)

        // Verify SQL-level: relative_path stored as NULL
        let stmt = try db.prepare("SELECT relative_path FROM items WHERE id = ?;")
        stmt.bind(DatabaseHelpers.encode(note.id), at: 1)
        try stmt.step()
        #expect(stmt.optionalString(at: 0) == nil)

        // Round-trip: loads back as empty string
        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 1)
        let loaded = service2.notes[0]
        #expect(loaded.id == note.id)
        #expect(loaded.relativePath == "")
        // Index filename should fall back to "{title}.md" when relativePath is empty
        #expect(service2.indexFilename(for: note.id) == "NoPath.md")
    }

    // MARK: - Sort Order

    @Test("Notes load sorted: pinned first, then by newest created")
    func sortOrder() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)

        let old = Note(title: "Old", content: "", createdAt: Date(timeIntervalSince1970: 1000))
        let new = Note(title: "New", content: "", createdAt: Date(timeIntervalSince1970: 2000))
        let pinned = Note(title: "Pinned", content: "", createdAt: Date(timeIntervalSince1970: 500), isPinned: true)

        service.persistNoteToDatabase(db, note: old)
        service.persistNoteToDatabase(db, note: new)
        service.persistNoteToDatabase(db, note: pinned)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.notes.count == 3)
        #expect(service2.notes[0].title == "Pinned")
        #expect(service2.notes[1].title == "New")
        #expect(service2.notes[2].title == "Old")
    }

    // MARK: - Sidecar UUID Recoverability

    @Test("SidecarItemMetadata round-trips id field through JSON")
    func sidecarMetadataEncodesID() throws {
        let id = UUID()
        let meta = SidecarItemMetadata(tags: ["foo"], summary: nil, date: nil, people: nil, id: id, extra: nil)

        let data = try JSONEncoder().encode(meta)
        let decoded = try JSONDecoder().decode(SidecarItemMetadata.self, from: data)

        #expect(decoded.id == id)
        #expect(decoded.tags == ["foo"])
        #expect(decoded.isEmpty == false)
    }

    @Test("SidecarItemMetadata with only id is NOT empty (identity must be preserved)")
    func sidecarMetadataIDKeepsEntryNonEmpty() {
        var meta = SidecarItemMetadata()
        #expect(meta.isEmpty == true)

        meta.id = UUID()
        #expect(meta.isEmpty == false, "Sidecar entry with only id set must not be treated as empty — otherwise note identity would be deleted")
    }

    @Test("SidecarFile round-trips note id via on-disk JSON")
    func sidecarFileRoundTripsNoteID() throws {
        // Write a SidecarFile containing a note entry with an id to a temp dir,
        // read it back, and verify the UUID survives. This is the exact format
        // SidecarService reads at launch via parseSidecarFile.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-sidecar-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let noteID = UUID()
        let filename = "My Note.md"
        let sidecarFile = SidecarFile(items: [
            filename: SidecarItemMetadata(tags: ["work"], summary: nil, date: nil, people: nil, id: noteID, extra: nil)
        ])

        let fileURL = tmp.appendingPathComponent(".cider-meta.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(sidecarFile)
        try data.write(to: fileURL, options: .atomic)

        // Read back and verify
        let readData = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode(SidecarFile.self, from: readData)

        #expect(decoded.items[filename]?.id == noteID)
        #expect(decoded.items[filename]?.tags == ["work"])
    }
}
