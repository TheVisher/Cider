import AppKit
import Foundation
import Testing
@testable import Cider

@Suite("Journal Atomic Capture Writer Tests")
@MainActor
struct JournalAtomicCaptureWriterTests {
    @Test("Reflection Lake text and three JPEGs commit as one day with distinct source cards")
    func reflectionLakeCaptureIsAtomicAndFriendly() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let media = try fixture.reflectionLakeMedia()
        let request = fixture.request(media: media)

        let receipt = try fixture.writer().capture(request)

        #expect(receipt.item.title == "Journal 07-15-2026")
        #expect(receipt.textSource.kind == "text")
        #expect(receipt.mediaSources.count == 3)
        #expect(Set(receipt.mediaSources.map(\.id)).count == 3)
        #expect(receipt.mediaSources.map(\.displayTitle) == [
            "Reflection Lake overlook",
            "Reflection Lake trail",
            "Reflection Lake shoreline",
        ])
        #expect(receipt.mediaSources.map(\.rawFilename) == ["IMG_8741.jpeg", "IMG_8742.jpeg", "IMG_8743.jpeg"])
        #expect(receipt.mediaSources.map(\.mediaItem?.title) == receipt.mediaSources.map(\.displayTitle))
        #expect(receipt.mediaSources.allSatisfy { $0.mediaItem?.relativePath?.hasPrefix("Journal/Photos/") == true })
        #expect(try fixture.count("items", where: "type = 'note'") == 1)
        #expect(try fixture.count("items", where: "type = 'vaultFile'") == 3)
        #expect(try fixture.count("capture_events") == 1)
        #expect(try fixture.count("capture_attachments") == 3)
        #expect(try fixture.count("owner_relations", where: "relation_type = 'journal_source_for'") == 3)
        #expect(try fixture.count("content_chunks", where: "owner_type = 'note'") == 1)
        #expect(fixture.notes.notes.count == 1)
        let content = fixture.notes.loadContent(for: try #require(fixture.notes.notes.first))
        #expect(content.contains(request.text))
        #expect(content.components(separatedBy: request.text).count == 2)
        #expect(!content.contains("IMG_8741"))

        for (source, input) in zip(receipt.mediaSources, media) {
            let relativePath = try #require(source.mediaItem?.relativePath)
            #expect(try Data(contentsOf: fixture.vault.appendingPathComponent(relativePath)) == Data(contentsOf: input.sourceURL))
        }
    }

    @Test("friendly title base numbers photos and explicit media title wins")
    func friendlyTitleBaseNumbersPhotosWithOverride() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let media = try fixture.reflectionLakeMedia().enumerated().map { index, source in
            JournalAtomicMediaSource(
                sourceURL: source.sourceURL,
                sourceID: source.sourceID,
                kind: source.kind,
                displayTitle: index == 1 ? "Reflection Lake favorite" : nil,
                mimeType: source.mimeType
            )
        }

        let receipt = try fixture.writer().capture(
            fixture.request(media: media, mediaTitleBase: "Reflection Lake")
        )

        #expect(receipt.mediaSources.map(\.displayTitle) == [
            "Reflection Lake — Photo 1",
            "Reflection Lake favorite",
            "Reflection Lake — Photo 3",
        ])
        #expect(receipt.mediaSources.map(\.rawFilename) == ["IMG_8741.jpeg", "IMG_8742.jpeg", "IMG_8743.jpeg"])
        #expect(try fixture.itemTitles(type: "vaultFile") == [
            "Reflection Lake favorite",
            "Reflection Lake — Photo 1",
            "Reflection Lake — Photo 3",
        ])
    }

    @Test("invalid title bases fail before mutation and changed base conflicts without mutation")
    func invalidAndChangedTitleBaseFailClosed() throws {
        for invalid in ["   ", "Reflection\u{0007}Lake", String(repeating: "x", count: 121)] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let before = try fixture.fingerprint()
            #expect(throws: JournalAtomicCaptureError.self) {
                try fixture.writer().capture(
                    fixture.request(media: try fixture.reflectionLakeMedia(), mediaTitleBase: invalid)
                )
            }
            #expect(try fixture.fingerprint() == before)
        }

        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let media = try fixture.reflectionLakeMedia().map {
            JournalAtomicMediaSource(
                sourceURL: $0.sourceURL,
                sourceID: $0.sourceID,
                kind: $0.kind,
                mimeType: $0.mimeType
            )
        }
        let firstRequest = fixture.request(media: media, mediaTitleBase: "Reflection Lake")
        let first = try fixture.writer().capture(firstRequest)
        let retry = try fixture.writer().capture(firstRequest)
        #expect(retry.receiptID == first.receiptID)
        #expect(retry.wasReused)
        let beforeConflict = try fixture.fingerprint()

        do {
            _ = try fixture.writer().capture(fixture.request(media: media, mediaTitleBase: "Narada Falls"))
            Issue.record("Expected title-base retry conflict")
        } catch let error as JournalAtomicCaptureError {
            #expect(error.code == .idempotencyConflict)
        }
        #expect(try fixture.fingerprint() == beforeConflict)
    }

    @Test("exact retry and database reopen reuse one durable receipt without duplicates")
    func retryAndReopenReuseReceipt() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let request = fixture.request(media: try fixture.reflectionLakeMedia())
        let first = try fixture.writer().capture(request)
        let retry = try fixture.writer().capture(request)

        #expect(retry.receiptID == first.receiptID)
        #expect(retry.item == first.item)
        #expect(retry.textSource == first.textSource)
        #expect(retry.mediaSources == first.mediaSources)
        #expect(retry.wasReused)
        #expect(try fixture.count("items", where: "type = 'vaultFile'") == 3)
        #expect(try fixture.count("capture_attachments") == 3)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedNotes = NotesStorage(
            database: reopened,
            notesDirectoryURL: fixture.notesDirectory,
            vaultRootURL: fixture.vault
        )
        reopenedNotes.loadNotesFromDatabase(reopened)
        let reopenedReceipt = try JournalAtomicCaptureWriter(
            database: reopened,
            notesStorage: reopenedNotes,
            vaultRoot: fixture.vault
        ).capture(request)

        #expect(reopenedReceipt.receiptID == first.receiptID)
        #expect(reopenedReceipt.mediaSources == first.mediaSources)
        #expect(reopenedReceipt.wasReused)
    }

    @Test("multi-file source-card and projection failures compensate every partial effect")
    func partialFailureCompensatesAllEffects() throws {
        for stage in [
            JournalAtomicCaptureWriter.Hooks.Stage.afterSourceCards,
            .beforeSearchProjection,
        ] {
            let fixture = try Fixture()
            defer { fixture.cleanup() }
            let request = fixture.request(media: try fixture.reflectionLakeMedia())
            let before = try fixture.fingerprint()
            let writer = fixture.writer(hooks: .init(atStage: { current in
                if current == stage { throw Injected.failure }
            }))

            do {
                _ = try writer.capture(request)
                Issue.record("Expected injected failure at \(stage)")
            } catch let error as JournalAtomicCaptureError {
                #expect(error.code == .notCommitted)
            }

            #expect(try fixture.fingerprint() == before)
            #expect(fixture.notes.notes.isEmpty)
        }
    }

    @Test("one invalid JPEG prevents all source materialization and day creation")
    func invalidSecondMediaPreventsPartialCommit() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        var media = try fixture.reflectionLakeMedia()
        let corrupt = fixture.sources.appendingPathComponent("broken.jpeg")
        try Data("not jpeg".utf8).write(to: corrupt)
        media[1] = .init(
            sourceURL: corrupt,
            sourceID: "discord:1527021398508310640:photo:2",
            kind: .photo,
            displayTitle: "Reflection Lake trail",
            mimeType: "image/jpeg"
        )
        let before = try fixture.fingerprint()

        #expect(throws: JournalAtomicCaptureError.self) {
            try fixture.writer().capture(fixture.request(media: media))
        }
        #expect(try fixture.fingerprint() == before)
        #expect(fixture.notes.notes.isEmpty)
    }

    @Test("second media database failure compensates the first prepared original")
    func secondMediaPersistenceFailureRollsBackBatch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let request = fixture.request(media: try fixture.reflectionLakeMedia())
        let before = try fixture.fingerprint()
        let validator = LocalFileIntakeValidator()
        var persistCount = 0
        let ingestion = VaultFileIngestionService(
            database: fixture.database,
            vaultRoot: fixture.vault,
            storage: VaultFileStorage(database: fixture.database),
            validator: validator,
            hooks: .init(beforeDatabasePersist: { _ in
                persistCount += 1
                if persistCount == 2 { throw Injected.failure }
            })
        )
        let mediaIntake = JournalMediaIntakeService(
            database: fixture.database,
            vaultRoot: fixture.vault,
            validator: validator,
            ingestionService: ingestion
        )

        #expect(throws: JournalAtomicCaptureError.self) {
            try fixture.writer(mediaIntake: mediaIntake).capture(request)
        }
        #expect(try fixture.fingerprint() == before)
        #expect(fixture.notes.notes.isEmpty)
    }

    @Test("same idempotency key with changed text fails closed")
    func idempotencyConflictFailsClosed() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let request = fixture.request(media: try fixture.reflectionLakeMedia())
        _ = try fixture.writer().capture(request)
        let before = try fixture.fingerprint()
        let changed = JournalAtomicCaptureRequest(
            journalDate: request.journalDate,
            time: request.time,
            text: request.text + " Changed.",
            source: request.source,
            capturedAt: request.capturedAt,
            idempotencyKey: request.idempotencyKey,
            sourceContext: request.sourceContext,
            media: request.media
        )

        do {
            _ = try fixture.writer().capture(changed)
            Issue.record("Expected idempotency conflict")
        } catch let error as JournalAtomicCaptureError {
            #expect(error.code == .idempotencyConflict)
        }
        #expect(try fixture.fingerprint() == before)
    }

    @Test("same idempotency key with changed media bytes fails closed after database reopen")
    func changedMediaContentConflictsAfterReopenWithoutMutation() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let request = fixture.request(media: try fixture.reflectionLakeMedia())
        let first = try fixture.writer().capture(request)

        fixture.database.close()
        let reopened = CiderDatabase()
        try reopened.open(at: fixture.databaseURL)
        defer { reopened.close() }
        let reopenedNotes = NotesStorage(
            database: reopened,
            notesDirectoryURL: fixture.notesDirectory,
            vaultRootURL: fixture.vault
        )
        reopenedNotes.loadNotesFromDatabase(reopened)
        let before = try fixture.fingerprint(database: reopened)
        let durableDigestBefore = try fixture.journalRequestDigest(database: reopened, receiptID: first.receiptID)
        try Fixture.changedJPEGData.write(to: request.media[1].sourceURL, options: .atomic)

        do {
            _ = try JournalAtomicCaptureWriter(
                database: reopened,
                notesStorage: reopenedNotes,
                vaultRoot: fixture.vault
            ).capture(request)
            Issue.record("Expected changed media content to conflict with the durable receipt")
        } catch let error as JournalAtomicCaptureError {
            #expect(error.code == .idempotencyConflict)
            #expect(!error.reason.contains(request.media[1].sourceURL.path))
            #expect(!error.reason.localizedCaseInsensitiveContains("sha256"))
        }

        #expect(try fixture.fingerprint(database: reopened) == before)
        #expect(try fixture.journalRequestDigest(database: reopened, receiptID: first.receiptID) == durableDigestBefore)
    }

    @Test("Journal read model surfaces source cards and missing originals degrade without losing identity")
    func readModelSurfacesMediaAndMissingState() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let request = fixture.request(media: try fixture.reflectionLakeMedia())
        let receipt = try fixture.writer().capture(request)
        let note = try #require(fixture.notes.notes.first)
        let service = JournalMediaSourceCardReadService(
            database: fixture.database,
            vaultRoot: fixture.vault
        )
        let sources = try service.sourceCards(noteIDs: [note.id])
        let day = try #require(JournalLibraryReadModel.build(from: [note], mediaSources: sources).defaultDay)
        let card = try #require(day.captureCards.first)

        #expect(card.mediaSources.count == 3)
        #expect(card.mediaSources.map(\.displayTitle) == receipt.mediaSources.map(\.displayTitle))
        #expect(card.mediaSources.allSatisfy { $0.isOriginalAvailable })
        #expect(card.mediaSources.allSatisfy { $0.canonicalItemRef.type == .vaultFile })

        let missing = try #require(receipt.mediaSources[1].mediaItem?.relativePath)
        try FileManager.default.removeItem(at: fixture.vault.appendingPathComponent(missing))
        let reloaded = try service.sourceCards(noteIDs: [note.id])
        let missingSource = try #require(reloaded.first { $0.id == receipt.mediaSources[1].id })
        #expect(!missingSource.isOriginalAvailable)
        #expect(missingSource.availabilityLabel.contains("Original unavailable"))
        #expect(missingSource.displayTitle == "Reflection Lake trail")
        #expect(missingSource.rawFilename == "IMG_8742.jpeg")
        do {
            _ = try fixture.writer().capture(request)
            Issue.record("A retry must not claim success for a missing immutable original")
        } catch let error as JournalAtomicCaptureError {
            #expect(error.code == .indeterminate)
        }
    }

    @Test("existing user-owned Journal bytes remain an exact prefix")
    func existingJournalTextIsNotRewritten() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let exact = "# Journal 07-15-2026\n\n## 07:05\nSource: voice\n\n  Keep my spacing.  \n\n"
        let untitled = fixture.notes.createNew(initialContent: exact)
        fixture.notes.rename(note: untitled, to: "Journal 07-15-2026")
        let existing = try #require(fixture.notes.notes.first { $0.id == untitled.id })
        #expect(fixture.notes.loadContent(for: existing) == exact)

        _ = try fixture.writer().capture(fixture.request(media: try fixture.reflectionLakeMedia()))
        let stored = try #require(fixture.notes.notes.first { $0.id == untitled.id })
        let after = fixture.notes.loadContent(for: stored)
        #expect(after.hasPrefix(exact))
        #expect(after.contains("  Keep my spacing.  "))
    }
}

