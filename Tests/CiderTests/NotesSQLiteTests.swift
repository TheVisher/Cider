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

    private func makeTempVaultURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-notes-vault-\(UUID().uuidString)", isDirectory: true)
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

    @Test("addTag and removeTag record mutation audit entries")
    func tagMutationsRecordAuditEntries() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let note = Note(
            title: "Audited Tags",
            content: "body",
            relativePath: "Inbox/Notes/Audited Tags.md"
        )
        service.persistNoteToDatabase(db, note: note)

        let service2 = makeService(db)
        service2.loadNotesFromDatabase(db)

        #expect(service2.addTag(note.id, tag: "architecture") == true)
        #expect(service2.removeTag(note.id, tag: "architecture") == true)

        let entries = MutationAuditService(database: db).loadEntries()
        let add = entries.first { $0.itemID == note.id && $0.action == "add_tag" }
        let remove = entries.first { $0.itemID == note.id && $0.action == "remove_tag" }

        #expect(add?.itemType == "note")
        #expect(add?.beforeState["tagCount"] == "0")
        #expect(add?.afterState["tagCount"] == "1")
        #expect(add?.metadata["tag"] == "architecture")

        #expect(remove?.itemType == "note")
        #expect(remove?.beforeState["tagCount"] == "1")
        #expect(remove?.afterState["tagCount"] == "0")
        #expect(remove?.metadata["tag"] == "architecture")
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

    @Test("SQLite load collapses exact duplicate note rows into one displayed note")
    func sqliteLoadCollapsesExactDuplicateNoteRows() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let canonicalID = UUID()
        let duplicateID = UUID()
        let service = makeService(db)
        let content = "Purpose: Track movies Erik loves, taste anchors, favorite genres/vibes, and future recommendation signals."

        let canonical = Note(
            id: canonicalID,
            title: "Movies Library",
            content: content,
            createdAt: Date(timeIntervalSince1970: 1_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: "Media/Movies Library.md",
            tags: ["media"]
        )
        let duplicate = Note(
            id: duplicateID,
            title: "Movies Library 2 2",
            content: content,
            summary: "Duplicate row summary that should be preserved.",
            createdAt: Date(timeIntervalSince1970: 1_500),
            modifiedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Media/Movies Library 2 2.md",
            tags: ["duplicate"]
        )

        service.persistNoteToDatabase(db, note: canonical)
        service.persistNoteToDatabase(db, note: duplicate)

        let displayService = makeService(db)
        displayService.loadNotesFromDatabase(db)

        #expect(displayService.notes.count == 1)
        let displayed = try #require(displayService.notes.first)
        #expect(displayed.id == canonicalID)
        #expect(displayed.title == "Movies Library")
        #expect(displayed.content == content)
        #expect(displayed.summary == "Duplicate row summary that should be preserved.")
        #expect(Set(displayed.tags) == Set(["media", "duplicate"]))
        #expect(displayed.relativePath == "Media/Movies Library.md")

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes.first?.id == canonicalID)
    }

    @Test("SQLite load collapses duplicate note rows with dated titles")
    func sqliteLoadCollapsesDatedDuplicateNoteRows() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let canonicalID = UUID()
        let duplicateID = UUID()
        let service = makeService(db)

        let canonical = Note(
            id: canonicalID,
            title: "QA Cider thought save test 20260515-1349",
            content: "",
            createdAt: Date(timeIntervalSince1970: 1_000),
            modifiedAt: Date(timeIntervalSince1970: 2_000),
            relativePath: "Inbox/Notes/QA Cider thought save test 20260515-1349.md",
            tags: ["qa"]
        )
        let duplicate = Note(
            id: duplicateID,
            title: "QA Cider thought save test 20260515-1349 2",
            content: "",
            createdAt: Date(timeIntervalSince1970: 1_500),
            modifiedAt: Date(timeIntervalSince1970: 3_000),
            relativePath: "Inbox/Notes/QA Cider thought save test 20260515-1349 2.md",
            tags: ["duplicate"]
        )

        service.persistNoteToDatabase(db, note: canonical)
        service.persistNoteToDatabase(db, note: duplicate)

        let displayService = makeService(db)
        displayService.loadNotesFromDatabase(db)

        #expect(displayService.notes.count == 1)
        let displayed = try #require(displayService.notes.first)
        #expect(displayed.id == canonicalID)
        #expect(displayed.title == "QA Cider thought save test 20260515-1349")
        #expect(Set(displayed.tags) == Set(["qa", "duplicate"]))
        #expect(displayed.relativePath == "Inbox/Notes/QA Cider thought save test 20260515-1349.md")
    }

    @Test("Markdown rescan preserves same filename notes in legacy and inbox paths")
    func markdownRescanPreservesSameFilenameInDistinctNoteRoots() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let legacyDir = StoragePaths.directoryURL(for: .notes)
        let inboxDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        try "Legacy body".write(to: legacyDir.appendingPathComponent("Shared.md"), atomically: true, encoding: .utf8)
        try "Inbox body".write(to: inboxDir.appendingPathComponent("Shared.md"), atomically: true, encoding: .utf8)

        let legacyID = UUID()
        let inboxID = UUID()
        let service = makeService(db)
        service.persistNoteToDatabase(
            db,
            note: Note(
                id: legacyID,
                title: "Shared",
                content: "Legacy body",
                createdAt: Date(timeIntervalSince1970: 1_000),
                modifiedAt: Date(timeIntervalSince1970: 1_100),
                relativePath: "Shared.md"
            )
        )
        service.persistNoteToDatabase(
            db,
            note: Note(
                id: inboxID,
                title: "Shared",
                content: "Inbox body",
                createdAt: Date(timeIntervalSince1970: 2_000),
                modifiedAt: Date(timeIntervalSince1970: 2_100),
                relativePath: "Inbox/Notes/Shared.md"
            )
        )

        let reconciler = makeService(db)
        reconciler.loadNotesFromDatabase(db)
        reconciler.rescan()

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)

        #expect(Set(reloaded.notes.map(\.id)) == Set([legacyID, inboxID]))
        #expect(Set(reloaded.notes.map(\.relativePath)) == Set(["Shared.md", "Inbox/Notes/Shared.md"]))
        #expect(Set(reloaded.notes.map(\.content)) == Set(["Legacy body", "Inbox body"]))
    }

    @Test("Markdown rescan ignores directories with md suffix")
    func markdownRescanIgnoresDirectoriesWithMDSuffix() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inboxDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        try fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        let directoryNamedLikeNote = inboxDir.appendingPathComponent("Voice journal - Ute-Janine trains.md", isDirectory: true)
        try fm.createDirectory(at: directoryNamedLikeNote, withIntermediateDirectories: true)

        let reconciler = makeService(db)
        reconciler.rescan()

        #expect(reconciler.notes.isEmpty)

        let countStmt = try db.prepare("""
            SELECT count(*)
            FROM items
            WHERE type = 'note'
              AND relative_path = 'Inbox/Notes/Voice journal - Ute-Janine trains.md';
            """)
        try countStmt.step()
        #expect(countStmt.int(at: 0) == 0)
    }

    @Test("Project artifact rescan reuses existing item row by relative path")
    func projectArtifactRescanReusesExistingItemRowByRelativePath() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let projectNoteRelativePath = "Projects/Cider/QA/Runtime Hang Audit.md"
        let projectNoteURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(projectNoteRelativePath)
        try fm.createDirectory(at: projectNoteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Runtime evidence".write(to: projectNoteURL, atomically: true, encoding: .utf8)
        let newProjectNoteRelativePath = "Projects/Cider/QA/Fresh Runtime Finding.md"
        let newProjectNoteURL = StoragePaths.cachedVaultDirectoryURL.appendingPathComponent(newProjectNoteRelativePath)
        try "Fresh evidence".write(to: newProjectNoteURL, atomically: true, encoding: .utf8)

        let existingID = UUID()
        let seeded = makeService(db)
        seeded.persistNoteToDatabase(
            db,
            note: Note(
                id: existingID,
                title: "Runtime Hang Audit",
                content: "Runtime evidence",
                createdAt: Date(timeIntervalSince1970: 1_000),
                modifiedAt: Date(timeIntervalSince1970: 2_000),
                relativePath: projectNoteRelativePath
            )
        )

        let reconciler = makeService(db)
        reconciler.loadNotesFromDatabase(db)
        reconciler.rescan()

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)

        let matchingNotes = reloaded.notes.filter { $0.relativePath == projectNoteRelativePath }
        #expect(matchingNotes.map(\.id) == [existingID])
        #expect(matchingNotes.first?.projectID == "cider")
        #expect(matchingNotes.first?.artifactType == "qa")
        #expect(reloaded.notes.contains { $0.relativePath == newProjectNoteRelativePath })

        let countStmt = try db.prepare("""
            SELECT count(*)
            FROM items
            WHERE type = 'note'
              AND relative_path = ?;
            """)
        countStmt.bind(projectNoteRelativePath, at: 1)
        try countStmt.step()
        #expect(countStmt.int(at: 0) == 1)
    }

    @Test("Markdown rescan collapses exact duplicate note artifacts")
    func markdownRescanCollapsesExactDuplicateNoteArtifacts() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inboxDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        try fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        let content = """
        # Games Library

        Seeded: 2026-04-30
        Purpose: Track games Erik loves and future recommendation signals.
        """
        let canonicalURL = inboxDir.appendingPathComponent("Games Library.md")
        let duplicateURL = inboxDir.appendingPathComponent("Games Library 2.md")
        try content.write(to: canonicalURL, atomically: true, encoding: .utf8)
        try content.write(to: duplicateURL, atomically: true, encoding: .utf8)

        let reconciler = makeService(db)
        reconciler.rescan()

        #expect(reconciler.notes.count == 1)
        #expect(reconciler.notes.first?.title == "Games Library")
        #expect(fm.fileExists(atPath: canonicalURL.path))
        #expect(!fm.fileExists(atPath: duplicateURL.path))
        #expect(!fm.fileExists(atPath: inboxDir.appendingPathComponent(".deduplicated").path))

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)
        #expect(reloaded.notes.count == 1)
        #expect(reloaded.notes.first?.relativePath == "Inbox/Notes/Games Library.md")

        let auditEntries = MutationAuditService(database: db).loadEntries()
        let pruneEntry = auditEntries.first { entry in
            entry.action == "scanner.note.delete_exact_duplicate_file"
                && entry.beforeState["relativePath"] == "Inbox/Notes/Games Library 2.md"
        }
        #expect(pruneEntry?.itemType == "note")
        #expect(pruneEntry?.source == .filesystem)
        #expect(pruneEntry?.metadata["operation"] == "delete_exact_duplicate_file")
        #expect(pruneEntry?.metadata["scanner"] == "NotesStorage.rescan")
        #expect(pruneEntry?.metadata["relativePath"] == "Inbox/Notes/Games Library 2.md")
    }

    @Test("Sync pull skips exact duplicate note instead of creating suffixed Markdown")
    func addFromSyncSkipsExactDuplicateNote() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let inboxDir = StoragePaths.cachedInboxSubdirectoryURL(for: .notes)
        try fm.createDirectory(at: inboxDir, withIntermediateDirectories: true)
        let content = """
        # Movies Library

        Seeded: 2026-04-30
        Purpose: Track movies Erik loves and future recommendation signals.
        """
        let canonicalURL = inboxDir.appendingPathComponent("Movies Library.md")
        try content.write(to: canonicalURL, atomically: true, encoding: .utf8)

        let existingID = UUID()
        let service = makeService(db)
        service.persistNoteToDatabase(
            db,
            note: Note(
                id: existingID,
                title: "Movies Library",
                content: content,
                createdAt: Date(timeIntervalSince1970: 1_000),
                modifiedAt: Date(timeIntervalSince1970: 2_000),
                relativePath: "Inbox/Notes/Movies Library.md",
                tags: ["media"]
            )
        )
        service.loadNotesFromDatabase(db)

        service.addFromSync(
            id: UUID(),
            title: "Movies Library 2",
            content: content,
            folderID: nil,
            isPinned: false,
            tags: ["sync"],
            createdAt: Date(timeIntervalSince1970: 3_000),
            updatedAt: Date(timeIntervalSince1970: 4_000)
        )

        #expect(service.notes.count == 1)
        let merged = try #require(service.notes.first)
        #expect(merged.id == existingID)
        #expect(merged.title == "Movies Library")
        #expect(Set(merged.tags) == Set(["media", "sync"]))
        #expect(fm.fileExists(atPath: canonicalURL.path))
        #expect(!fm.fileExists(atPath: inboxDir.appendingPathComponent("Movies Library 2.md").path))
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

    @Test("togglePin records mutation audit entry")
    func togglePinRecordsMutationAuditEntry() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let initial = makeService(db)
        let note = Note(
            title: "Audit Pin",
            content: "Body",
            relativePath: "Inbox/Notes/Audit Pin.md",
            isPinned: false
        )
        initial.persistNoteToDatabase(db, note: note)

        let service = makeService(db)
        service.loadNotesFromDatabase(db)

        let toggled = service.togglePin(note.id)
        #expect(toggled == true)

        let entries = MutationAuditService(database: db).loadEntries()
        let entry = entries.first { $0.itemID == note.id && $0.action == "toggle_pin" }
        #expect(entry?.itemType == "note")
        #expect(entry?.beforeState["isPinned"] == "false")
        #expect(entry?.afterState["isPinned"] == "true")
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

    // MARK: - Project Notes

    @Test("Project notes are file-backed under project containers and reload explicit project ownership")
    func projectNotesAreFileBackedAndReloadOwnership() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let note = service.createProjectNote(
            projectID: "cider",
            title: "Project Native Notes",
            content: "# Body\nFile-backed project note."
        )

        #expect(note.projectID == "cider")
        #expect(note.artifactType == "note")
        #expect(note.relativePath == "Projects/Cider/Notes/Project Native Notes.md")
        let fileURL = vault.appendingPathComponent(note.relativePath)
        #expect(fm.fileExists(atPath: fileURL.path))
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "# Body\nFile-backed project note.")

        let relationStmt = try db.prepare("""
            SELECT target_owner_type, target_owner_id, relation_type, metadata
            FROM owner_relations
            WHERE source_owner_type = 'note' AND source_owner_id = ?;
            """)
        relationStmt.bind(DatabaseHelpers.encode(note.id), at: 1)
        #expect(try relationStmt.step())
        #expect(relationStmt.string(at: 0) == "project")
        #expect(relationStmt.string(at: 1) == "cider")
        #expect(relationStmt.string(at: 2) == "artifact_of")
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: relationStmt.optionalString(at: 3)) ?? [:]
        #expect(metadata["artifactType"] == "note")
        #expect(metadata["path"] == note.relativePath)

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)
        #expect(reloaded.notes.count == 1)
        let loaded = try #require(reloaded.notes.first(where: { $0.id == note.id }))
        #expect(loaded.projectID == "cider")
        #expect(loaded.artifactType == "note")
        #expect(reloaded.loadContent(for: loaded) == "# Body\nFile-backed project note.")
    }

    @Test("Project handoff artifacts are file-backed under project handoffs and reload explicit ownership")
    func projectHandoffArtifactsAreFileBackedAndReloadOwnership() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let handoff = service.createProjectNote(
            projectID: "cider",
            title: "Cody Handoff 2c0a04",
            content: "# Handoff\nA long handoff body that belongs in Cider, not Discord.",
            artifactType: "handoff"
        )

        #expect(handoff.projectID == "cider")
        #expect(handoff.artifactType == "handoff")
        #expect(handoff.relativePath == "Projects/Cider/Handoffs/Cody Handoff 2c0a04.md")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent(handoff.relativePath).path))

        let relationStmt = try db.prepare("""
            SELECT target_owner_type, target_owner_id, relation_type, metadata
            FROM owner_relations
            WHERE source_owner_type = 'note' AND source_owner_id = ?;
            """)
        relationStmt.bind(DatabaseHelpers.encode(handoff.id), at: 1)
        #expect(try relationStmt.step())
        #expect(relationStmt.string(at: 0) == "project")
        #expect(relationStmt.string(at: 1) == "cider")
        #expect(relationStmt.string(at: 2) == "artifact_of")
        let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: relationStmt.optionalString(at: 3)) ?? [:]
        #expect(metadata["artifactType"] == "handoff")
        #expect(metadata["path"] == handoff.relativePath)

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)
        let loaded = try #require(reloaded.notes.first(where: { $0.id == handoff.id }))
        #expect(loaded.projectID == "cider")
        #expect(loaded.artifactType == "handoff")
        #expect(reloaded.loadContent(for: loaded).contains("not Discord"))
    }

    @Test("Project note metadata is inferred from project note path when relation metadata is missing")
    func projectNoteMetadataFallsBackToProjectPath() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let note = Note(
            title: "Path Owned Note",
            content: "body",
            relativePath: "Projects/Cider/Notes/Path Owned Note.md"
        )
        service.persistNoteToDatabase(db, note: note)

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)

        let loaded = try #require(reloaded.notes.first(where: { $0.id == note.id }))
        #expect(loaded.projectID == "cider")
        #expect(loaded.artifactType == "note")

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let model = ProjectWorkspaceSurfaceProvider.model(
            for: catalog.workspace(id: "cider")!,
            surface: .notes,
            notes: reloaded.notes
        )
        #expect(model.notes.map(\.id) == [note.id])
    }

    @Test("Project note metadata survives duplicate canonicalization during rescan")
    func projectNoteMetadataSurvivesDuplicateCanonicalizationDuringRescan() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let body = "# Shared\nSame body."
        let legacy = Note(
            title: "Shared Duplicate",
            content: body,
            relativePath: "Shared Duplicate.md"
        )
        let project = Note(
            title: "Shared Duplicate",
            content: body,
            relativePath: "Projects/Cider/Notes/Shared Duplicate.md",
            projectID: "cider",
            artifactType: "note"
        )
        try fm.createDirectory(
            at: StoragePaths.directoryURL(for: .notes),
            withIntermediateDirectories: true
        )
        try body.write(to: StoragePaths.directoryURL(for: .notes).appendingPathComponent("Shared Duplicate.md"), atomically: true, encoding: .utf8)
        let projectFile = vault.appendingPathComponent(project.relativePath)
        try fm.createDirectory(at: projectFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try body.write(to: projectFile, atomically: true, encoding: .utf8)
        service.persistNoteToDatabase(db, note: legacy)
        service.persistNoteToDatabase(db, note: project)

        service.loadNotesFromDatabase(db)
        service.rescan()

        let projectNotes = service.notes.filter { $0.projectID == "cider" && $0.artifactType == "note" }
        #expect(projectNotes.count == 1)
        #expect(projectNotes.first?.relativePath == "Projects/Cider/Notes/Shared Duplicate.md")
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let model = ProjectWorkspaceSurfaceProvider.model(
            for: catalog.workspace(id: "cider")!,
            surface: .notes,
            notes: service.notes
        )
        #expect(model.notes.count == 1)
        #expect(model.notes.first?.path == "Projects/Cider/Notes/Shared Duplicate.md")
    }

    @Test("Cider project note seed creates a visible project note once")
    func ciderProjectNoteSeedCreatesVisibleProjectNoteOnce() throws {
        let (db, url) = try makeTestDB()
        let vault = makeTempVaultURL()
        let fm = FileManager.default
        defer {
            db.close()
            cleanup(url)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
            try? fm.removeItem(at: vault)
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let first = service.ensureCiderProjectNoteSeedIfNeeded()
        let second = service.ensureCiderProjectNoteSeedIfNeeded()

        #expect(first != nil)
        let firstID = try #require(first?.id)
        #expect(second?.id == firstID)
        #expect(service.notes.filter { $0.projectID == "cider" && $0.artifactType == "note" }.count == 1)
        #expect(first?.relativePath == "Projects/Cider/Notes/Cider Project Notes.md")
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Projects/Cider/Notes/Cider Project Notes.md").path))
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Projects/Cider/Decisions").path))
        #expect(fm.fileExists(atPath: vault.appendingPathComponent("Projects/Cider/QA").path))
        #expect(try itemRowCount(db, id: firstID, relativePath: "Projects/Cider/Notes/Cider Project Notes.md") == 1)
        #expect(try noteRowCount(db, id: firstID) == 1)
        #expect(try projectNoteRelationRowCount(db, id: firstID, relativePath: "Projects/Cider/Notes/Cider Project Notes.md") == 1)

        service.rescan()
        #expect(service.notes.filter { $0.projectID == "cider" && $0.artifactType == "note" }.count == 1)
        #expect(try itemRowCount(db, id: firstID, relativePath: "Projects/Cider/Notes/Cider Project Notes.md") == 1)
        #expect(try noteRowCount(db, id: firstID) == 1)
        #expect(try projectNoteRelationRowCount(db, id: firstID, relativePath: "Projects/Cider/Notes/Cider Project Notes.md") == 1)

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [KanbanBoard(id: "2afee0", name: "Cider")])
        let model = ProjectWorkspaceSurfaceProvider.model(
            for: catalog.workspace(id: "cider")!,
            surface: .notes,
            notes: service.notes
        )
        #expect(model.notes.map(\.id) == [firstID])

        let reloaded = makeService(db)
        reloaded.loadNotesFromDatabase(db)
        #expect(reloaded.notes.filter { $0.projectID == "cider" && $0.artifactType == "note" }.count == 1)
    }

    @Test("Cider project note seed repairs dangling relation into item and note rows")
    func ciderProjectNoteSeedRepairsDanglingRelationIntoRows() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()
        let service = makeService(db)
        let relativePath = "Projects/Cider/Notes/Cider Project Notes.md"
        let fileURL = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Cider Project Notes\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let danglingID = UUID(uuidString: "D94674C0-ACC9-493E-AE24-A15DE6C4B5B5")!
        try SecondBrainStore(database: db).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: danglingID.uuidString),
            targetOwner: SecondBrainProjectGraphService.owner(projectID: "cider"),
            relationType: "artifact_of",
            evidence: "Pre-existing dangling project note relation from dogfood failure.",
            source: "project_notes",
            actor: "cider",
            confidence: 1,
            metadata: [
                "title": "Cider Project Notes",
                "artifactType": "note",
                "path": relativePath
            ]
        ))
        #expect(try itemRowCount(db, id: danglingID, relativePath: relativePath) == 0)
        #expect(try noteRowCount(db, id: danglingID) == 0)
        #expect(try projectNotePathRelationRowCount(db, relativePath: relativePath) == 1)

        let repaired = try #require(service.ensureCiderProjectNoteSeedIfNeeded())
        #expect(repaired.id == danglingID)
        #expect(try itemRowCount(db, id: danglingID, relativePath: relativePath) == 1)
        #expect(try noteRowCount(db, id: danglingID) == 1)
        #expect(try projectNoteRelationRowCount(db, id: danglingID, relativePath: relativePath) == 1)
        #expect(try projectNotePathRelationRowCount(db, relativePath: relativePath) == 1)

        service.rescan()
        let repairedProjectNoteCount = service.notes.filter { note in
            note.id == danglingID && note.projectID == "cider" && note.artifactType == "note"
        }.count
        #expect(repairedProjectNoteCount == 1)
        #expect(try itemRowCount(db, id: danglingID, relativePath: relativePath) == 1)
        #expect(try noteRowCount(db, id: danglingID) == 1)
        #expect(try projectNotePathRelationRowCount(db, relativePath: relativePath) == 1)
    }

    @Test("Rescan persists externally added project QA artifacts")
    func rescanPersistsExternallyAddedProjectQAArtifacts() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let existing = Note(
            title: "Existing Note",
            content: "Already canonical.",
            relativePath: "Inbox/Notes/Existing Note.md"
        )
        let existingFileURL = vault.appendingPathComponent(existing.relativePath)
        try FileManager.default.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existing.content.write(to: existingFileURL, atomically: true, encoding: .utf8)
        service.persistNoteToDatabase(db, note: existing)
        service.loadNotesFromDatabase(db)

        let relativePath = "Projects/Cider/QA/External QA Audit.md"
        let fileURL = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# External QA Audit\n\nNew artifact from disk.\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        service.rescan()

        let adopted = try #require(service.notes.first { $0.relativePath == relativePath })
        #expect(adopted.projectID == "cider")
        #expect(adopted.artifactType == "qa")
        #expect(try noteItemCount(db) == service.notes.count)
        #expect(try noteItemExists(db, id: adopted.id, title: "External QA Audit", relativePath: relativePath))
        #expect(try noteRowCount(db, id: adopted.id) == 1)
        #expect(try projectNoteRelationRowCount(db, id: adopted.id, relativePath: relativePath) == 1)
    }

    @Test("Rescan adopts project artifact by existing note path before dangling relation")
    func rescanAdoptsProjectArtifactByExistingNotePathBeforeDanglingRelation() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let relativePath = "Projects/Cider/QA/Relation Drift Audit.md"
        let fileURL = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Relation Drift Audit\n\nCanonical file body.\n".write(
            to: fileURL,
            atomically: true,
            encoding: .utf8
        )

        let pathOwnerID = UUID(uuidString: "B2E81346-2B16-41D5-8863-978AFC4C9474")!
        let danglingRelationID = UUID(uuidString: "6B482882-2EB1-495F-A5E2-A57B0672B0ED")!
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
            VALUES ('\(pathOwnerID.uuidString)', 'note', 'Relation Drift Audit', 1, 1, '\(relativePath)');
            INSERT INTO notes (item_id, content, summary, is_pinned)
            VALUES ('\(pathOwnerID.uuidString)', 'Existing DB body', NULL, 0);
            """)
        try SecondBrainStore(database: db).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: danglingRelationID.uuidString),
            targetOwner: SecondBrainProjectGraphService.owner(projectID: "cider"),
            relationType: "artifact_of",
            evidence: "Stale relation left behind by an earlier failed rescan.",
            source: "project_notes",
            actor: "test",
            confidence: 1,
            metadata: [
                "title": "Relation Drift Audit",
                "artifactType": "qa",
                "path": relativePath
            ]
        ))

        service.loadNotesFromDatabase(db)
        service.rescan()

        let adopted = try #require(service.notes.first { $0.relativePath == relativePath })
        #expect(adopted.id == pathOwnerID)
        #expect(try noteItemExists(db, id: pathOwnerID, title: "Relation Drift Audit", relativePath: relativePath))
        #expect(try noteRowCount(db, id: pathOwnerID) == 1)
        #expect(try projectNoteRelationRowCount(db, id: pathOwnerID, relativePath: relativePath) == 1)
        #expect(try projectNotePathRelationRowCount(db, relativePath: relativePath) == 1)
    }

    @Test("Rescan rehomes legacy vault-file project Markdown rows into notes")
    func rescanRehomesLegacyVaultFileProjectMarkdownRowsIntoNotes() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let existing = Note(
            title: "Existing Note",
            content: "Already canonical.",
            relativePath: "Inbox/Notes/Existing Note.md"
        )
        let existingFileURL = vault.appendingPathComponent(existing.relativePath)
        try FileManager.default.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existing.content.write(to: existingFileURL, atomically: true, encoding: .utf8)
        service.persistNoteToDatabase(db, note: existing)

        let conflictingRelativePath = "Projects/Cider/QA/Conflicting QA Audit.md"
        let conflictingID = UUID(uuidString: "5480D8D8-7C51-48C3-88FA-F0D5E2DDE002")!
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
            VALUES ('\(conflictingID.uuidString)', 'vaultFile', 'Conflicting QA Audit', 1, 1, '\(conflictingRelativePath)');
            INSERT INTO vault_files (item_id, filename, file_type, file_size, notes, title_manually_set)
            VALUES ('\(conflictingID.uuidString)', 'Conflicting QA Audit.md', 'document', 22, '', 0);
            """)
        let conflictingFileURL = vault.appendingPathComponent(conflictingRelativePath)
        try FileManager.default.createDirectory(
            at: conflictingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Conflicting QA Audit\n".write(to: conflictingFileURL, atomically: true, encoding: .utf8)

        service.loadNotesFromDatabase(db)
        service.rescan()

        let adopted = try #require(service.notes.first { $0.relativePath == conflictingRelativePath })
        #expect(adopted.id == conflictingID)
        #expect(adopted.projectID == "cider")
        #expect(adopted.artifactType == "qa")
        #expect(try noteItemCount(db) == 2)
        #expect(try noteItemExists(db, id: existing.id, title: "Existing Note", relativePath: existing.relativePath))
        #expect(try noteItemExists(db, id: conflictingID, title: "Conflicting QA Audit", relativePath: conflictingRelativePath))
        #expect(try noteRowCount(db, id: conflictingID) == 1)
        #expect(try vaultFileRowCount(db, id: conflictingID) == 0)
        #expect(try projectNoteRelationRowCount(db, id: conflictingID, relativePath: conflictingRelativePath) == 1)
        let persistedNoteCount = try noteItemCount(db)
        #expect(service.notes.count == persistedNoteCount)
    }

    @Test("Rescan prunes orphan note item rows whose files are missing")
    func rescanPrunesOrphanNoteItemRowsWhoseFilesAreMissing() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let existing = Note(
            title: "Existing Note",
            content: "Already canonical.",
            relativePath: "Inbox/Notes/Existing Note.md"
        )
        let existingFileURL = vault.appendingPathComponent(existing.relativePath)
        try FileManager.default.createDirectory(
            at: existingFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try existing.content.write(to: existingFileURL, atomically: true, encoding: .utf8)
        service.persistNoteToDatabase(db, note: existing)

        let orphanID = UUID(uuidString: "26462C02-BD50-4E3A-9505-58187904896E")!
        let missingRelativePath = "Projects/Cider/QA/Missing QA Artifact 2.md"
        try db.runSQL("""
            INSERT INTO items (id, type, title, created_at, updated_at, relative_path)
            VALUES ('\(orphanID.uuidString)', 'note', 'Missing QA Artifact 2', 1, 1, '\(missingRelativePath)');
            """)

        service.loadNotesFromDatabase(db)
        #expect(service.notes.map(\.id) == [existing.id])
        #expect(try noteItemExists(db, id: orphanID, title: "Missing QA Artifact 2", relativePath: missingRelativePath))

        service.rescan()

        let orphanStillExists = try noteItemExists(db, id: orphanID, title: "Missing QA Artifact 2", relativePath: missingRelativePath)
        #expect(!orphanStillExists)
        #expect(try noteItemExists(db, id: existing.id, title: "Existing Note", relativePath: existing.relativePath))
        let persistedNoteCount = try noteItemCount(db)
        #expect(service.notes.count == persistedNoteCount)
    }

    @Test("Scanned duplicate relative paths canonicalize before SQLite sync")
    func scannedDuplicateRelativePathsCanonicalizeBeforeSQLiteSync() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }

        let service = makeService(db)
        let relativePath = "Inbox/Notes/Untitled.md"
        let stalePlaceholder = Note(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            title: "Untitled",
            content: "",
            relativePath: relativePath
        )
        let hydrated = Note(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            title: "Untitled",
            content: "Recovered content from the durable row.",
            relativePath: relativePath
        )

        let canonicalized = service.canonicalizedScannedNotesForTesting([stalePlaceholder, hydrated])

        #expect(canonicalized.notes.count == 1)
        #expect(canonicalized.notes[0].relativePath == relativePath)
        #expect(canonicalized.notes[0].content == hydrated.content)
        #expect(canonicalized.removedNotes.map(\.id) == [stalePlaceholder.id])
    }

    @Test("Rescan reuses SQLite item ID for externally captured inbox note paths")
    func rescanReusesSQLiteItemIDForExternallyCapturedInboxNotePaths() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let noteID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        let relativePath = "Inbox/Notes/CLI Captured Note.md"
        let fileURL = vault.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "Captured by another process.".write(to: fileURL, atomically: true, encoding: .utf8)

        let service = makeService(db)
        let persisted = Note(
            id: noteID,
            title: "CLI Captured Note",
            content: "Captured by another process.",
            relativePath: relativePath
        )
        service.persistNoteToDatabase(db, note: persisted)

        let rescanner = makeService(db)
        rescanner.rescan()

        let adopted = try #require(rescanner.notes.first { $0.relativePath == relativePath })
        #expect(adopted.id == noteID)
        #expect(try noteItemCount(db) == 1)
        #expect(try noteItemExists(db, id: noteID, title: "CLI Captured Note", relativePath: relativePath))
    }

    @Test("Rescan restores missing project artifact files from SQLite note content")
    func rescanRestoresMissingProjectArtifactFilesFromSQLiteNoteContent() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let noteID = UUID(uuidString: "26462C02-BD50-4E3A-9505-58187904896E")!
        let relativePath = "Projects/Cider/QA/Missing Content Artifact 2.md"
        let content = "# Missing Content Artifact\n\nSQLite has the durable body.\n"
        let note = Note(
            id: noteID,
            title: "Missing Content Artifact 2",
            content: content,
            relativePath: relativePath,
            projectID: "cider",
            artifactType: "qa"
        )
        service.persistNoteToDatabase(db, note: note)
        try SecondBrainStore(database: db).recordRelation(SecondBrainRelation(
            sourceOwner: SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString),
            targetOwner: SecondBrainProjectGraphService.owner(projectID: "cider"),
            relationType: "artifact_of",
            evidence: "Markdown project qa lives at \(relativePath).",
            source: "project_notes",
            actor: "test",
            confidence: 1,
            metadata: [
                "title": note.title,
                "artifactType": "qa",
                "path": relativePath
            ]
        ))

        let fileURL = vault.appendingPathComponent(relativePath)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        service.loadNotesFromDatabase(db)
        service.rescan()

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect((try? String(contentsOf: fileURL, encoding: .utf8)) == content)
        #expect(try noteItemExists(db, id: noteID, title: "Missing Content Artifact 2", relativePath: relativePath))
        let restored = try #require(service.notes.first { $0.id == noteID })
        #expect(restored.projectID == "cider")
        #expect(restored.artifactType == "qa")
    }

    @Test("Project decision and QA artifacts record typed relation producers")
    func projectDecisionAndQAArtifactsRecordTypedRelationProducers() throws {
        let (db, url) = try makeTestDB()
        defer { db.close(); cleanup(url) }
        let vault = makeTempVaultURL()
        defer {
            cleanup(vault)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }
        StoragePaths.vaultOverride = vault
        StoragePaths.invalidateCachedDirectory()

        let service = makeService(db)
        let decision = service.createProjectNote(
            projectID: "cider",
            title: "Decision source relation",
            content: "Decision body",
            artifactType: "decision"
        )
        let qa = service.createProjectNote(
            projectID: "cider",
            title: "QA relation producer",
            content: "QA body",
            artifactType: "qa"
        )
        let sourceCard = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/8b6f3c")
        let targetCard = SecondBrainOwnerRef(ownerType: "kanban_card", ownerID: "2afee0/2c0a04")

        let decisionRelations = ProjectArtifactRelationService.recordArtifactRelations(
            note: decision,
            targets: [
                .init(owner: sourceCard, relationType: ProjectArtifactRelationType.decidedFrom, title: "Project workspace relationship graph MVP")
            ],
            actor: "test",
            database: db
        )
        let qaRelations = ProjectArtifactRelationService.recordArtifactRelations(
            note: qa,
            targets: [
                .init(owner: targetCard, relationType: ProjectArtifactRelationType.validates, title: "Plans/Handoffs surface"),
                .init(owner: sourceCard, relationType: ProjectArtifactRelationType.foundBugIn, title: "Relationship graph MVP")
            ],
            actor: "test",
            database: db
        )

        #expect(decisionRelations.map(\.relationType) == [ProjectArtifactRelationType.decidedFrom])
        #expect(qaRelations.map(\.relationType).sorted() == [ProjectArtifactRelationType.foundBugIn, ProjectArtifactRelationType.validates].sorted())
        let decisionOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: decision.id.uuidString)
        let qaOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: qa.id.uuidString)
        let storedDecisionRelations = try SecondBrainStore(database: db).outgoingRelations(for: decisionOwner)
        let storedQARelations = try SecondBrainStore(database: db).outgoingRelations(for: qaOwner)
        #expect(storedDecisionRelations.contains { $0.relationType == ProjectArtifactRelationType.decidedFrom && $0.targetOwner == sourceCard })
        #expect(storedQARelations.contains { $0.relationType == ProjectArtifactRelationType.validates && $0.targetOwner == targetCard })
        #expect(storedQARelations.contains { $0.relationType == ProjectArtifactRelationType.foundBugIn && $0.targetOwner == sourceCard })
    }

    private func itemRowCount(_ db: CiderDatabase, id: UUID, relativePath: String) throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM items WHERE id = ? AND type = 'note' AND title = 'Cider Project Notes' AND relative_path = ?;")
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(relativePath, at: 2)
        guard try stmt.step() else { return 0 }
        return Int(stmt.int64(at: 0))
    }

    private func noteRowCount(_ db: CiderDatabase, id: UUID) throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM notes WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
        guard try stmt.step() else { return 0 }
        return Int(stmt.int64(at: 0))
    }

    private func vaultFileRowCount(_ db: CiderDatabase, id: UUID) throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM vault_files WHERE item_id = ?;")
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
        guard try stmt.step() else { return 0 }
        return Int(stmt.int64(at: 0))
    }

    private func noteItemCount(_ db: CiderDatabase) throws -> Int {
        let stmt = try db.prepare("SELECT COUNT(*) FROM items WHERE type = 'note';")
        guard try stmt.step() else { return 0 }
        return Int(stmt.int64(at: 0))
    }

    private func noteItemExists(_ db: CiderDatabase, id: UUID, title: String, relativePath: String) throws -> Bool {
        let stmt = try db.prepare("SELECT COUNT(*) FROM items WHERE id = ? AND type = 'note' AND title = ? AND relative_path = ?;")
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
            .bind(title, at: 2)
            .bind(relativePath, at: 3)
        guard try stmt.step() else { return false }
        return stmt.int64(at: 0) == 1
    }

    private func projectNoteRelationRowCount(_ db: CiderDatabase, id: UUID, relativePath: String) throws -> Int {
        let stmt = try db.prepare("""
            SELECT source_owner_id, metadata FROM owner_relations
            WHERE source_owner_type = 'note'
              AND source_owner_id = ?
              AND target_owner_type = 'project'
              AND target_owner_id = 'cider'
              AND relation_type = 'artifact_of';
            """)
        stmt.bind(DatabaseHelpers.encode(id), at: 1)
        var count = 0
        while try stmt.step() {
            let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 1)) ?? [:]
            if metadata["path"] == relativePath { count += 1 }
        }
        return count
    }

    private func projectNotePathRelationRowCount(_ db: CiderDatabase, relativePath: String) throws -> Int {
        let stmt = try db.prepare("""
            SELECT metadata FROM owner_relations
            WHERE source_owner_type = 'note'
              AND target_owner_type = 'project'
              AND target_owner_id = 'cider'
              AND relation_type = 'artifact_of';
            """)
        var count = 0
        while try stmt.step() {
            let metadata = DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 0)) ?? [:]
            if metadata["path"] == relativePath { count += 1 }
        }
        return count
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

}
