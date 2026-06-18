import Foundation

struct JournalIntelligenceSnapshot: Equatable {
    var generatedAt: Date
    var note: JournalIntelligenceNoteSummary?
    var captureHealth: JournalIntelligenceCaptureHealth
    var graphCandidates: [JournalIntelligenceCandidate]
    var memoryCandidates: [JournalIntelligenceCandidate]
    var missingMemoryOpportunities: [JournalIntelligenceMissingOpportunity]
    var safeNextCommands: [String]

    static func empty(generatedAt: Date = Date()) -> JournalIntelligenceSnapshot {
        JournalIntelligenceSnapshot(
            generatedAt: generatedAt,
            note: nil,
            captureHealth: .empty,
            graphCandidates: [],
            memoryCandidates: [],
            missingMemoryOpportunities: [],
            safeNextCommands: ["cider-cli capture add --kind journal --date today --stdin --json"]
        )
    }
}

struct JournalIntelligenceNoteSummary: Equatable, Identifiable {
    var id: UUID
    var title: String
    var relativePath: String?
    var createdAt: Date
    var updatedAt: Date
    var content: String
}

struct JournalIntelligenceCaptureHealth: Equatable {
    var provenanceStatus: String
    var provenanceReason: String
    var indexingStatus: String
    var indexingReason: String
    var chunkCount: Int
    var captureEventID: String?
    var captureSourceKind: String?
    var captureSurface: String?
    var captureChannel: String?
    var capturedAt: Date?

    static let empty = JournalIntelligenceCaptureHealth(
        provenanceStatus: "missing",
        provenanceReason: "No latest Daily Journal note was found.",
        indexingStatus: "missing",
        indexingReason: "No note is available for chunk/index inspection.",
        chunkCount: 0,
        captureEventID: nil,
        captureSourceKind: nil,
        captureSurface: nil,
        captureChannel: nil,
        capturedAt: nil
    )
}

struct JournalIntelligenceCandidate: Equatable, Identifiable {
    var id: String
    var family: String
    var mentionOrValue: String
    var relationOrType: String
    var targetKind: String?
    var sourceQuote: String
    var confidence: Double?
    var qualityLevel: String
    var qualityFlags: [String]
    var qualityExplanation: String
    var truthBoundary: String
    var reviewState: String
    var safeActions: [String]
    var safeNextCommands: [String]
}

struct JournalIntelligenceMissingOpportunity: Equatable, Identifiable {
    var id: String { label }
    var label: String
    var evidenceHint: String
    var reason: String
    var safeNextCommand: String
}

@MainActor
final class JournalIntelligencePanelService {
    private let database: CiderDatabase
    private let now: () -> Date

    init(database: CiderDatabase = .shared, now: @escaping () -> Date = Date.init) {
        self.database = database
        self.now = now
    }