private extension JournalAtomicCaptureWriterTests {
    enum Injected: Error { case failure }

    @MainActor
    final class Fixture {
        let root: URL
        let vault: URL
        let sources: URL
        let notesDirectory: URL
        let databaseURL: URL
        let database: CiderDatabase
        let notes: NotesStorage

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent("cider-journal-atomic-\(UUID().uuidString)", isDirectory: true)
            vault = root.appendingPathComponent("vault", isDirectory: true)
            sources = root.appendingPathComponent("sources", isDirectory: true)
            notesDirectory = vault.appendingPathComponent(".cider/notes", isDirectory: true)
            databaseURL = root.appendingPathComponent("cider.sqlite")
            try FileManager.default.createDirectory(at: vault.appendingPathComponent("Inbox/Notes"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: notesDirectory, withIntermediateDirectories: true)
            database = CiderDatabase()
            try database.open(at: databaseURL)
            notes = NotesStorage(database: database, notesDirectoryURL: notesDirectory, vaultRootURL: vault)
            notes.loadNotesFromDatabase(database)
        }

        func cleanup() {
            database.close()
            try? FileManager.default.removeItem(at: root)
        }

        func writer(
            mediaIntake: JournalMediaIntakeService? = nil,
            hooks: JournalAtomicCaptureWriter.Hooks = .init()
        ) -> JournalAtomicCaptureWriter {
            JournalAtomicCaptureWriter(
                database: database,
                notesStorage: notes,
                vaultRoot: vault,
                mediaIntake: mediaIntake,
                hooks: hooks
            )
        }

