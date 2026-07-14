import Foundation
import Testing
@testable import Cider

@Suite("Journal Intelligence Daily Receipt Tests")
@MainActor
struct JournalIntelligenceDailyReceiptTests {
    @Test("representative text and voice corpus exercises production extraction guards")
    func corpusExercisesProductionExtractionGuards() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let morning = JournalIntelligenceCorpus.captures[0]
        let correction = JournalIntelligenceCorpus.captures[2]

        let morningOutputs = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: morning.text,
            date: JournalIntelligenceCorpus.date,
            time: morning.time
        ).outputs
        #expect(morningOutputs.contains { $0.value == "Discovery Park" })
        #expect(morningOutputs.contains { $0.value == "Arrival" })
        #expect(morningOutputs.contains { $0.value.localizedCaseInsensitiveContains("cedar loop hike") })

        let correctionOutputs = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: correction.text,
            date: JournalIntelligenceCorpus.date,
            time: correction.time
        ).outputs
        #expect(!correctionOutputs.contains { $0.value.lowercased() == "it" })
        #expect(!correctionOutputs.contains { $0.value.localizedCaseInsensitiveContains("Red Barn") })
    }

    @Test("production extractor fails closed for ambiguous negated corrected and vague intent wording")
    func productionExtractorFailsClosedForGuardWording() throws {
        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: UUID().uuidString)
        let outputs = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: JournalIntelligenceCorpus.precisionGuardText,
            date: JournalIntelligenceCorpus.date,
            time: "20:15"
        ).outputs

        let guardedKinds = Set([
            "relationship_event",
            "commitment",
            "task_intent",
            "trip_plan",
            "artifact_intent",
            "durable_memory",
        ])
        #expect(outputs.filter { output in
            guard output.kind == "memory_candidate" else { return false }
            let kind = output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? ""
            return guardedKinds.contains(kind)
        }.isEmpty)
    }

    @Test("daily receipt groups only precise active proposals with complete capture provenance")
    func dailyReceiptGroupsOnlyPreciseActiveProposals() throws {
        let fixture = try makeFixture()
        defer { fixture.close() }

        let service = JournalIntelligenceDailyReceiptService(database: fixture.database)
        let first = try service.receipt(date: JournalIntelligenceCorpus.date)
        let second = try service.receipt(date: JournalIntelligenceCorpus.date)

        #expect(first == second)
        #expect(first.readOnly)
        #expect(!first.changed)
        #expect(first.proposalCount == 9)
        #expect(first.statement == "Cider found 9 things worth reviewing.")
        #expect(first.groups.map(\.category) == JournalIntelligenceCategory.allCases)
        #expect(first.groups.allSatisfy { $0.proposals.count == 1 })
        #expect(first.suppressedCount == 7)

        let proposals = first.groups.flatMap(\.proposals)
        #expect(Set(proposals.map(\.category)) == Set(JournalIntelligenceCategory.allCases))
        #expect(proposals.allSatisfy { $0.journalOwner.ref == "note:\(fixture.noteID.uuidString)" })
        #expect(proposals.allSatisfy { !$0.captureEvent.id.isEmpty && $0.captureEvent.ref.hasPrefix("capture_event:") })
        #expect(proposals.allSatisfy { !$0.section.id.isEmpty && $0.section.timestamp24Hour == $0.captureEvent.journalTime })
        #expect(proposals.allSatisfy { !$0.source.quote.isEmpty && $0.source.spanEnd > $0.source.spanStart })
        #expect(proposals.allSatisfy { $0.source.coordinateSpace == "capture_event.source_text" })
        #expect(proposals.allSatisfy { $0.confidence >= 0.70 && !$0.confidenceReason.isEmpty })
        #expect(proposals.allSatisfy { $0.truthBoundary == "reviewable_candidate_not_truth" })
        #expect(proposals.contains { $0.category == .tasks && $0.proposalState == "deferred" })

        let reasonCodes = Set(first.suppressions.flatMap(\.reasonCodes))
        #expect(reasonCodes.contains("low_confidence"))
        #expect(reasonCodes.contains("low_quality_candidate"))
        #expect(reasonCodes.contains("corrected_later_in_capture"))
        #expect(reasonCodes.contains("duplicate_within_day"))
        #expect(reasonCodes.contains("terminal_review_state"))
        #expect(reasonCodes.contains("missing_capture_event_provenance"))
    }

    private struct Fixture {
        var database: CiderDatabase
        var databaseURL: URL
        var noteID: UUID

        @MainActor
        func close() {
            database.close()
            try? FileManager.default.removeItem(at: databaseURL)
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-wal")
            try? FileManager.default.removeItem(atPath: databaseURL.path + "-shm")
        }
    }

    private func makeFixture() throws -> Fixture {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-journal-intelligence-receipt-\(UUID().uuidString).db")
        let database = CiderDatabase()
        try database.open(at: url)
        let noteID = UUID()
        let noteOwner = SecondBrainOwnerRef(ownerType: "note", ownerID: noteID.uuidString)
        let baseTime = Date(timeIntervalSince1970: 1_784_000_000)

        try insertJournal(noteID: noteID, at: baseTime, into: database)
        for (index, capture) in JournalIntelligenceCorpus.captures.enumerated() {
            try insertCapture(capture, noteID: noteID, at: baseTime.addingTimeInterval(Double(index * 60)), into: database)
        }

        let morning = JournalIntelligenceCorpus.captures[0]
        let midday = JournalIntelligenceCorpus.captures[1]
        let correction = JournalIntelligenceCorpus.captures[2]
        let outputService = SecondBrainEnrichmentOutputService(database: database)

        try record(memory(
            id: "people-maya",
            owner: noteOwner,
            capture: morning,
            quote: "Maya started a new job at Alder Labs.",
            value: "Maya started a new job at Alder Labs.",
            kind: "relationship_event",
            confidence: 0.86
        ), capture: morning, using: outputService)
        try record(graph(
            id: "place-discovery",
            owner: noteOwner,
            capture: morning,
            quote: "I went to Discovery Park.",
            mention: "Discovery Park",
            types: [.place],
            relations: [.visited],
            confidence: 0.82
        ), capture: morning, using: outputService)
        try record(memory(
            id: "activity-hike",
            owner: noteOwner,
            capture: morning,
            quote: "I loved the cedar loop hike.",
            value: "Visher completed the cedar loop hike.",
            kind: "activity",
            confidence: 0.78
        ), capture: morning, using: outputService)
        try record(graph(
            id: "preference-hike",
            owner: noteOwner,
            capture: morning,
            quote: "I loved the cedar loop hike.",
            mention: "cedar loop hike",
            types: [.object],
            relations: [.likes],
            confidence: 0.78
        ), capture: morning, using: outputService)
        try record(memory(
            id: "commitment-map",
            owner: noteOwner,
            capture: morning,
            quote: "I promised Maya I would bring the trail map tomorrow.",
            value: "Bring Maya the trail map tomorrow.",
            kind: "commitment",
            confidence: 0.88
        ), capture: morning, using: outputService)
        var task = memory(
            id: "task-permit",
            owner: noteOwner,
            capture: morning,
            quote: "Remember to email the signed permit.",
            value: "Email the signed permit.",
            kind: "task_intent",
            confidence: 0.9
        )
        task.reviewState = "deferred"
        try record(task, capture: morning, using: outputService)
        try record(graph(
            id: "artifact-arrival",
            owner: noteOwner,
            capture: morning,
            quote: "I watched Arrival last night.",
            mention: "Arrival",
            types: [.movie, .media],
            relations: [.watched],
            confidence: 0.84
        ), capture: morning, using: outputService)
        try record(memory(
            id: "trip-kyoto",
            owner: noteOwner,
            capture: midday,
            quote: "We are planning a September trip to Kyoto.",
            value: "Plan a September trip to Kyoto.",
            kind: "trip_plan",
            confidence: 0.9
        ), capture: midday, using: outputService)
        try record(memory(
            id: "memory-hiking-mood",
            owner: noteOwner,
            capture: morning,
            quote: "Remember that hiking before work improves my mood.",
            value: "Hiking before work improves Visher's mood.",
            kind: "pattern",
            confidence: 0.88
        ), capture: morning, using: outputService)

        try record(graph(
            id: "noise-vague",
            owner: noteOwner,
            capture: correction,
            quote: "I liked it.",
            mention: "it",
            types: [.object],
            relations: [.likes],
            confidence: 0.91
        ), capture: correction, using: outputService)
        try record(graph(
            id: "noise-incidental",
            owner: noteOwner,
            capture: midday,
            quote: "Maybe Alex mentioned the old mall, but I am not sure.",
            mention: "old mall",
            types: [.place],
            relations: [.mentions],
            confidence: 0.51
        ), capture: midday, using: outputService)
        try record(graph(
            id: "noise-corrected",
            owner: noteOwner,
            capture: correction,
            quote: "I went to Portland.",
            mention: "Portland",
            types: [.place],
            relations: [.visited],
            confidence: 0.84
        ), capture: correction, using: outputService)
        try record(graph(
            id: "noise-duplicate",
            owner: noteOwner,
            capture: midday,
            quote: "I went to Discovery Park again.",
            mention: "Discovery Park",
            types: [.place],
            relations: [.visited],
            confidence: 0.8
        ), capture: midday, using: outputService)
        var accepted = memory(
            id: "noise-accepted",
            owner: noteOwner,
            capture: correction,
            quote: "I went to Seattle.",
            value: "Visher went to Seattle.",
            kind: "activity",
            confidence: 0.84
        )
        accepted.reviewState = "accepted"
        try record(accepted, capture: correction, using: outputService)
        var rejected = memory(
            id: "noise-rejected",
            owner: noteOwner,
            capture: correction,
            quote: "I did not visit the Red Barn.",
            value: "Visher visited the Red Barn.",
            kind: "activity",
            confidence: 0.84
        )
        rejected.reviewState = "rejected"
        try record(rejected, capture: correction, using: outputService)
        var missingProvenance = memory(
            id: "noise-no-provenance",
            owner: noteOwner,
            capture: midday,
            quote: "Save the ferry itinerary PDF with the trip.",
            value: "Save the ferry itinerary PDF.",
            kind: "artifact",
            confidence: 0.9
        )
        missingProvenance.metadata.removeValue(forKey: "capture_event_id")
        missingProvenance.metadata.removeValue(forKey: "capture_event_ref")
        try outputService.record(missingProvenance)

        return Fixture(database: database, databaseURL: url, noteID: noteID)
    }

    private func insertJournal(noteID: UUID, at date: Date, into database: CiderDatabase) throws {
        let title = "Daily Journal \(JournalIntelligenceCorpus.date)"
        let item = try database.prepare("""
            INSERT INTO items (id, type, title, created_at, updated_at, folder_id, relative_path)
            VALUES (?, 'note', ?, ?, ?, NULL, ?);
            """)
        item.bind(noteID.uuidString, at: 1)
            .bind(title, at: 2)
            .bind(date.timeIntervalSince1970, at: 3)
            .bind(date.timeIntervalSince1970, at: 4)
            .bind("Inbox/Notes/\(title).md", at: 5)
        try item.step()
        let note = try database.prepare("INSERT INTO notes (item_id, content, summary, is_pinned) VALUES (?, ?, NULL, 0);")
        note.bind(noteID.uuidString, at: 1)
            .bind(JournalIntelligenceCorpus.journalMarkdown, at: 2)
        try note.step()
    }

    private func insertCapture(_ capture: JournalIntelligenceCorpus.Capture, noteID: UUID, at date: Date, into database: CiderDatabase) throws {
        let metadata = DatabaseHelpers.encodeJSON([
            "date": JournalIntelligenceCorpus.date,
            "time": capture.time,
            "appendSource": capture.source,
            "input": capture.surface == "voice" ? "voice-transcript" : "text",
        ]) ?? "{}"
        let event = try database.prepare("""
            INSERT INTO capture_events (id, source_kind, surface, channel, channel_id, thread_id, message_id, sender_id, sender_name, source_url, source_file, source_text, attachment_count, metadata, created_at)
            VALUES (?, 'journal', ?, ?, NULL, NULL, NULL, NULL, 'Visher', NULL, NULL, ?, 0, ?, ?);
            """)
        event.bind(capture.id, at: 1)
            .bind(capture.surface, at: 2)
            .bind(capture.source, at: 3)
            .bind(capture.text, at: 4)
            .bind(metadata, at: 5)
            .bind(date.timeIntervalSince1970, at: 6)
        try event.step()

        let relation = try database.prepare("""
            INSERT INTO owner_relations (id, source_owner_type, source_owner_id, target_owner_type, target_owner_id, relation_type, evidence, source, actor, confidence, metadata, created_at, updated_at)
            VALUES (?, 'capture_event', ?, 'note', ?, 'produced_item', 'Journal capture appended to note.', 'capture.add', 'system', 1, '{}', ?, ?);
            """)
        relation.bind("relation-\(capture.id)", at: 1)
            .bind(capture.id, at: 2)
            .bind(noteID.uuidString, at: 3)
            .bind(date.timeIntervalSince1970, at: 4)
            .bind(date.timeIntervalSince1970, at: 5)
        try relation.step()
    }

    private func record(_ output: SecondBrainEnrichmentOutput, capture: JournalIntelligenceCorpus.Capture, using service: SecondBrainEnrichmentOutputService) throws {
        var output = output
        output.metadata["capture_event_id"] = capture.id
        output.metadata["capture_event_ref"] = "capture_event:\(capture.id)"
        output.metadata["journal_date"] = JournalIntelligenceCorpus.date
        output.metadata["journal_time"] = capture.time
        try service.record(output)
    }

    private func graph(
        id: String,
        owner: SecondBrainOwnerRef,
        capture: JournalIntelligenceCorpus.Capture,
        quote: String,
        mention: String,
        types: [SecondBrainGraphCandidateContract.ObjectType],
        relations: [SecondBrainGraphCandidateContract.RelationType],
        confidence: Double
    ) -> SecondBrainEnrichmentOutput {
        var output = try! SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: owner,
            candidateKind: .objectRelation,
            mentionText: mention,
            sourceQuote: quote,
            sourceKind: "journal",
            objectTypeGuesses: types,
            relationGuesses: relations,
            confidence: confidence,
            confidenceReason: "The deterministic journal corpus contains an explicit source-backed statement.",
            source: "test.journal_intelligence_corpus"
        )
        output.id = id
        addSpan(to: &output, quote: quote, capture: capture)
        return output
    }

    private func memory(
        id: String,
        owner: SecondBrainOwnerRef,
        capture: JournalIntelligenceCorpus.Capture,
        quote: String,
        value: String,
        kind: String,
        confidence: Double
    ) -> SecondBrainEnrichmentOutput {
        var output = SecondBrainEnrichmentOutput(
            id: id,
            owner: owner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: value.lowercased(),
            label: "Memory candidate: \(kind)",
            evidence: quote,
            source: "test.journal_intelligence_corpus",
            confidence: confidence,
            reviewState: "suggested",
            metadata: [
                "memory_kind": kind,
                "candidate_kind": kind,
                "requires_review": "true",
                "source_kind": "journal",
                "source_quote": quote,
                "source_owner_ref": owner.canonicalRef,
                "truth_boundary": "reviewable_candidate_not_truth",
                "confidence_reason": "The deterministic journal corpus contains an explicit source-backed statement.",
            ]
        )
        addSpan(to: &output, quote: quote, capture: capture)
        return output
    }

    private func addSpan(to output: inout SecondBrainEnrichmentOutput, quote: String, capture: JournalIntelligenceCorpus.Capture) {
        let range = capture.text.range(of: quote)!
        output.metadata["source_span_start"] = String(capture.text.distance(from: capture.text.startIndex, to: range.lowerBound))
        output.metadata["source_span_end"] = String(capture.text.distance(from: capture.text.startIndex, to: range.upperBound))
    }
}
