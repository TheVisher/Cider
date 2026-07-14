import Foundation

enum JournalIntelligenceCategory: String, Codable, CaseIterable, Hashable {
    case people
    case places
    case activities
    case preferences
    case commitments
    case tasks
    case artifactsMedia = "artifacts_media"
    case tripPlans = "trip_plans"
    case durableMemory = "durable_memory"

    var label: String {
        switch self {
        case .people: return "People"
        case .places: return "Places"
        case .activities: return "Activities"
        case .preferences: return "Preferences"
        case .commitments: return "Commitments"
        case .tasks: return "Tasks"
        case .artifactsMedia: return "Artifacts & Media"
        case .tripPlans: return "Trip Plans"
        case .durableMemory: return "Durable Memory"
        }
    }
}

struct JournalIntelligenceOwner: Codable, Equatable {
    var id: String
    var ref: String
    var title: String
    var relativePath: String?
    var journalDate: String
}

struct JournalIntelligenceCaptureEvent: Codable, Equatable {
    var id: String
    var ref: String
    var sourceKind: String
    var surface: String?
    var channel: String?
    var inputKind: String?
    var journalTime: String
    var capturedAt: Date
}

struct JournalIntelligenceSection: Codable, Equatable {
    var id: String
    var timestamp24Hour: String
    var captureSource: String
    var noteSpanStart: Int
    var noteSpanEnd: Int
}

struct JournalIntelligenceSourceSpan: Codable, Equatable {
    var coordinateSpace: String
    var spanStart: Int
    var spanEnd: Int
    var quote: String
}

struct JournalIntelligenceProposal: Codable, Equatable, Identifiable {
    var id: String
    var candidateRef: String
    var family: String
    var category: JournalIntelligenceCategory
    var candidateType: String
    var value: String
    var confidence: Double
    var confidenceReason: String
    var proposalState: String
    var reviewState: String
    var truthBoundary: String
    var journalOwner: JournalIntelligenceOwner
    var captureEvent: JournalIntelligenceCaptureEvent
    var section: JournalIntelligenceSection
    var source: JournalIntelligenceSourceSpan
    var crossTimeReconciliation: JournalIntelligenceCrossTimeReconciliation? = nil
    var safeNextCommands: [String]
}

struct JournalIntelligenceProposalGroup: Codable, Equatable, Identifiable {
    var id: String { category.rawValue }
    var category: JournalIntelligenceCategory
    var label: String
    var count: Int
    var proposals: [JournalIntelligenceProposal]
}

struct JournalIntelligenceSuppression: Codable, Equatable, Identifiable {
    var id: String { candidateRef }
    var candidateRef: String
    var family: String
    var reviewState: String
    var value: String
    var sourceQuote: String
    var reasonCodes: [String]
    var explanation: String
}

struct JournalIntelligenceDailyReceipt: Codable, Equatable {
    var command: String = "item.journal-intelligence"
    var date: String
    var dataAsOf: Date?
    var readOnly: Bool = true
    var changed: Bool = false
    var statement: String
    var proposalCount: Int
    var countsByCategory: [String: Int]
    var groups: [JournalIntelligenceProposalGroup]
    var suppressedCount: Int
    var suppressions: [JournalIntelligenceSuppression]
    var journalOwners: [JournalIntelligenceOwner]
    var truthBoundary: String = "reviewable_candidates_are_not_accepted_truth"
    var safeNextCommands: [String]

    func toDictionary() -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        var dictionary: [String: Any] = [
            "ok": true,
            "command": command,
            "date": date,
            "readOnly": readOnly,
            "changed": changed,
            "statement": statement,
            "proposalCount": proposalCount,
            "countsByCategory": countsByCategory,
            "groups": groups.map { group in
                [
                    "category": group.category.rawValue,
                    "label": group.label,
                    "count": group.count,
                    "proposals": group.proposals.map { $0.toDictionary(formatter: formatter) },
                ] as [String: Any]
            },
            "suppressedCount": suppressedCount,
            "suppressions": suppressions.map { suppression in
                [
                    "candidateRef": suppression.candidateRef,
                    "family": suppression.family,
                    "reviewState": suppression.reviewState,
                    "value": suppression.value,
                    "sourceQuote": suppression.sourceQuote,
                    "reasonCodes": suppression.reasonCodes,
                    "explanation": suppression.explanation,
                ] as [String: Any]
            },
            "journalOwners": journalOwners.map { $0.toDictionary() },
            "truthBoundary": truthBoundary,
            "safeNextCommands": safeNextCommands,
        ]
        if let dataAsOf {
            dictionary["dataAsOf"] = formatter.string(from: dataAsOf)
        }
        return dictionary
    }
}

