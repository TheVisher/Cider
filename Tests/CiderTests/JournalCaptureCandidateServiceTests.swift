import AppKit
import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Journal Capture Candidate Service Tests")
@MainActor
struct JournalCaptureCandidateServiceTests {
    @Test("atomic capture yields exact reviewable URL place person and project candidates once")
    func captureScopedCandidatesAreExactReviewableAndIdempotent() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try fixture.seedCanonicalReferences()
        let request = try fixture.requestWithPhoto()
        let firstReceipt = try fixture.writer().capture(request)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: firstReceipt.item.id)
        let markdownURL = fixture.vault.appendingPathComponent(try #require(firstReceipt.item.relativePath))
        let markdownAfterCapture = try Data(contentsOf: markdownURL)
        let relationsBefore = try fixture.count("owner_relations")

        let first = try JournalCaptureCandidateService(database: fixture.database).generate(
            captureEventID: firstReceipt.receiptID,
            journalOwner: noteOwner
        )

        #expect(first.status == .suggested)
        #expect(first.outputs.count == 4)
        #expect(!first.wasReused)
        #expect(!first.wasBounded)
        #expect(first.discardedCount == 0)
        #expect(Set(first.outputs.map(\.id)).count == 4)
        #expect(first.textSourceRef == firstReceipt.textSource.canonicalRef)
        #expect(try Data(contentsOf: markdownURL) == markdownAfterCapture)
        #expect(try fixture.count("owner_relations") == relationsBefore)
        #expect(try fixture.count("projects") == 1)
        #expect(try fixture.count("items", where: "type = 'contact'") == 2)

        var outputByType: [SecondBrainGraphCandidateContract.ObjectType: SecondBrainEnrichmentOutput] = [:]
        for output in first.outputs {
            let candidate = try SecondBrainGraphCandidateContract.validate(output)
            for type in candidate.objectTypeGuesses {
                outputByType[type] = output
            }
            let start = try #require(Int(output.metadata["source_span_start"] ?? ""))
            let end = try #require(Int(output.metadata["source_span_end"] ?? ""))
            let exact = (request.text as NSString).substring(with: NSRange(location: start, length: end - start))
            #expect(exact == output.evidence)
            #expect(output.metadata["capture_event_id"] == firstReceipt.receiptID)
            #expect(output.metadata["capture_event_ref"] == firstReceipt.captureEventRef)
            #expect(output.metadata["journal_source_ref"] == firstReceipt.textSource.canonicalRef)
            #expect(output.metadata["journal_note_ref"] == noteOwner.canonicalRef)
            #expect(output.metadata["journal_date"] == request.journalDate)
            #expect(output.metadata["journal_time"] == request.time)
            #expect(output.metadata["source_coordinate_space"] == "capture_event.source_text")
            #expect(output.metadata["truth_boundary"] == "reviewable_candidate_not_truth")

            let evidence = try #require(
                try SecondBrainSourceEvidenceService(database: fixture.database).record(
                    derivedOwner: SecondBrainOwnerRef(ownerType: "enrichment_output", ownerID: output.id)
                )
            )
            #expect(evidence.sourceOwnerRef == firstReceipt.captureEventRef)
            #expect(evidence.sourceQuote == output.evidence)
            #expect(evidence.spanStart == start)
            #expect(evidence.spanEnd == end)
            #expect(evidence.candidateRef == "graph_candidate:\(output.id)")
        }
        #expect(outputByType[.url]?.value == "https://example.com/cider-review")
        #expect(outputByType[.place]?.value == "Pike Place Market")
        #expect(outputByType[.person]?.value == "Alex Rivera")
        #expect(outputByType[.project]?.value == "Project Atlas")
        #expect(first.outputs.allSatisfy { !$0.value.contains("user:secret") && !$0.evidence.contains("user:secret") })
        #expect(first.outputs.allSatisfy { !$0.value.contains("https://.") })

        let note = try #require(fixture.notes.notes.first { $0.id.uuidString == firstReceipt.item.id })
        let media = try JournalMediaSourceCardReadService(database: fixture.database, vaultRoot: fixture.vault)
            .sourceCards(noteIDs: [note.id])
        let card = try #require(JournalLibraryReadModel.build(from: [note], mediaSources: media).defaultDay?.captureCards.first)
        #expect(card.mediaSources.count == 1)
        #expect(card.mediaSources.first?.kind == .photo)
        #expect(card.mediaSources.first?.isOriginalAvailable == true)
        let links = card.links(resolveCanonicalItem: { _, _ in nil })
        #expect(links.count == 1)
        #expect(links.first?.destination.absoluteString == "https://example.com/cider-review")

        let intelligence = try JournalIntelligenceDailyReceiptService(database: fixture.database)
            .receipt(date: request.journalDate)
        let proposals = intelligence.groups.flatMap(\.proposals)
        #expect(proposals.count == 4)
        #expect(Set(proposals.map(\.category)) == [.artifactsMedia, .places, .people, .durableMemory])
        #expect(proposals.allSatisfy { $0.captureEvent.id == firstReceipt.receiptID })
        #expect(proposals.allSatisfy { $0.source.coordinateSpace == "capture_event.source_text" })
        let person = try #require(proposals.first { $0.candidateType == "person" })
        #expect(person.crossTimeReconciliation?.status == .ambiguous)
        #expect(person.crossTimeReconciliation?.classification == nil)
        #expect(person.crossTimeReconciliation?.likelyMatches.count == 2)
        let project = try #require(proposals.first { $0.candidateType == "project" })
        #expect(project.crossTimeReconciliation?.status == .matched)
        #expect(project.crossTimeReconciliation?.likelyMatches.map(\.canonicalRef) == ["project:project-atlas"])

        let cliCandidates = CiderCLI.recordJournalGraphCandidates(
            captureEventID: firstReceipt.receiptID,
            journalOwner: noteOwner,
            database: fixture.database
        )
        #expect(cliCandidates["status"] as? String == "suggested")
        #expect(cliCandidates["count"] as? Int == 4)
        #expect(cliCandidates["wasReused"] as? Bool == true)
        #expect(cliCandidates["journalSourceRef"] as? String == firstReceipt.textSource.canonicalRef)
        #expect((cliCandidates["safeNextCommands"] as? [String])?.contains {
            $0.contains("capture review-queue --kind graph_candidate")
        } == true)

        let personID = try #require(outputByType[.person]?.id)
        let storedPerson = try #require(
            try SecondBrainEnrichmentOutputService(database: fixture.database).output(id: personID)
        )
        let unauthorized = CiderReviewActionCoordinator(database: fixture.database).perform(.init(
            identity: .init(candidateRef: "graph_candidate:\(storedPerson.id)", family: .graphCandidate),
            expectedVersion: .init(reviewState: storedPerson.reviewState, updatedAt: storedPerson.updatedAt),
            action: .approve,
            actor: "cid-759-test",
            surface: .journal,
            exactEvidenceRequirement: .required,
            mutationAuthority: .inferredProposal
        ))
        #expect(unauthorized.error?.classification == .reviewApprovalRequired)
        #expect(!unauthorized.changed)
        #expect(try fixture.count("action_receipts") == 0)
        #expect(try fixture.count("owner_relations") == relationsBefore)

        let countsBeforeRetry = try fixture.candidateCounts()
        #expect(countsBeforeRetry == CandidateCounts(outputs: 4, evidence: 4, lifecycle: 4))
        let retryReceipt = try fixture.writer().capture(request)
        let retry = try JournalCaptureCandidateService(database: fixture.database).generate(
            captureEventID: retryReceipt.receiptID,
            journalOwner: noteOwner
        )
        #expect(retryReceipt.wasReused)
        #expect(retry.wasReused)
        #expect(retry.outputs.map(\.id) == first.outputs.map(\.id))
        #expect(try fixture.candidateCounts() == countsBeforeRetry)
        #expect(try Data(contentsOf: markdownURL) == markdownAfterCapture)

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
        let reopenedCandidates = try JournalCaptureCandidateService(database: reopened).generate(
            captureEventID: reopenedReceipt.receiptID,
            journalOwner: noteOwner
        )
        #expect(reopenedReceipt.wasReused)
        #expect(reopenedCandidates.wasReused)
        #expect(reopenedCandidates.outputs.map(\.id) == first.outputs.map(\.id))
        #expect(try fixture.candidateCounts(database: reopened) == countsBeforeRetry)
        #expect(try Data(contentsOf: markdownURL) == markdownAfterCapture)
    }

    @Test("candidate persistence failure rolls back enrichment but preserves committed Journal source")
    func enrichmentFailureIsTruthfulAndRecoverable() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let request = try fixture.requestWithPhoto()
        let receipt = try fixture.writer().capture(request)
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: receipt.item.id)
        let markdownURL = fixture.vault.appendingPathComponent(try #require(receipt.item.relativePath))
        let committedMarkdown = try Data(contentsOf: markdownURL)
        let partialPayload = CiderCLI.journalAtomicCapturePayload(
            receipt,
            sourceContext: request.sourceContext,
            graphCandidates: ["status": "failed", "count": 0]
        )
        #expect(partialPayload["ok"] as? Bool == true)
        #expect((partialPayload["partialSuccess"] as? [String: Any])?["sourceCaptureCommitted"] as? Bool == true)
        #expect((partialPayload["partialSuccess"] as? [String: Any])?["enrichmentClaimed"] as? Bool == false)
        var records = 0
        let service = JournalCaptureCandidateService(
            database: fixture.database,
            hooks: .init(beforeRecord: { _ in
                records += 1
                if records == 2 { throw Injected.failure }
            })
        )

        do {
            _ = try service.generate(captureEventID: receipt.receiptID, journalOwner: noteOwner)
            Issue.record("Expected candidate persistence failure")
        } catch let error as JournalCaptureCandidateError {
            #expect(error.code == .persistenceFailed)
            #expect(!error.localizedDescription.contains(fixture.root.path))
            #expect(!error.localizedDescription.localizedCaseInsensitiveContains("user:secret"))
        }

        #expect(try fixture.count("capture_events") == 1)
        #expect(try fixture.count("capture_attachments") == 1)
        #expect(try fixture.candidateCounts() == .zero)
        #expect(try Data(contentsOf: markdownURL) == committedMarkdown)
        let recovered = try JournalCaptureCandidateService(database: fixture.database).generate(
            captureEventID: receipt.receiptID,
            journalOwner: noteOwner
        )
        #expect(recovered.outputs.count == 4)
        #expect(!recovered.wasReused)
        #expect(try Data(contentsOf: markdownURL) == committedMarkdown)
    }
}