        func request(
            media: [JournalAtomicMediaSource],
            mediaTitleBase: String? = nil
        ) -> JournalAtomicCaptureRequest {
            JournalAtomicCaptureRequest(
                journalDate: "2026-07-15",
                time: "11:42",
                text: "Reflection Lake was glassy this morning. The trail was quiet and the shoreline still had snow.",
                source: "discord",
                capturedAt: Date(timeIntervalSince1970: 1_768_501_320),
                idempotencyKey: "discord:message:1527021398508310640",
                sourceContext: CaptureSourceContext(
                    surface: "hermes",
                    channel: "discord",
                    channelID: "reflection-lake",
                    messageID: "1527021398508310640",
                    senderID: "visher",
                    originalText: "Reflection Lake was glassy this morning. The trail was quiet and the shoreline still had snow."
                ),
                media: media,
                mediaTitleBase: mediaTitleBase
            )
        }

        func reflectionLakeMedia() throws -> [JournalAtomicMediaSource] {
            let titles = ["Reflection Lake overlook", "Reflection Lake trail", "Reflection Lake shoreline"]
            return try titles.enumerated().map { index, title in
                let url = sources.appendingPathComponent("IMG_874\(index + 1).jpeg")
                try Self.jpegData.write(to: url)
                return JournalAtomicMediaSource(
                    sourceURL: url,
                    sourceID: "discord:1527021398508310640:photo:\(index + 1)",
                    kind: .photo,
                    displayTitle: title,
                    mimeType: "image/jpeg"
                )
            }
        }