private extension JournalIntelligenceOwner {
    func toDictionary() -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": id,
            "ref": ref,
            "title": title,
            "journalDate": journalDate,
        ]
        if let relativePath { dictionary["relativePath"] = relativePath }
        return dictionary
    }
}

private extension JournalIntelligenceProposal {
    func toDictionary(formatter: ISO8601DateFormatter) -> [String: Any] {
        [
            "id": id,
            "candidateRef": candidateRef,
            "family": family,
            "category": category.rawValue,
            "candidateType": candidateType,
            "value": value,
            "confidence": confidence,
            "confidenceReason": confidenceReason,
            "proposalState": proposalState,
            "reviewState": reviewState,
            "truthBoundary": truthBoundary,
            "journalOwner": journalOwner.toDictionary(),
            "captureEvent": [
                "id": captureEvent.id,
                "ref": captureEvent.ref,
                "sourceKind": captureEvent.sourceKind,
                "surface": captureEvent.surface as Any,
                "channel": captureEvent.channel as Any,
                "inputKind": captureEvent.inputKind as Any,
                "journalTime": captureEvent.journalTime,
                "capturedAt": formatter.string(from: captureEvent.capturedAt),
            ] as [String: Any],
            "section": [
                "id": section.id,
                "timestamp24Hour": section.timestamp24Hour,
                "captureSource": section.captureSource,
                "noteSourceSpan": [
                    "start": section.noteSpanStart,
                    "end": section.noteSpanEnd,
                ],
            ] as [String: Any],
            "source": [
                "coordinateSpace": source.coordinateSpace,
                "spanStart": source.spanStart,
                "spanEnd": source.spanEnd,
                "quote": source.quote,
            ] as [String: Any],
            "crossTimeReconciliation": crossTimeReconciliation?.toDictionary() ?? NSNull(),
            "safeNextCommands": safeNextCommands,
        ]
    }
}

private extension JournalIntelligenceCrossTimeReconciliation {
    func toDictionary() -> [String: Any] {
        [
            "status": status.rawValue,
            "classification": classification?.rawValue ?? NSNull(),
            "likelyMatches": likelyMatches.map { $0.toDictionary() },
            "reasonCodes": reasonCodes,
            "explanation": explanation,
            "comparedCanonicalKinds": comparedCanonicalKinds,
            "canonicalFamilyScans": canonicalFamilyScans.map { $0.toDictionary() },
            "maxLikelyMatches": maxLikelyMatches,
            "truthBoundary": truthBoundary,
            "readOnly": readOnly,
            "changed": changed,
            "safeNextCommands": safeNextCommands,
        ]
    }
}

private extension JournalIntelligenceCanonicalFamilyScan {
    func toDictionary() -> [String: Any] {
        [
            "family": family,
            "limit": limit,
            "loadedCount": loadedCount,
            "complete": complete,
            "truncated": truncated,
        ]
    }
}

private extension JournalIntelligenceLikelyMatch {
    func toDictionary() -> [String: Any] {
        [
            "canonicalRef": canonicalRef,
            "canonicalKind": canonicalKind,
            "canonicalLabel": canonicalLabel,
            "matchStrength": matchStrength.rawValue,
            "confidence": confidence,
            "reasonCodes": reasonCodes,
            "evidence": evidence,
            "safeNextCommands": safeNextCommands,
        ]
    }
}

@MainActor
final class JournalIntelligenceDailyReceiptService {
    enum ReceiptError: LocalizedError, Equatable {
        case invalidDate(String)

        var errorDescription: String? {
            switch self {
            case .invalidDate(let date):
                return "Journal Intelligence date must be YYYY-MM-DD; got '\(date)'."
            }
        }
    }