private extension JournalCaptureCandidateServiceTests {
    enum Injected: Error { case failure }

    struct CandidateCounts: Equatable {
        var outputs: Int
        var evidence: Int
        var lifecycle: Int

        static let zero = CandidateCounts(outputs: 0, evidence: 0, lifecycle: 0)
    }

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
                .appendingPathComponent("cider-journal-candidates-\(UUID().uuidString)", isDirectory: true)
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

        func writer() -> JournalAtomicCaptureWriter {
            JournalAtomicCaptureWriter(database: database, notesStorage: notes, vaultRoot: vault)
        }

        func requestWithPhoto() throws -> JournalAtomicCaptureRequest {
            let photoURL = sources.appendingPathComponent("CID-759.jpeg")
            try Self.jpegData().write(to: photoURL)
            let text = """
            Reference [review notes](https://example.com/cider-review). I visited Pike Place Market. I met with Alex Rivera about launch. I worked on Project Atlas. Ignore [private](https://user:secret@example.com/private), javascript:alert(1), and https://.
            """
            return JournalAtomicCaptureRequest(
                journalDate: "2026-07-15",
                time: "14:20",
                text: text,
                source: "voice",
                capturedAt: Date(timeIntervalSince1970: 1_768_510_800),
                idempotencyKey: "cid-759:checkpoint-3:capture",
                sourceContext: CaptureSourceContext(
                    surface: "hermes",
                    channel: "voice",
                    messageID: "cid-759-message",
                    originalText: text
                ),
                media: [.init(
                    sourceURL: photoURL,
                    sourceID: "cid-759:photo:1",
                    kind: .photo,
                    displayTitle: "CID-759 source photo",
                    mimeType: "image/jpeg"
                )]
            )
        }

