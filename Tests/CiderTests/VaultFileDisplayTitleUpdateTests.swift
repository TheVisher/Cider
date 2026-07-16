import AppKit
import Foundation
import Testing
@testable import Cider

@Suite("VaultFile Display Title Update Tests", .serialized)
@MainActor
struct VaultFileDisplayTitleUpdateTests {
    @Test("linked Journal vaultFile retitle is metadata-only, projected, durable, and duplicate titles are allowed")
    func linkedJournalRetitlePreservesImmutableTruthAndSurvivesReopen() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let capture = try fixture.capture(titleBase: "Reflection Lake")
        let source = try #require(capture.mediaSources.first)
        let fileID = try #require(UUID(uuidString: source.mediaItem?.id ?? ""))
        let before = try fixture.immutableFingerprint(fileID: fileID)
        let counts = try fixture.canonicalCounts()

        let receipt = try fixture.service().updateVaultFileDisplayTitle(
            ref: .init(type: .vaultFile, entityID: fileID),
            expectedCurrentTitle: "Reflection Lake — Photo 1",
            newTitle: "Narada Falls",
            reason: "Repair filename-like Journal media title.",
            actor: "cid759-test",
            source: "test.cid759"
        )

        #expect(receipt.changed)
        #expect(!receipt.wasReused)
        #expect(receipt.beforeTitle == "Reflection Lake — Photo 1")
        #expect(receipt.afterTitle == "Narada Falls")
        #expect(try fixture.immutableFingerprint(fileID: fileID) == before)
        #expect(try fixture.canonicalCounts() == counts)
        #expect(try fixture.itemTitle(fileID) == "Narada Falls")
        #expect(try fixture.chunkBodies(fileID).contains { $0.contains("Narada Falls") })
        #expect(!fixture.journalContent().contains("Narada Falls"))
        #expect(try fixture.sourceCards().first?.displayTitle == "Narada Falls")
        #expect(try fixture.captureAttachmentDisplayTitle(source.id) == "Reflection Lake — Photo 1")

        let repeated = try fixture.service().updateVaultFileDisplayTitle(
            ref: .init(type: .vaultFile, entityID: fileID),
            expectedCurrentTitle: "Reflection Lake — Photo 1",
            newTitle: "Narada Falls",
            reason: "Repair filename-like Journal media title.",
            actor: "cid759-test",
            source: "test.cid759"
        )
        #expect(repeated.receiptID == receipt.receiptID)
        #expect(repeated.changed)
        #expect(repeated.wasReused)
        #expect(try fixture.actionReceiptCount() == 1)

        let noop = try fixture.service().updateVaultFileDisplayTitle(
            ref: .init(type: .vaultFile, entityID: fileID),
            expectedCurrentTitle: "Narada Falls",
            newTitle: "Narada Falls",
            reason: "Verify canonical title.",
            actor: "cid759-test",
            source: "test.cid759"
        )
        #expect(!noop.changed)
        #expect(!noop.wasReused)

        let second = try fixture.captureSecondFile(title: "Narada Falls")
        #expect(try fixture.itemTitle(second) == "Narada Falls")
        #expect(second != fileID)