    private struct JournalSource {
        var owner: JournalIntelligenceOwner
        var note: Note
        var updatedAt: Date
        var sections: [JournalEntrySection]
    }

    private struct CaptureSource {
        var id: String
        var sourceKind: String
        var surface: String?
        var channel: String?
        var sourceText: String
        var metadata: [String: String]
        var createdAt: Date
    }

    private struct ClassifiedCandidate {
        var category: JournalIntelligenceCategory
        var candidateType: String
        var confidenceReason: String
        var graphCandidate: SecondBrainGraphCandidateContract.Candidate?
    }

    private struct CandidateDraft {
        var output: SecondBrainEnrichmentOutput
        var proposal: JournalIntelligenceProposal?
        var suppression: JournalIntelligenceSuppression?
        var capturedAt: Date?
        var stableKey: String?
    }

    private let database: CiderDatabase
    private let minimumConfidence: Double

    init(database: CiderDatabase = .shared, minimumConfidence: Double = 0.70) {
        self.database = database
        self.minimumConfidence = minimumConfidence
    }

    func receipt(date rawDate: String) throws -> JournalIntelligenceDailyReceipt {
        let date = rawDate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard JournalTitle.isValidISODate(date) else { throw ReceiptError.invalidDate(rawDate) }

        let sources = try journalSources(date: date)
        var drafts: [CandidateDraft] = []
        var dataDates = sources.map(\.updatedAt)
        let outputService = SecondBrainEnrichmentOutputService(database: database)

        for source in sources {
            let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: source.owner.id)
            let captureSources = try captureSources(noteID: source.owner.id)
            dataDates.append(contentsOf: captureSources.values.map(\.createdAt))
            for output in try outputService.outputs(for: owner)
                where output.kind == SecondBrainGraphCandidateContract.outputKind || output.kind == "memory_candidate" {
                dataDates.append(output.updatedAt)
                drafts.append(candidateDraft(output: output, journal: source, captures: captureSources))
            }
        }

        drafts.sort(by: draftOrder)
        var seen = Set<String>()
        var proposals: [JournalIntelligenceProposal] = []
        var suppressions: [JournalIntelligenceSuppression] = []
        for draft in drafts {
            if var proposal = draft.proposal, let stableKey = draft.stableKey {
                guard seen.insert(stableKey).inserted else {
                    suppressions.append(suppression(
                        output: draft.output,
                        reasonCodes: ["duplicate_within_day"]
                    ))
                    continue
                }
                proposal.safeNextCommands = orderedUnique(proposal.safeNextCommands)
                proposals.append(proposal)
            } else if let suppression = draft.suppression {
                suppressions.append(suppression)
            }
        }

        let outputByCandidateRef = Dictionary(
            drafts.map { (candidateRef(for: $0.output), $0.output) },
            uniquingKeysWith: { first, _ in first }
        )
        let reconciliationService = JournalIntelligenceCrossTimeReconciliationService(database: database)
        let reconciliation = try reconciliationService.reconcile(proposals.compactMap { proposal in
            guard let output = outputByCandidateRef[proposal.candidateRef] else { return nil }
            return JournalIntelligenceCrossTimeReconciliationService.Input(proposal: proposal, output: output)
        })
        if let canonicalDataAsOf = reconciliation.dataAsOf { dataDates.append(canonicalDataAsOf) }
        for index in proposals.indices {
            proposals[index].crossTimeReconciliation = reconciliation.byCandidateRef[proposals[index].candidateRef]
        }