        func seedCanonicalReferences() throws {
            try insertContact(id: "alex-rivera-1", title: "Alex Rivera")
            try insertContact(id: "alex-rivera-2", title: "Alex Rivera")
            let labels = SecondBrainOwnerLabelIndexService(database: database)
            _ = try labels.refreshContact(ownerID: "alex-rivera-1")
            _ = try labels.refreshContact(ownerID: "alex-rivera-2")
            _ = try labels.upsertLabel(
                owner: SecondBrainOwnerRef(ownerType: "place", ownerID: "pike-place-market"),
                ownerKind: "place",
                canonicalLabel: "Pike Place Market",
                aliases: [],
                sourceRefs: ["place:pike-place-market"],
                labelSource: "cid-759.test",
                confidence: 1
            )
            let timestamp = Date(timeIntervalSince1970: 1_768_500_000).timeIntervalSince1970
            let project = try database.prepare("""
                INSERT INTO projects (id, title, subtitle, status, metadata, created_at, updated_at)
                VALUES ('project-atlas', 'Project Atlas', '', 'active', '{}', ?, ?);
                """)
            project.bind(timestamp, at: 1).bind(timestamp, at: 2)
            try project.step()
        }

        func insertContact(id: String, title: String) throws {
            let timestamp = Date(timeIntervalSince1970: 1_768_500_000).timeIntervalSince1970
            let item = try database.prepare("""
                INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
                VALUES (?, 'contact', ?, ?, ?, NULL, ?);
                """)
            item.bind(id, at: 1)
                .bind(title, at: 2)
                .bind(timestamp, at: 3)
                .bind(timestamp, at: 4)
                .bind("Inbox/Contacts/\(id).vcf", at: 5)
            try item.step()
            let contact = try database.prepare("""
                INSERT INTO contacts (item_id, relationship_label, birthday, notes, email, phone, address, has_avatar, custom_fields)
                VALUES (?, '', NULL, '', '', '', '', 0, '[]');
                """)
            contact.bind(id, at: 1)
            try contact.step()
        }