    func latestSnapshot() throws -> JournalIntelligenceSnapshot {
        guard database.isOpen else { return .empty(generatedAt: now()) }
        guard let note = try latestJournalNote() else { return .empty(generatedAt: now()) }

        let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
        let outputs = try SecondBrainEnrichmentOutputService(database: database).outputs(for: owner)
        let reviewItems = try CiderReviewQueueService(database: database)
            .list(limit: Int.max, includeDeferred: true)
            .items
            .filter { $0.itemID == note.id && ($0.kind == "graph_candidate" || $0.kind == "memory_candidate") }
        let reviewByCandidateID = Dictionary(uniqueKeysWithValues: reviewItems.compactMap { item in
            item.candidateID.map { ($0, item) }
        })

        let graphCandidates = outputs
            .filter { $0.kind == SecondBrainGraphCandidateContract.outputKind }
            .compactMap { output -> JournalIntelligenceCandidate? in
                guard let candidate = try? SecondBrainGraphCandidateContract.validate(output) else { return nil }
                let reviewItem = reviewByCandidateID[output.id]
                let quality = qualitySignal(from: reviewItem, mentionText: candidate.mentionText, sourceQuote: candidate.sourceQuote)
                let relations = candidate.relationGuesses.map(\.rawValue)
                let types = candidate.objectTypeGuesses.map(\.rawValue)
                return JournalIntelligenceCandidate(
                    id: output.id,
                    family: "graph_candidate",
                    mentionOrValue: candidate.mentionText,
                    relationOrType: relations.isEmpty ? candidate.kind.rawValue : relations.joined(separator: ", "),
                    targetKind: types.isEmpty ? nil : types.joined(separator: ", "),
                    sourceQuote: candidate.sourceQuote,
                    confidence: candidate.confidence,
                    qualityLevel: quality.level,
                    qualityFlags: quality.codes,
                    qualityExplanation: quality.explanation,
                    truthBoundary: reviewItem?.truthState ?? (candidate.reviewState == .accepted ? "accepted_graph_truth" : "reviewable_candidate_not_truth"),
                    reviewState: output.reviewState,
                    safeActions: candidate.safeActions.map(\.rawValue),
                    safeNextCommands: reviewItem?.safeNextCommands ?? safeCommands(forGraphCandidate: output, note: note)
                )
            }

        let memoryCandidates = outputs
            .filter { $0.kind == "memory_candidate" }
            .map { output -> JournalIntelligenceCandidate in
                let reviewItem = reviewByCandidateID[output.id]
                return JournalIntelligenceCandidate(
                    id: output.id,
                    family: "memory_candidate",
                    mentionOrValue: output.value,
                    relationOrType: output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? "memory",
                    targetKind: output.metadata["memory_status"],
                    sourceQuote: output.evidence,
                    confidence: output.confidence,
                    qualityLevel: reviewItem?.candidateQualityLevel ?? "needs_review",
                    qualityFlags: reviewItem?.candidateQualityCodes ?? ["requires_human_memory_review"],
                    qualityExplanation: reviewItem?.candidateQualityExplanation ?? "Memory candidates are source-backed suggestions and must be reviewed before promotion.",
                    truthBoundary: reviewItem?.truthState ?? (output.reviewState == "accepted" ? "accepted_memory_candidate" : "reviewable_candidate_not_truth"),
                    reviewState: output.reviewState,
                    safeActions: reviewItem?.safeActions ?? ["inspect_source", "accept", "reject", "defer", "correct"],
                    safeNextCommands: reviewItem?.safeNextCommands ?? safeCommands(forMemoryCandidate: output, note: note)
                )
            }

        let safeNextCommands = orderedUnique([
            "cider-cli item get note \(note.id.uuidString) --json",
            "cider-cli item graph-candidates note \(note.id.uuidString) --json",
            "cider-cli capture review-queue --kind graph_candidate --json",
            "cider-cli capture review-queue --kind memory_candidate --json",
            "cider-cli item recall-context --item note \(note.id.uuidString) --json",
        ] + graphCandidates.flatMap(\.safeNextCommands) + memoryCandidates.flatMap(\.safeNextCommands))

        return JournalIntelligenceSnapshot(
            generatedAt: now(),
            note: note,
            captureHealth: try captureHealth(for: note),
            graphCandidates: graphCandidates,
            memoryCandidates: memoryCandidates,
            missingMemoryOpportunities: missingMemoryOpportunities(note: note, memoryCandidates: memoryCandidates),
            safeNextCommands: safeNextCommands
        )
    }

