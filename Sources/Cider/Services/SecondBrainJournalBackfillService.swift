import Foundation

struct SecondBrainJournalBackfillOwnerResult: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var date: String?
    var chunkCount: Int
    var referenceCount: Int
    var enrichmentOutputCount: Int
    var enrichmentKindCounts: [String: Int]
    var enrichmentReviewStates: [String: Int]
    var similarityCandidateCount: Int
    var similarityReviewStates: [String: Int]
    var graphCandidateCount: Int
    var memoryCandidateCount: Int
    var graphCandidates: [SecondBrainEnrichmentOutput]
    var memoryCandidates: [SecondBrainEnrichmentOutput]
}

struct SecondBrainJournalBackfillError: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var date: String?
    var message: String
}

struct SecondBrainJournalBackfillSkippedOwner: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var date: String?
    var reason: String
    var chunkCount: Int
    var enrichmentOutputCount: Int
    var similarityCandidateCount: Int
}

struct SecondBrainJournalBackfillResult: Codable, Equatable {
    var scope: String
    var dryRun: Bool
    var selectedCount: Int
    var skippedCount: Int
    var skippedAlreadySeededCount: Int
    var ownerCount: Int
    var errorCount: Int
    var errors: [SecondBrainJournalBackfillError]
    var limit: Int
    var date: String?
    var threshold: Double
    var candidateLimit: Int
    var chunkCount: Int
    var referenceCount: Int
    var enrichmentOutputCount: Int
    var similarityCandidateCount: Int
    var graphCandidateCount: Int
    var memoryCandidateCount: Int
    var reviewRequired: Bool
    var owners: [SecondBrainJournalBackfillOwnerResult]
    var skippedOwners: [SecondBrainJournalBackfillSkippedOwner]
}

@MainActor
final class SecondBrainJournalBackfillService {
    private let database: CiderDatabase
    private let store: SecondBrainStore
    private let notesStorage: NotesStorage

    init(
        database: CiderDatabase = .shared,
        store: SecondBrainStore? = nil,
        notesStorage: NotesStorage = .shared
    ) {
        self.database = database
        self.store = store ?? SecondBrainStore(database: database)
        self.notesStorage = notesStorage
    }

    func backfillDailyJournals(
        limit: Int = 20,
        date: String? = nil,
        threshold: Double = 0.34,
        candidateLimit: Int = 10,
        dryRun: Bool = false
    ) throws -> SecondBrainJournalBackfillResult {
        let boundedLimit = max(0, limit)
        let boundedCandidateLimit = max(0, candidateLimit)
        let normalizedDate = date?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        let dailyNotes = allDailyJournalNotes()
        let selection = try selectDailyJournalNotes(
            from: dailyNotes,
            limit: boundedLimit,
            date: normalizedDate
        )
        let selectedNotes = selection.selected
        let skippedOwners = selection.skippedOwners
        let skippedCount = max(0, dailyNotes.count - selectedNotes.count)

        let indexer = SecondBrainItemContentIndexingService(database: database, store: store)
        let referenceExtractor = SecondBrainReferenceExtractionService(store: store, notesStorage: notesStorage)
        let enrichmentService = SecondBrainEnrichmentOutputService(database: database)
        let similarityService = SecondBrainSimilarityCandidateService(database: database, store: store)
        let journalExtractor = SecondBrainJournalGraphCandidateExtractor()

        var ownerResults: [SecondBrainJournalBackfillOwnerResult] = []
        var errors: [SecondBrainJournalBackfillError] = []
        for note in selectedNotes {
            let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
            if dryRun {
                ownerResults.append(Self.emptyOwnerResult(for: note, owner: owner))
                continue
            }

            do {
                let contentIndex = try indexer.rebuild(owner: owner)
                let references = try referenceExtractor.rebuildNote(note)
                let chunkEnrichment = try enrichmentService.rebuildFromChunks(owner: owner)
                let rawContent = notesStorage.loadContent(for: note)
                let journalExtraction = journalExtractor.extract(
                    sourceOwner: owner,
                    rawContent: rawContent,
                    date: note.dailyJournalDateLabel,
                    time: nil
                )
                for output in journalExtraction.outputs {
                    try enrichmentService.record(output)
                }
                _ = try similarityService.rebuildChunkOverlapCandidates(
                    for: owner,
                    threshold: threshold,
                    limit: boundedCandidateLimit
                )
                _ = try similarityService.rebuildEntityRelationCandidates(
                    for: owner,
                    targetTypes: ["contact"],
                    limit: boundedCandidateLimit
                )

                let outputs = try enrichmentService.outputs(for: owner)
                let similarityCandidates = try similarityService.candidates(for: owner)
                let graphCandidates = outputs.filter { $0.kind == SecondBrainGraphCandidateContract.outputKind }
                let memoryCandidates = outputs.filter { $0.kind == "memory_candidate" }
                ownerResults.append(SecondBrainJournalBackfillOwnerResult(
                    owner: owner,
                    title: note.title,
                    date: note.dailyJournalDateLabel,
                    chunkCount: contentIndex.chunkCount,
                    referenceCount: references.relations.count,
                    enrichmentOutputCount: chunkEnrichment.outputCount + journalExtraction.outputs.count,
                    enrichmentKindCounts: Dictionary(grouping: outputs, by: \.kind).mapValues(\.count),
                    enrichmentReviewStates: Dictionary(grouping: outputs, by: \.reviewState).mapValues(\.count),
                    similarityCandidateCount: similarityCandidates.count,
                    similarityReviewStates: Dictionary(grouping: similarityCandidates, by: \.reviewState).mapValues(\.count),
                    graphCandidateCount: graphCandidates.count,
                    memoryCandidateCount: memoryCandidates.count,
                    graphCandidates: graphCandidates,
                    memoryCandidates: memoryCandidates
                ))
            } catch {
                errors.append(SecondBrainJournalBackfillError(
                    owner: owner,
                    title: note.title,
                    date: note.dailyJournalDateLabel,
                    message: error.localizedDescription
                ))
            }
        }

        let chunkCount = ownerResults.reduce(0) { $0 + $1.chunkCount }
        let referenceCount = ownerResults.reduce(0) { $0 + $1.referenceCount }
        let enrichmentOutputCount = ownerResults.reduce(0) { $0 + $1.enrichmentOutputCount }
        let similarityCandidateCount = ownerResults.reduce(0) { $0 + $1.similarityCandidateCount }
        let graphCandidateCount = ownerResults.reduce(0) { $0 + $1.graphCandidateCount }
        let memoryCandidateCount = ownerResults.reduce(0) { $0 + $1.memoryCandidateCount }
        return SecondBrainJournalBackfillResult(
            scope: "daily_journal",
            dryRun: dryRun,
            selectedCount: selectedNotes.count,
            skippedCount: skippedCount,
            skippedAlreadySeededCount: skippedOwners.count,
            ownerCount: ownerResults.count,
            errorCount: errors.count,
            errors: errors,
            limit: boundedLimit,
            date: normalizedDate,
            threshold: threshold,
            candidateLimit: boundedCandidateLimit,
            chunkCount: chunkCount,
            referenceCount: referenceCount,
            enrichmentOutputCount: enrichmentOutputCount,
            similarityCandidateCount: similarityCandidateCount,
            graphCandidateCount: graphCandidateCount,
            memoryCandidateCount: memoryCandidateCount,
            reviewRequired: graphCandidateCount > 0 || memoryCandidateCount > 0 || similarityCandidateCount > 0 || enrichmentOutputCount > 0,
            owners: ownerResults,
            skippedOwners: skippedOwners
        )
    }