        func count(_ table: String, where predicate: String? = nil, database: CiderDatabase? = nil) throws -> Int {
            let database = database ?? self.database
            let statement = try database.prepare("SELECT COUNT(*) FROM \(table)\(predicate.map { " WHERE \($0)" } ?? "");")
            try statement.step()
            return statement.int(at: 0)
        }

        func candidateCounts(database: CiderDatabase? = nil) throws -> CandidateCounts {
            let database = database ?? self.database
            return CandidateCounts(
                outputs: try count(
                    "enrichment_outputs",
                    where: "kind IN ('graph_candidate', 'memory_candidate')",
                    database: database
                ),
                evidence: try count(
                    "source_evidence",
                    where: "derived_kind IN ('graph_candidate', 'memory_candidate')",
                    database: database
                ),
                lifecycle: try count(
                    "review_lifecycle_events",
                    where: "candidate_ref LIKE 'graph_candidate:%' OR candidate_ref LIKE 'memory_candidate:%'",
                    database: database
                )
            )
        }

        static func jpegData() throws -> Data {
            let image = NSImage(size: NSSize(width: 8, height: 6))
            image.lockFocus()
            NSColor.systemOrange.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 8, height: 6)).fill()
            image.unlockFocus()
            let tiff = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: tiff))
            return try #require(bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9]))
        }
    }
}