    private func latestJournalNote() throws -> JournalIntelligenceNoteSummary? {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, i.relative_path, i.created_at, i.updated_at, n.content
            FROM items i
            JOIN notes n ON n.item_id = i.id
            WHERE i.type = 'note'
              AND (i.title LIKE 'Daily Journal %' OR i.relative_path LIKE '%Daily Journal %.md')
            ORDER BY i.created_at DESC, i.updated_at DESC
            LIMIT 1;
            """)
        guard try stmt.step(), let id = UUID(uuidString: stmt.string(at: 0)) else { return nil }
        return JournalIntelligenceNoteSummary(
            id: id,
            title: stmt.string(at: 1),
            relativePath: stmt.optionalString(at: 2),
            createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 3)),
            updatedAt: DatabaseHelpers.decodeDate(stmt.double(at: 4)),
            content: stmt.optionalString(at: 5) ?? ""
        )
    }

    private func captureHealth(for note: JournalIntelligenceNoteSummary) throws -> JournalIntelligenceCaptureHealth {
        let chunk = try chunkStatus(for: note)
        let stmt = try database.prepare("""
            SELECT e.id, e.source_kind, e.surface, e.channel, e.created_at
            FROM owner_relations r
            JOIN capture_events e ON e.id = r.source_owner_id
            WHERE r.source_owner_type = 'capture_event'
              AND r.target_owner_type = 'note'
              AND r.target_owner_id = ?
              AND r.relation_type = 'produced_item'
            ORDER BY e.created_at DESC
            LIMIT 1;
            """)
        stmt.bind(note.id.uuidString, at: 1)
        if try stmt.step() {
            return JournalIntelligenceCaptureHealth(
                provenanceStatus: "recorded",
                provenanceReason: "Capture provenance is linked by owner_relations produced_item.",
                indexingStatus: chunk.status,
                indexingReason: chunk.reason,
                chunkCount: chunk.count,
                captureEventID: stmt.string(at: 0),
                captureSourceKind: stmt.optionalString(at: 1),
                captureSurface: stmt.optionalString(at: 2),
                captureChannel: stmt.optionalString(at: 3),
                capturedAt: DatabaseHelpers.decodeDate(stmt.double(at: 4))
            )
        }
        return JournalIntelligenceCaptureHealth(
            provenanceStatus: "missing",
            provenanceReason: "No capture_events produced_item provenance is linked to this journal note.",
            indexingStatus: chunk.status,
            indexingReason: chunk.reason,
            chunkCount: chunk.count,
            captureEventID: nil,
            captureSourceKind: nil,
            captureSurface: nil,
            captureChannel: nil,
            capturedAt: nil
        )
    }

    private func chunkStatus(for note: JournalIntelligenceNoteSummary) throws -> (status: String, reason: String, count: Int) {
        let stmt = try database.prepare("""
            SELECT COUNT(id), MAX(updated_at)
            FROM content_chunks
            WHERE owner_type = 'note' AND owner_id = ?;
            """)
        stmt.bind(note.id.uuidString, at: 1)
        guard try stmt.step() else {
            return ("missing", "No content chunk query result was available.", 0)
        }
        let count = stmt.int(at: 0)
        guard count > 0 else {
            return ("missing", "No searchable content chunks exist for this journal note.", 0)
        }
        let updatedAt = stmt.optionalDouble(at: 1).map(DatabaseHelpers.decodeDate)
        if let updatedAt, updatedAt >= note.updatedAt {
            return ("indexed", "\(count) searchable content chunk(s) are current for this journal note.", count)
        }
        return ("stale", "\(count) content chunk(s) exist, but they predate the journal note update.", count)
    }

    private func qualitySignal(from item: CiderReviewQueueItem?, mentionText: String, sourceQuote: String) -> (level: String, codes: [String], explanation: String) {
        if let item {
            return (
                item.candidateQualityLevel ?? "needs_review",
                item.candidateQualityCodes,
                item.candidateQualityExplanation ?? "Review this source-backed candidate before accepting it as truth."
            )
        }
        let lower = mentionText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let codes: [String]
        if ["one", "it", "that", "this", "thing", "stuff"].contains(lower) {
            codes = ["pronoun_or_placeholder_only", "vague_pronoun_fragment"]
        } else if mentionText.count > 80 || mentionText.contains(":") {
            codes = ["long_phrase_maybe_not_canonical_object"]
        } else {
            codes = []
        }
        if codes.isEmpty {
            return ("good", [], "Looks concrete, but remains a source-backed candidate until explicitly accepted.")
        }
        return ("low", codes, "Likely noisy; inspect/correct/reject instead of accepting as truth.")
    }

    private func missingMemoryOpportunities(note: JournalIntelligenceNoteSummary, memoryCandidates: [JournalIntelligenceCandidate]) -> [JournalIntelligenceMissingOpportunity] {
        guard memoryCandidates.isEmpty else { return [] }
        let lower = note.content.lowercased()
        let probes: [(String, [String], String)] = [
            ("Eating-plan / overnight-work signal", ["overnight", "oats", "weekend overtime", "eating plan"], "No memory_candidate was generated for the journal's work/eating-plan planning signal."),
            ("GLP-1 cost barrier", ["glp", "ozempic", "wegovy", "mounjaro", "cost"], "No memory_candidate was generated for the durable medication/cost-barrier signal."),
            ("Rowing-machine-to-garage habit", ["rowing", "garage"], "No memory_candidate was generated for the habit/environment change signal."),
            ("Work pace mindset", ["pace", "mindset", "slower", "faster", "burnout"], "No memory_candidate was generated for the work pace/mindset signal."),
        ]
        var opportunities = probes.compactMap { label, needles, reason -> JournalIntelligenceMissingOpportunity? in
            guard needles.contains(where: lower.contains) else { return nil }
            return JournalIntelligenceMissingOpportunity(
                label: label,
                evidenceHint: needles.first(where: lower.contains) ?? label,
                reason: reason,
                safeNextCommand: "cider-cli item memory-suggest note \(note.id.uuidString) --kind pattern --value '<reviewed memory>' --evidence '<source quote>' --json"
            )
        }
        if opportunities.isEmpty {
            opportunities.append(JournalIntelligenceMissingOpportunity(
                label: "No memory candidates extracted",
                evidenceHint: note.title,
                reason: "This journal has zero memory_candidate rows; inspect the source manually for durable user preferences, patterns, constraints, or agent lessons.",
                safeNextCommand: "cider-cli capture review-queue --kind memory_candidate --json"
            ))
        }
        return opportunities
    }

    private func safeCommands(forGraphCandidate output: SecondBrainEnrichmentOutput, note: JournalIntelligenceNoteSummary) -> [String] {
        [
            "cider-cli item graph-candidate \(output.id) --json",
            "cider-cli item graph-candidates note \(note.id.uuidString) --json",
            "cider-cli item context note \(note.id.uuidString) --json",
            "cider-cli capture review-queue --kind graph_candidate --json",
        ]
    }

    private func safeCommands(forMemoryCandidate output: SecondBrainEnrichmentOutput, note: JournalIntelligenceNoteSummary) -> [String] {
        [
            "cider-cli item memory-candidate \(output.id) --json",
            "cider-cli item context note \(note.id.uuidString) --json",
            "cider-cli capture review-queue --kind memory_candidate --json",
        ]
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values where !value.isEmpty && seen.insert(value).inserted {
            output.append(value)
        }
        return output
    }
}