        try fixture.reopen()
        _ = try SecondBrainItemContentIndexingService(database: fixture.database).rebuildAll()
        #expect(try fixture.itemTitle(fileID) == "Narada Falls")
        #expect(try fixture.sourceCards().first?.displayTitle == "Narada Falls")
        #expect(try fixture.chunkBodies(fileID).contains { $0.contains("Narada Falls") })
        #expect(try fixture.immutableFingerprint(fileID: fileID) == before)
    }

    @Test("retitle rejects stale, missing, wrong-type, invalid, and rolls back injected failures")
    func retitleFailuresDoNotPartiallyMutate() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let capture = try fixture.capture(titleBase: "Reflection Lake")
        let fileID = try #require(UUID(uuidString: capture.mediaSources[0].mediaItem?.id ?? ""))
        let baseline = try fixture.fullFingerprint()

        for invalid in ["", "  ", "bad\u{0000}title", String(repeating: "z", count: 161)] {
            #expect(throws: CiderVaultFileDisplayTitleUpdateError.self) {
                try fixture.service().updateVaultFileDisplayTitle(
                    ref: .init(type: .vaultFile, entityID: fileID),
                    expectedCurrentTitle: "Reflection Lake — Photo 1",
                    newTitle: invalid,
                    reason: "Repair title.", actor: "test", source: "test"
                )
            }
            #expect(try fixture.fullFingerprint() == baseline)
        }

        #expect(throws: CiderVaultFileDisplayTitleUpdateError.self) {
            try fixture.service().updateVaultFileDisplayTitle(
                ref: .init(type: .vaultFile, entityID: fileID),
                expectedCurrentTitle: "Stale title", newTitle: "Narada Falls",
                reason: "Repair title.", actor: "test", source: "test"
            )
        }
        #expect(throws: CiderVaultFileDisplayTitleUpdateError.self) {
            try fixture.service().updateVaultFileDisplayTitle(
                ref: .init(type: .vaultFile, entityID: UUID()),
                expectedCurrentTitle: "Missing", newTitle: "Narada Falls",
                reason: "Repair title.", actor: "test", source: "test"
            )
        }
        let noteID = try #require(fixture.notes.notes.first?.id)
        #expect(throws: CiderVaultFileDisplayTitleUpdateError.self) {
            try fixture.service().updateVaultFileDisplayTitle(
                ref: .init(type: .vaultFile, entityID: noteID),
                expectedCurrentTitle: "Journal 07-15-2026", newTitle: "Wrong type",
                reason: "Repair title.", actor: "test", source: "test"
            )
        }
        #expect(try fixture.fullFingerprint() == baseline)

        for stage in [
            CiderItemMutationService.Hooks.Stage.beforeTitlePersist,
            .beforeSearchProjection,
            .beforeReceiptPersist,
        ] {
            #expect(throws: CiderVaultFileDisplayTitleUpdateError.self) {
                try fixture.service(hooks: .init(atStage: { current in
                    if current == stage { throw Injected.failure }
                })).updateVaultFileDisplayTitle(
                    ref: .init(type: .vaultFile, entityID: fileID),
                    expectedCurrentTitle: "Reflection Lake — Photo 1", newTitle: "Narada Falls",
                    reason: "Repair title.", actor: "test", source: "test"
                )
            }
            #expect(try fixture.fullFingerprint() == baseline)
        }
    }
}

private extension VaultFileDisplayTitleUpdateTests {
    enum Injected: Error { case failure }

    @MainActor
    final class Fixture {
        let root: URL
        let vault: URL
        let sources: URL
        let databaseURL: URL
        var database: CiderDatabase
        var notes: NotesStorage

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("cider-retitle-\(UUID().uuidString)", isDirectory: true)
            vault = root.appendingPathComponent("vault", isDirectory: true)
            sources = root.appendingPathComponent("sources", isDirectory: true)
            databaseURL = root.appendingPathComponent("cider.sqlite")
            try FileManager.default.createDirectory(at: vault.appendingPathComponent("Inbox/Notes"), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            database = CiderDatabase()
            try database.open(at: databaseURL)
            notes = NotesStorage(database: database, notesDirectoryURL: vault.appendingPathComponent(".cider/notes"), vaultRootURL: vault)
            notes.loadNotesFromDatabase(database)
        }

        func cleanup() { database.close(); try? FileManager.default.removeItem(at: root) }

        func service(hooks: CiderItemMutationService.Hooks = .init()) -> CiderItemMutationService {
            CiderItemMutationService(database: database, hooks: hooks)
        }

        func capture(titleBase: String) throws -> JournalAtomicCaptureReceipt {
            let url = sources.appendingPathComponent("IMG_8741.jpeg")
            try Self.jpegData.write(to: url)
            return try JournalAtomicCaptureWriter(database: database, notesStorage: notes, vaultRoot: vault).capture(.init(
                journalDate: "2026-07-15", time: "11:42", text: "Reflection Lake was glassy.", source: "test",
                capturedAt: Date(timeIntervalSince1970: 1_768_501_320), idempotencyKey: "retitle-fixture-1",
                sourceContext: nil,
                media: [.init(sourceURL: url, sourceID: "fixture-photo-1", kind: .photo, mimeType: "image/jpeg")],
                mediaTitleBase: titleBase
            ))
        }

        func captureSecondFile(title: String) throws -> UUID {
            let url = sources.appendingPathComponent("IMG_8742.jpeg")
            try Self.jpegData.write(to: url)
            let receipt = try JournalAtomicCaptureWriter(database: database, notesStorage: notes, vaultRoot: vault).capture(.init(
                journalDate: "2026-07-15", time: "11:43", text: "A second view.", source: "test",
                capturedAt: Date(timeIntervalSince1970: 1_768_501_380), idempotencyKey: "retitle-fixture-2", sourceContext: nil,
                media: [.init(sourceURL: url, sourceID: "fixture-photo-2", kind: .photo, displayTitle: title, mimeType: "image/jpeg")]
            ))
            return try #require(UUID(uuidString: receipt.mediaSources[0].mediaItem?.id ?? ""))
        }