        func count(_ table: String, where predicate: String? = nil) throws -> Int {
            let sql = "SELECT COUNT(*) FROM \(table)\(predicate.map { " WHERE \($0)" } ?? "");"
            let statement = try database.prepare(sql)
            try statement.step()
            return statement.int(at: 0)
        }

        func itemTitles(type: String) throws -> [String] {
            let statement = try database.prepare("SELECT title FROM items WHERE type = ? ORDER BY title COLLATE NOCASE ASC;")
            statement.bind(type, at: 1)
            var titles: [String] = []
            while try statement.step() { titles.append(statement.string(at: 0)) }
            return titles
        }

        func fingerprint(database: CiderDatabase? = nil) throws -> String {
            let database = database ?? self.database
            let tables = ["items", "notes", "vault_files", "capture_events", "capture_attachments", "owner_relations", "content_chunks"]
            let counts = try tables.map { table -> String in
                let statement = try database.prepare("SELECT COUNT(*) FROM \(table);")
                try statement.step()
                return "\(table)=\(statement.int(at: 0))"
            }.joined(separator: "|")
            let rows = try logicalDatabaseFingerprint(database)
            let files = try FileManager.default.subpathsOfDirectory(atPath: vault.path).sorted().map { path -> String in
                let url = vault.appendingPathComponent(path)
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                    return "\(path):\(LocalFileIntakeValidator.sha256(try Data(contentsOf: url)))"
                }
                return "\(path)/"
            }.joined(separator: "|")
            return counts + "||" + rows + "||" + files
        }