        proposals.sort(by: proposalOrder)
        suppressions.sort { $0.candidateRef < $1.candidateRef }
        let groups = JournalIntelligenceCategory.allCases.compactMap { category -> JournalIntelligenceProposalGroup? in
            let matches = proposals.filter { $0.category == category }
            guard !matches.isEmpty else { return nil }
            return JournalIntelligenceProposalGroup(
                category: category,
                label: category.label,
                count: matches.count,
                proposals: matches
            )
        }
        let counts = Dictionary(uniqueKeysWithValues: JournalIntelligenceCategory.allCases.map { category in
            (category.rawValue, proposals.count { $0.category == category })
        })
        let count = proposals.count
        let noun = count == 1 ? "thing" : "things"
        let safeNextCommands = orderedUnique(
            ["cider-cli item journal-intelligence --date \(date) --json"]
                + sources.flatMap { source in
                    [
                        "cider-cli item get note \(source.owner.id) --json",
                        "cider-cli item context note \(source.owner.id) --json",
                    ]
                }
                + (count > 0 ? ["cider-cli capture review-queue --kind graph_candidate --json", "cider-cli capture review-queue --kind memory_candidate --json"] : [])
                + proposals.compactMap(\.crossTimeReconciliation).flatMap(\.safeNextCommands)
        )