    private static func emptyOwnerResult(for note: Note, owner: SecondBrainOwnerRef) -> SecondBrainJournalBackfillOwnerResult {
        SecondBrainJournalBackfillOwnerResult(
            owner: owner,
            title: note.title,
            date: note.dailyJournalDateLabel,
            chunkCount: 0,
            referenceCount: 0,
            enrichmentOutputCount: 0,
            enrichmentKindCounts: [:],
            enrichmentReviewStates: [:],
            similarityCandidateCount: 0,
            similarityReviewStates: [:],
            graphCandidateCount: 0,
            memoryCandidateCount: 0,
            graphCandidates: [],
            memoryCandidates: []
        )
    }

    private func allDailyJournalNotes() -> [Note] {
        notesStorage.notes
            .filter(\.isDailyJournalNote)
            .sorted { lhs, rhs in
                if lhs.title != rhs.title { return lhs.title > rhs.title }
                return lhs.modifiedAt > rhs.modifiedAt
            }
    }

    private func selectDailyJournalNotes(
        from dailyNotes: [Note],
        limit: Int,
        date: String?
    ) throws -> (selected: [Note], skippedOwners: [SecondBrainJournalBackfillSkippedOwner]) {
        guard limit > 0 else { return ([], []) }
        var selected: [Note] = []
        var skippedOwners: [SecondBrainJournalBackfillSkippedOwner] = []
        for note in dailyNotes {
            if let date, note.dailyJournalDateLabel != date {
                continue
            }
            let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: note.id.uuidString)
            if date == nil {
                let counts = try generatedArtifactCounts(for: owner)
                if counts.isSeeded {
                    skippedOwners.append(SecondBrainJournalBackfillSkippedOwner(
                        owner: owner,
                        title: note.title,
                        date: note.dailyJournalDateLabel,
                        reason: "already_seeded",
                        chunkCount: counts.chunkCount,
                        enrichmentOutputCount: counts.enrichmentOutputCount,
                        similarityCandidateCount: counts.similarityCandidateCount
                    ))
                    continue
                }
            }
            selected.append(note)
            if selected.count >= limit {
                break
            }
        }
        return (selected, skippedOwners)
    }

    private struct GeneratedArtifactCounts {
        var chunkCount: Int
        var enrichmentOutputCount: Int
        var similarityCandidateCount: Int

        var isSeeded: Bool {
            enrichmentOutputCount > 0 || similarityCandidateCount > 0
        }
    }

    private func generatedArtifactCounts(for owner: SecondBrainOwnerRef) throws -> GeneratedArtifactCounts {
        GeneratedArtifactCounts(
            chunkCount: try countRows(
                sql: "SELECT count(*) FROM content_chunks WHERE owner_type = ? AND owner_id = ?;",
                owner: owner
            ),
            enrichmentOutputCount: try countRows(
                sql: "SELECT count(*) FROM enrichment_outputs WHERE owner_type = ? AND owner_id = ?;",
                owner: owner
            ),
            similarityCandidateCount: try countRows(
                sql: "SELECT count(*) FROM similarity_candidates WHERE source_owner_type = ? AND source_owner_id = ?;",
                owner: owner
            )
        )
    }

    private func countRows(sql: String, owner: SecondBrainOwnerRef) throws -> Int {
        let stmt = try database.prepare(sql)
        stmt.bind(owner.ownerType, at: 1)
            .bind(owner.ownerID, at: 2)
        guard try stmt.step() else { return 0 }
        return stmt.int(at: 0)
    }
}

private extension String {
    var nilIfBlank: String? {
        isEmpty ? nil : self
    }
}