        func journalRequestDigest(database: CiderDatabase, receiptID: String) throws -> String {
            let statement = try database.prepare("SELECT metadata FROM capture_events WHERE id = ? LIMIT 1;")
            statement.bind(receiptID, at: 1)
            guard try statement.step() else { throw CocoaError(.fileReadUnknown) }
            let metadata = DatabaseHelpers.decodeJSON(
                [String: String].self,
                from: statement.optionalString(at: 0)
            ) ?? [:]
            return try #require(metadata["journal_request_digest"])
        }

        private func logicalDatabaseFingerprint(_ database: CiderDatabase) throws -> String {
            let tables = try database.prepare("""
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name ASC;
                """)
            var tableNames: [String] = []
            while try tables.step() { tableNames.append(tables.string(at: 0)) }
            var rows: [String] = []
            for table in tableNames {
                let quotedTable = Self.quotedIdentifier(table)
                let columnsStatement = try database.prepare("PRAGMA table_info(\(quotedTable));")
                var columns: [String] = []
                while try columnsStatement.step() { columns.append(columnsStatement.string(at: 1)) }
                guard !columns.isEmpty else { continue }
                let expression = columns
                    .map { "quote(\(Self.quotedIdentifier($0)))" }
                    .joined(separator: " || char(31) || ")
                let rowStatement = try database.prepare("SELECT \(expression) FROM \(quotedTable);")
                var tableRows: [String] = []
                while try rowStatement.step() { tableRows.append(rowStatement.string(at: 0)) }
                rows.append("\(table):\(tableRows.sorted().joined(separator: "\u{1e}"))")
            }
            return LocalFileIntakeValidator.sha256(Data(rows.joined(separator: "\u{1d}").utf8))
        }

        private static func quotedIdentifier(_ value: String) -> String {
            "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        static let jpegData: Data = {
            let image = NSImage(size: NSSize(width: 2, height: 2))
            image.lockFocus()
            NSColor.systemBlue.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
            image.unlockFocus()
            let tiff = image.tiffRepresentation!
            let bitmap = NSBitmapImageRep(data: tiff)!
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        }()

        static let changedJPEGData: Data = {
            let image = NSImage(size: NSSize(width: 2, height: 2))
            image.lockFocus()
            NSColor.systemRed.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
            image.unlockFocus()
            return NSBitmapImageRep(data: image.tiffRepresentation!)!
                .representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        }()
    }
}
