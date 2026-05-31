import Foundation
import Testing
@testable import Cider

@Suite("Notes Content IO Tests")
@MainActor
struct NotesContentIOTests {
    private func makeTempDBURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-note-io-test-\(UUID().uuidString).db")
    }

    private func makeTempVaultURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-note-io-vault-\(UUID().uuidString)", isDirectory: true)
    }

    private func cleanup(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        try? fm.removeItem(atPath: url.path + "-wal")
        try? fm.removeItem(atPath: url.path + "-shm")
    }

    private func makeService() throws -> (NotesStorage, CiderDatabase, URL, URL) {
        let dbURL = makeTempDBURL()
        let vaultURL = makeTempVaultURL()
        StoragePaths.vaultOverride = vaultURL
        StoragePaths.invalidateCachedDirectory()

        let db = CiderDatabase()
        try db.open(at: dbURL)
        return (NotesStorage(database: db), db, dbURL, vaultURL)
    }

    @Test("loadContentResult reports invalid UTF-8 without caching an empty body")
    func loadContentResultReportsInvalidUTF8WithoutCachingEmptyBody() throws {
        let (service, db, dbURL, vaultURL) = try makeService()
        defer {
            db.close()
            cleanup(dbURL)
            cleanup(vaultURL)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }

        let note = Note(
            title: "Unreadable",
            content: "",
            modifiedAt: Date(timeIntervalSince1970: 123),
            relativePath: "Inbox/Notes/Unreadable.md"
        )
        let fileURL = service.noteFileURL(for: note)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xff, 0xfe, 0xfd]).write(to: fileURL)

        let firstRead = service.loadContentResult(for: note)
        #expect(firstRead.content == nil)
        #expect(firstRead.issue?.operation == .read)
        #expect(service.lastContentIOIssue?.noteID == note.id)

        try "Recovered body".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(service.loadContent(for: note) == "Recovered body")
        #expect(service.lastContentIOIssue == nil)
    }

    @Test("missing note file reports a transient read issue without caching empty content")
    func missingNoteFileReportsReadIssueWithoutCachingEmptyContent() throws {
        let (service, db, dbURL, vaultURL) = try makeService()
        defer {
            db.close()
            cleanup(dbURL)
            cleanup(vaultURL)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }

        let note = Note(
            title: "Temporarily Missing",
            content: "",
            modifiedAt: Date(timeIntervalSince1970: 456),
            relativePath: "Inbox/Notes/Temporarily Missing.md"
        )
        let fileURL = service.noteFileURL(for: note)

        let missingRead = service.loadContentResult(for: note)
        #expect(missingRead.content == nil)
        #expect(missingRead.issue?.operation == .read)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "Now present".write(to: fileURL, atomically: true, encoding: .utf8)

        #expect(service.loadContent(for: note) == "Now present")
        #expect(service.lastContentIOIssue == nil)
    }

    @Test("save reports unreadable previous content and preserves disk bytes")
    func saveReportsUnreadablePreviousContentAndPreservesDiskBytes() throws {
        let (service, db, dbURL, vaultURL) = try makeService()
        defer {
            db.close()
            cleanup(dbURL)
            cleanup(vaultURL)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }

        let note = Note(
            title: "Invalid Previous",
            content: "Replacement body",
            modifiedAt: Date(timeIntervalSince1970: 789),
            relativePath: "Inbox/Notes/Invalid Previous.md"
        )
        let fileURL = service.noteFileURL(for: note)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let originalBytes = Data([0xff, 0xfe, 0xfd])
        try originalBytes.write(to: fileURL)

        let saved = service.save(note: note)

        #expect(saved == false)
        #expect(try Data(contentsOf: fileURL) == originalBytes)
        #expect(service.lastContentIOIssue?.operation == .read)
    }

    @Test("save reports write failures when the note parent cannot be created")
    func saveReportsWriteFailuresWhenParentCannotBeCreated() throws {
        let (service, db, dbURL, vaultURL) = try makeService()
        defer {
            db.close()
            cleanup(dbURL)
            cleanup(vaultURL)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }

        let note = Note(
            title: "Blocked Parent",
            content: "Body",
            relativePath: "Inbox/Notes/Blocked Parent.md"
        )
        let fileURL = service.noteFileURL(for: note)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent().deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not a directory".utf8).write(to: fileURL.deletingLastPathComponent())

        let saved = service.save(note: note)

        #expect(saved == false)
        #expect(service.lastContentIOIssue?.operation == .write)
    }

    @Test("attachment reference scan reports unreadable note paths")
    func attachmentReferenceScanReportsUnreadableNotePaths() throws {
        let directory = makeTempVaultURL()
        defer { cleanup(directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let readable = directory.appendingPathComponent("Readable.md")
        let unreadable = directory.appendingPathComponent("Unreadable.md")
        try "![img](.attachments/kept.png)".write(to: readable, atomically: true, encoding: .utf8)
        try Data([0xff, 0xfe, 0xfd]).write(to: unreadable)

        let scan = NotesStorage.referencedAttachmentScan(fromNotePaths: [readable, unreadable])

        #expect(scan.referencedFilenames == ["kept.png"])
        #expect(scan.unreadableNoteURLs == [unreadable])
    }

    @Test("Note resolvedContentResult distinguishes unreadable files from empty notes")
    func noteResolvedContentResultDistinguishesUnreadableFilesFromEmptyNotes() throws {
        let vaultURL = makeTempVaultURL()
        StoragePaths.vaultOverride = vaultURL
        StoragePaths.invalidateCachedDirectory()
        defer {
            cleanup(vaultURL)
            StoragePaths.vaultOverride = nil
            StoragePaths.invalidateCachedDirectory()
        }

        let note = Note(
            title: "Unreadable Direct",
            content: "",
            relativePath: "Inbox/Notes/Unreadable Direct.md"
        )
        let fileURL = note.absoluteFileURL
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0xff, 0xfe, 0xfd]).write(to: fileURL)

        let result = note.resolvedContentResult

        #expect(result.content == nil)
        #expect(result.issue?.operation == .read)
    }
}