        return JournalIntelligenceDailyReceipt(
            date: date,
            dataAsOf: dataDates.max(),
            statement: "Cider found \(count) \(noun) worth reviewing.",
            proposalCount: count,
            countsByCategory: counts,
            groups: groups,
            suppressedCount: suppressions.count,
            suppressions: suppressions,
            journalOwners: sources.map(\.owner),
            safeNextCommands: safeNextCommands
        )
    }

    private func journalSources(date: String) throws -> [JournalSource] {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, i.relative_path, i.created_at, i.updated_at, n.content
            FROM items i
            JOIN notes n ON n.item_id = i.id
            WHERE i.type = 'note'
            ORDER BY i.created_at ASC, i.id ASC;
            """)
        var sources: [JournalSource] = []
        while try stmt.step() {
            let title = stmt.string(at: 1)
            guard JournalTitle.parse(title)?.isoDate == date,
                  let id = UUID(uuidString: stmt.string(at: 0)) else { continue }
            let createdAt = DatabaseHelpers.decodeDate(stmt.double(at: 3))
            let updatedAt = DatabaseHelpers.decodeDate(stmt.double(at: 4))
            let relativePath = stmt.optionalString(at: 2) ?? ""
            let note = Note(
                id: id,
                title: title,
                content: stmt.optionalString(at: 5) ?? "",
                createdAt: createdAt,
                modifiedAt: updatedAt,
                relativePath: relativePath
            )
            let metadata = JournalLibraryReadModel.metadata(for: note, dateLabel: date)
            sources.append(JournalSource(
                owner: JournalIntelligenceOwner(
                    id: id.uuidString,
                    ref: "note:\(id.uuidString)",
                    title: title,
                    relativePath: relativePath.isEmpty ? nil : relativePath,
                    journalDate: date
                ),
                note: note,
                updatedAt: updatedAt,
                sections: metadata?.sections ?? []
            ))
        }
        return sources
    }

    private func captureSources(noteID: String) throws -> [String: CaptureSource] {
        let stmt = try database.prepare("""
            SELECT e.id, e.source_kind, e.surface, e.channel, e.source_text, e.metadata, e.created_at
            FROM owner_relations r
            JOIN capture_events e ON e.id = r.source_owner_id
            WHERE r.source_owner_type = 'capture_event'
              AND r.target_owner_type = 'note'
              AND r.target_owner_id = ?
              AND r.relation_type = 'produced_item'
            ORDER BY e.created_at ASC, e.id ASC;
            """)
        stmt.bind(noteID, at: 1)
        var captures: [String: CaptureSource] = [:]
        while try stmt.step() {
            let capture = CaptureSource(
                id: stmt.string(at: 0),
                sourceKind: stmt.string(at: 1),
                surface: stmt.optionalString(at: 2),
                channel: stmt.optionalString(at: 3),
                sourceText: stmt.optionalString(at: 4) ?? "",
                metadata: DatabaseHelpers.decodeJSON([String: String].self, from: stmt.optionalString(at: 5)) ?? [:],
                createdAt: DatabaseHelpers.decodeDate(stmt.double(at: 6))
            )
            captures[capture.id] = capture
        }
        return captures
    }

    private func candidateDraft(
        output: SecondBrainEnrichmentOutput,
        journal: JournalSource,
        captures: [String: CaptureSource]
    ) -> CandidateDraft {
        var reasons: [String] = []
        let family = output.kind
        let normalizedState = output.reviewState.lowercased()
        if !["suggested", "needs_review", "deferred"].contains(normalizedState) {
            reasons.append("terminal_review_state")
        }
        guard output.metadata["source_kind"]?.lowercased() == "journal" else {
            reasons.append("non_journal_candidate")
            return suppressedDraft(output, reasons: reasons)
        }
        guard let confidence = output.confidence else {
            reasons.append("missing_confidence")
            return suppressedDraft(output, reasons: reasons)
        }
        if confidence < minimumConfidence { reasons.append("low_confidence") }

        let classification: ClassifiedCandidate?
        if output.kind == SecondBrainGraphCandidateContract.outputKind {
            guard let candidate = try? SecondBrainGraphCandidateContract.validate(output) else {
                reasons.append("invalid_graph_candidate_contract")
                return suppressedDraft(output, reasons: reasons)
            }
            let quality = CiderReviewQueueService.candidateQualitySignal(
                mentionText: candidate.mentionText,
                sourceQuote: candidate.sourceQuote
            )
            if quality.level != "good" { reasons.append("low_quality_candidate") }
            classification = graphClassification(output: output, candidate: candidate)
        } else {
            classification = memoryClassification(output: output)
        }
        guard let classification else {
            reasons.append("unsupported_candidate_category")
            return suppressedDraft(output, reasons: reasons)
        }

        guard let captureEventID = output.metadata["capture_event_id"], !captureEventID.isEmpty,
              let capture = captures[captureEventID] else {
            reasons.append("missing_capture_event_provenance")
            return suppressedDraft(output, reasons: reasons)
        }
        guard capture.sourceKind.lowercased() == "journal" else {
            reasons.append("capture_event_is_not_journal")
            return suppressedDraft(output, reasons: reasons)
        }
        guard let source = exactSourceSpan(output: output, capture: capture) else {
            reasons.append("unverifiable_exact_source_span")
            return suppressedDraft(output, reasons: reasons)
        }
        guard let section = matchingSection(journal: journal, capture: capture, quote: source.quote) else {
            reasons.append("missing_capture_section")
            return suppressedDraft(output, reasons: reasons)
        }
        if correctedLater(output: output, capture: capture, source: source, graphCandidate: classification.graphCandidate) {
            reasons.append("corrected_later_in_capture")
        }
        if negatedGraphClaim(source.quote, candidate: classification.graphCandidate) {
            reasons.append("negated_graph_claim")
        }
        guard reasons.isEmpty else {
            return suppressedDraft(output, reasons: reasons, capturedAt: capture.createdAt)
        }

        let candidateRef = candidateRef(for: output)
        let journalTime = capture.metadata["time"] ?? output.metadata["journal_time"] ?? section.timestamp24Hour
        let proposal = JournalIntelligenceProposal(
            id: candidateRef,
            candidateRef: candidateRef,
            family: family,
            category: classification.category,
            candidateType: classification.candidateType,
            value: output.value,
            confidence: confidence,
            confidenceReason: classification.confidenceReason,
            proposalState: proposalState(reviewState: normalizedState),
            reviewState: normalizedState,
            truthBoundary: output.metadata["truth_boundary"] ?? "reviewable_candidate_not_truth",
            journalOwner: journal.owner,
            captureEvent: JournalIntelligenceCaptureEvent(
                id: capture.id,
                ref: "capture_event:\(capture.id)",
                sourceKind: capture.sourceKind,
                surface: capture.surface,
                channel: capture.channel,
                inputKind: capture.metadata["input"],
                journalTime: journalTime,
                capturedAt: capture.createdAt
            ),
            section: JournalIntelligenceSection(
                id: section.id,
                timestamp24Hour: section.timestamp24Hour,
                captureSource: section.captureSource,
                noteSpanStart: section.sourceSpan.location,
                noteSpanEnd: section.sourceSpan.location + section.sourceSpan.length
            ),
            source: source,
            safeNextCommands: candidateCommands(output: output, noteID: journal.owner.id)
        )
        return CandidateDraft(
            output: output,
            proposal: proposal,
            suppression: nil,
            capturedAt: capture.createdAt,
            stableKey: stableKey(output: output, classification: classification)
        )
    }

    private func graphClassification(
        output: SecondBrainEnrichmentOutput,
        candidate: SecondBrainGraphCandidateContract.Candidate
    ) -> ClassifiedCandidate? {
        let types = Set(candidate.objectTypeGuesses)
        let relations = Set(candidate.relationGuesses)
        let category: JournalIntelligenceCategory
        if !types.isDisjoint(with: [.person, .contact]) {
            category = .people
        } else if !types.isDisjoint(with: [.trip]) {
            category = .tripPlans
        } else if !types.isDisjoint(with: [.movie, .show, .media, .video, .book, .music, .file, .url, .recipe]) {
            category = .artifactsMedia
        } else if !relations.isDisjoint(with: [.likes, .likesDrink, .likesFood, .dislikes]) {
            category = .preferences
        } else if !types.isDisjoint(with: [.place, .restaurant]) || relations.contains(.visited) {
            category = .places
        } else if !relations.isDisjoint(with: [.watched, .read, .listenedTo, .cooked, .ate, .drank]) {
            category = .activities
        } else if types.contains(.reminder) {
            category = .tasks
        } else if relations.contains(.wants) {
            category = .commitments
        } else {
            return nil
        }
        let candidateType = candidate.objectTypeGuesses.first?.rawValue
            ?? candidate.relationGuesses.first?.rawValue
            ?? candidate.kind.rawValue
        return ClassifiedCandidate(
            category: category,
            candidateType: candidateType,
            confidenceReason: output.metadata[SecondBrainGraphCandidateContract.MetadataKey.confidenceReason]
                ?? "The production Journal graph extractor emitted a concrete source-backed candidate.",
            graphCandidate: candidate
        )
    }

    private func memoryClassification(output: SecondBrainEnrichmentOutput) -> ClassifiedCandidate? {
        let kind = (output.metadata["memory_kind"] ?? output.metadata["candidate_kind"] ?? "memory")
            .lowercased()
        let category: JournalIntelligenceCategory
        if containsAny(kind, ["relationship", "person", "people", "contact"]) {
            category = .people
        } else if containsAny(kind, ["place", "location", "restaurant"]) {
            category = .places
        } else if containsAny(kind, ["preference", "liked", "disliked", "favorite"]) {
            category = .preferences
        } else if containsAny(kind, ["commitment", "promise", "schedule_plan", "work_schedule"]) {
            category = .commitments
        } else if containsAny(kind, ["task", "todo", "reminder", "follow_up", "action_intent"]) {
            category = .tasks
        } else if containsAny(kind, ["artifact", "media", "movie", "show", "book", "file", "url", "recipe"]) {
            category = .artifactsMedia
        } else if containsAny(kind, ["trip", "travel", "future_planning", "tradition"]) {
            category = .tripPlans
        } else if containsAny(kind, ["activity", "routine", "medical_event", "work_incident", "food_routine", "work_context"]) {
            category = .activities
        } else if containsAny(kind, ["memory", "pattern", "lesson", "project_context", "fact", "spending", "payroll", "gift"]) {
            category = .durableMemory
        } else {
            return nil
        }
        return ClassifiedCandidate(
            category: category,
            candidateType: kind,
            confidenceReason: output.metadata["confidence_reason"]
                ?? "The production Journal memory extractor emitted a source-backed \(kind.replacingOccurrences(of: "_", with: " ")) candidate.",
            graphCandidate: nil
        )
    }

    private func exactSourceSpan(
        output: SecondBrainEnrichmentOutput,
        capture: CaptureSource
    ) -> JournalIntelligenceSourceSpan? {
        let quote = output.metadata["source_quote"] ?? output.evidence
        guard !quote.isEmpty, !capture.sourceText.isEmpty else { return nil }
        if let start = output.metadata["source_span_start"].flatMap(Int.init),
           let end = output.metadata["source_span_end"].flatMap(Int.init),
           let exact = substring(capture.sourceText, start: start, end: end),
           exact == quote {
            return JournalIntelligenceSourceSpan(
                coordinateSpace: "capture_event.source_text",
                spanStart: start,
                spanEnd: end,
                quote: quote
            )
        }

        let ranges = exactRanges(of: quote, in: capture.sourceText)
        guard ranges.count == 1, let range = ranges.first else { return nil }
        return JournalIntelligenceSourceSpan(
            coordinateSpace: "capture_event.source_text",
            spanStart: range.start,
            spanEnd: range.end,
            quote: quote
        )
    }

    private func matchingSection(
        journal: JournalSource,
        capture: CaptureSource,
        quote: String
    ) -> JournalEntrySection? {
        let time = capture.metadata["time"]
        let candidates = journal.sections.filter { section in
            time == nil || section.timestamp24Hour == time
        }
        if let exact = candidates.first(where: { section in
            section.sourceSnippet.contains(capture.sourceText) || section.sourceSnippet.contains(quote)
        }) {
            return exact
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

    private func correctedLater(
        output: SecondBrainEnrichmentOutput,
        capture: CaptureSource,
        source: JournalIntelligenceSourceSpan,
        graphCandidate: SecondBrainGraphCandidateContract.Candidate?
    ) -> Bool {
        guard let suffix = substring(capture.sourceText, start: source.spanEnd, end: capture.sourceText.count) else {
            return false
        }
        let lower = suffix.lowercased()
        guard lower.contains("correction") || lower.contains("actually") || lower.contains("rather") else {
            return false
        }
        let subject = (graphCandidate?.mentionText ?? output.value).lowercased()
        let meaningfulTokens = subject
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 }
        guard meaningfulTokens.contains(where: lower.contains) else { return false }
        return lower.range(of: #"\b(?:did\s+not|didn't|not|never|instead)\b"#, options: .regularExpression) != nil
    }

    private func negatedGraphClaim(
        _ quote: String,
        candidate: SecondBrainGraphCandidateContract.Candidate?
    ) -> Bool {
        guard let candidate else { return false }
        let claimRelations: Set<SecondBrainGraphCandidateContract.RelationType> = [
            .visited, .watched, .read, .listenedTo, .likes, .likesDrink, .likesFood,
            .ate, .drank, .bought, .cooked, .owns, .wants,
        ]
        guard !claimRelations.isDisjoint(with: Set(candidate.relationGuesses)) else { return false }
        return quote.lowercased().range(
            of: #"\b(?:did\s+not|didn't|do\s+not|don't|never|not\s+going|not\s+planning)\b"#,
            options: .regularExpression
        ) != nil
    }

    private func stableKey(
        output: SecondBrainEnrichmentOutput,
        classification: ClassifiedCandidate
    ) -> String {
        let relation = classification.graphCandidate?.relationGuesses.first?.rawValue ?? ""
        return [
            classification.category.rawValue,
            classification.candidateType,
            relation,
            normalized(output.normalizedValue.isEmpty ? output.value : output.normalizedValue),
        ].joined(separator: "|")
    }

    private func suppressedDraft(
        _ output: SecondBrainEnrichmentOutput,
        reasons: [String],
        capturedAt: Date? = nil
    ) -> CandidateDraft {
        CandidateDraft(
            output: output,
            proposal: nil,
            suppression: suppression(output: output, reasonCodes: orderedUnique(reasons)),
            capturedAt: capturedAt,
            stableKey: nil
        )
    }

    private func suppression(
        output: SecondBrainEnrichmentOutput,
        reasonCodes: [String]
    ) -> JournalIntelligenceSuppression {
        JournalIntelligenceSuppression(
            candidateRef: candidateRef(for: output),
            family: output.kind,
            reviewState: output.reviewState,
            value: output.value,
            sourceQuote: output.metadata["source_quote"] ?? output.evidence,
            reasonCodes: reasonCodes,
            explanation: reasonCodes.map(suppressionExplanation).joined(separator: " ")
        )
    }

    private func suppressionExplanation(_ reason: String) -> String {
        switch reason {
        case "terminal_review_state": return "Candidate is already accepted, rejected, hidden, or superseded and is not active review work."
        case "non_journal_candidate": return "Candidate is not explicitly sourced from Journal capture."
        case "missing_confidence": return "Candidate has no confidence score, so the receipt fails closed."
        case "low_confidence": return "Candidate confidence is below the receipt's precision threshold."
        case "low_quality_candidate": return "Candidate wording is vague, fragmentary, or otherwise fails the existing Review Queue quality gate."
        case "invalid_graph_candidate_contract": return "Candidate does not satisfy the canonical graph candidate contract."
        case "unsupported_candidate_category": return "Candidate cannot be mapped to a stable useful Journal Intelligence category."
        case "missing_capture_event_provenance": return "Candidate is not linked to a verified Journal capture event for this note."
        case "capture_event_is_not_journal": return "Linked capture event is not a Journal capture."
        case "unverifiable_exact_source_span": return "Candidate quote cannot be resolved to one exact span in capture_event.source_text."
        case "missing_capture_section": return "Candidate capture cannot be matched to one timestamped Journal section."
        case "corrected_later_in_capture": return "A later correction in the same capture contradicts this candidate."
        case "negated_graph_claim": return "The source quote negates the inferred graph relation."
        case "duplicate_within_day": return "An equivalent higher-priority proposal is already present in this day's receipt."
        default: return "Candidate was suppressed by the precision-first Journal Intelligence gate (\(reason))."
        }
    }

    private func candidateCommands(output: SecondBrainEnrichmentOutput, noteID: String) -> [String] {
        let id = output.id
        let inspect = output.kind == "memory_candidate"
            ? "cider-cli item memory-facts inspect \(id) --json"
            : "cider-cli item graph-candidate \(id) --json"
        return [
            inspect,
            "cider-cli item context note \(noteID) --json",
            "cider-cli review approve \(id) --json",
            "cider-cli review reject \(id) --reason <reason> --json",
            "cider-cli review defer \(id) --reason <reason> --json",
        ]
    }

    private func candidateRef(for output: SecondBrainEnrichmentOutput) -> String {
        "\(output.kind == "memory_candidate" ? "memory_candidate" : "graph_candidate"):\(output.id)"
    }

    private func proposalState(reviewState: String) -> String {
        switch reviewState {
        case "accepted": return "accepted"
        case "rejected": return "rejected"
        case "deferred": return "deferred"
        default: return "proposed"
        }
    }

    private func draftOrder(_ lhs: CandidateDraft, _ rhs: CandidateDraft) -> Bool {
        switch (lhs.capturedAt, rhs.capturedAt) {
        case let (left?, right?) where left != right: return left < right
        case (nil, _?): return false
        case (_?, nil): return true
        default:
            let leftConfidence = lhs.output.confidence ?? -1
            let rightConfidence = rhs.output.confidence ?? -1
            if leftConfidence != rightConfidence { return leftConfidence > rightConfidence }
            return candidateRef(for: lhs.output) < candidateRef(for: rhs.output)
        }
    }

    private func proposalOrder(_ lhs: JournalIntelligenceProposal, _ rhs: JournalIntelligenceProposal) -> Bool {
        let leftRank = JournalIntelligenceCategory.allCases.firstIndex(of: lhs.category) ?? Int.max
        let rightRank = JournalIntelligenceCategory.allCases.firstIndex(of: rhs.category) ?? Int.max
        if leftRank != rightRank { return leftRank < rightRank }
        if lhs.captureEvent.capturedAt != rhs.captureEvent.capturedAt {
            return lhs.captureEvent.capturedAt < rhs.captureEvent.capturedAt
        }
        if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
        return lhs.candidateRef < rhs.candidateRef
    }

    private func exactRanges(of needle: String, in haystack: String) -> [(start: Int, end: Int)] {
        guard !needle.isEmpty else { return [] }
        var ranges: [(Int, Int)] = []
        var searchStart = haystack.startIndex
        while searchStart < haystack.endIndex,
              let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
            ranges.append((
                haystack.distance(from: haystack.startIndex, to: range.lowerBound),
                haystack.distance(from: haystack.startIndex, to: range.upperBound)
            ))
            searchStart = range.upperBound
        }
        return ranges
    }

    private func substring(_ text: String, start: Int, end: Int) -> String? {
        guard start >= 0, end >= start, end <= text.count else { return nil }
        let lower = text.index(text.startIndex, offsetBy: start)
        let upper = text.index(text.startIndex, offsetBy: end)
        return String(text[lower..<upper])
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains(where: value.contains)
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