        func reopen() throws {
            database.close()
            database = CiderDatabase()
            try database.open(at: databaseURL)
            notes = NotesStorage(database: database, notesDirectoryURL: vault.appendingPathComponent(".cider/notes"), vaultRootURL: vault)
            notes.loadNotesFromDatabase(database)
        }

        func itemTitle(_ id: UUID) throws -> String {
            let stmt = try database.prepare("SELECT title FROM items WHERE id = ?;")
            stmt.bind(id.uuidString, at: 1); try #require(try stmt.step()); return stmt.string(at: 0)
        }

        func sourceCards() throws -> [JournalMediaSourceCard] {
            try JournalMediaSourceCardReadService(database: database, vaultRoot: vault).sourceCards(noteIDs: Set(notes.notes.map(\.id)))
        }

        func journalContent() -> String { notes.notes.first.map(notes.loadContent(for:)) ?? "" }

        func captureAttachmentDisplayTitle(_ id: String) throws -> String? {
            let stmt = try database.prepare("SELECT metadata FROM capture_attachments WHERE id = ?;")
            stmt.bind(id, at: 1); try #require(try stmt.step())
            return DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 0))?["display_title"]
        }

        func chunkBodies(_ id: UUID) throws -> [String] {
            let stmt = try database.prepare("SELECT body FROM content_chunks WHERE owner_type = 'vaultFile' AND owner_id = ? ORDER BY chunk_index;")
            stmt.bind(id.uuidString, at: 1); var rows: [String] = []; while try stmt.step() { rows.append(stmt.string(at: 0)) }; return rows
        }

        func actionReceiptCount() throws -> Int { try count("action_receipts") }

        func canonicalCounts() throws -> String {
            try ["items", "notes", "vault_files", "capture_events", "capture_attachments", "owner_relations", "item_links"].map { "\($0)=\(try count($0))" }.joined(separator: "|")
        }

        func count(_ table: String) throws -> Int {
            let stmt = try database.prepare("SELECT COUNT(*) FROM \(table);"); try #require(try stmt.step()); return stmt.int(at: 0)
        }

        func immutableFingerprint(fileID: UUID) throws -> String {
            let stmt = try database.prepare("SELECT i.relative_path, i.created_at, i.updated_at, vf.filename, vf.file_type, vf.file_size FROM items i JOIN vault_files vf ON vf.item_id = i.id WHERE i.id = ?;")
            stmt.bind(fileID.uuidString, at: 1); try #require(try stmt.step())
            let path = stmt.string(at: 0)
            let values = (0..<6).map { stmt.optionalString(at: Int32($0)) ?? String(stmt.optionalDouble(at: Int32($0)) ?? -1) }
            let bytes = try Data(contentsOf: vault.appendingPathComponent(path))
            let provenance = try database.prepare("SELECT source_attachment_id, filename, local_path, byte_size, metadata FROM capture_attachments WHERE json_extract(metadata, '$.vault_file_id') = ?;")
            provenance.bind(fileID.uuidString, at: 1); try #require(try provenance.step())
            return LocalFileIntakeValidator.sha256(Data((values + [LocalFileIntakeValidator.sha256(bytes), provenance.string(at: 0), provenance.string(at: 1), provenance.string(at: 2), String(provenance.int(at: 3)), provenance.string(at: 4)]).joined(separator: "|").utf8))
        }

        func fullFingerprint() throws -> String {
            let tables = ["items", "vault_files", "capture_events", "capture_attachments", "owner_relations", "content_chunks", "action_receipts"]
            var rows: [String] = []
            for table in tables {
                let columnsStatement = try database.prepare("PRAGMA table_info(\(table));")
                var columns: [String] = []
                while try columnsStatement.step() { columns.append(columnsStatement.string(at: 1)) }
                let expression = columns.map { "quote(\($0))" }.joined(separator: " || char(31) || ")
                let stmt = try database.prepare("SELECT \(expression) FROM \(table);")
                var values: [String] = []
                while try stmt.step() { values.append(stmt.string(at: 0)) }
                rows.append("\(table):\(values.sorted())")
            }
            let files = try FileManager.default.subpathsOfDirectory(atPath: vault.path).sorted().compactMap { path -> String? in
                let url = vault.appendingPathComponent(path); var directory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), !directory.boolValue else { return nil }
                return "\(path):\(LocalFileIntakeValidator.sha256(try Data(contentsOf: url)))"
            }
            return LocalFileIntakeValidator.sha256(Data((rows + files).joined(separator: "|").utf8))
        }

        static let jpegData: Data = {
            let image = NSImage(size: NSSize(width: 2, height: 2)); image.lockFocus(); NSColor.systemBlue.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill(); image.unlockFocus()
            return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
        }()
    }
}
