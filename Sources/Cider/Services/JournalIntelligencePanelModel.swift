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

enum JournalIntelligenceDayReviewHealth: Equatable {
    case loading
    case ready
    case empty
    case suppressed
    case partial
    case stale
    case unavailable

    var message: String {
        switch self {
        case .loading:
            return "Checking this Journal day for source-backed suggestions…"
        case .ready:
            return "Suggestions are ready to review. Nothing here is accepted Cider truth."
        case .empty:
            return "Nothing is ready for review from this Journal day."
        case .suppressed:
            return "Cider held back uncertain suggestions instead of presenting them as reliable."
        case .partial:
            return "The comparison was partial. Cider will not claim an item is new when the scan is incomplete."
        case .stale:
            return "Journal Review may be stale. Cider will not claim novelty until the source-backed scan catches up."
        case .unavailable:
            return "Journal Review is unavailable right now. Your Journal and Cider truth are unchanged."
        }
    }
}

enum JournalIntelligenceSourceNavigationPrecision: Equatable {
    case exactCaptureMoment
    case sourceEntry
    case evidenceOnly
}

struct JournalIntelligenceSourceNavigation: Equatable {
    var captureCardID: String?
    var sectionID: String
    var precision: JournalIntelligenceSourceNavigationPrecision
    var actionLabel: String
    var boundaryCopy: String
}

struct JournalIntelligenceReviewSource: Equatable {
    var timestamp24Hour: String
    var typeLabel: String
    var channelLabel: String
    var sourceKind: String
    var coordinateSpace: String
    var spanStart: Int
    var spanEnd: Int
    var quote: String
}

struct JournalIntelligenceReviewLikelyMatch: Equatable, Identifiable {
    var id: String { canonicalRef }
    var canonicalRef: String
    var kindLabel: String
    var label: String
    var confidence: Double
}

struct JournalIntelligenceReviewReconciliation: Equatable {
    var status: JournalIntelligenceReconciliationStatus?
    var classification: JournalIntelligenceReconciliationClassification?
    var label: String
    var explanation: String
    var likelyMatches: [JournalIntelligenceReviewLikelyMatch]
    var isIncomplete: Bool

    static func make(
        reconciliation: JournalIntelligenceCrossTimeReconciliation?,
        receiptIsStale: Bool
    ) -> JournalIntelligenceReviewReconciliation {
        guard let reconciliation else {
            return JournalIntelligenceReviewReconciliation(
                status: nil,
                classification: nil,
                label: "Comparison unavailable",
                explanation: "Cider has not completed a bounded comparison for this suggestion, so it is not claiming a match or novelty.",
                likelyMatches: [],
                isIncomplete: true
            )
        }

        let likelyMatches = reconciliation.likelyMatches.map {
            JournalIntelligenceReviewLikelyMatch(
                canonicalRef: $0.canonicalRef,
                kindLabel: friendlyKind($0.canonicalKind),
                label: $0.canonicalLabel,
                confidence: $0.confidence
            )
        }
        let scanIsIncomplete = reconciliation.canonicalFamilyScans.contains { $0.truncated || !$0.complete }

        if receiptIsStale, reconciliation.classification == .genuinelyNew {
            return JournalIntelligenceReviewReconciliation(
                status: reconciliation.status,
                classification: reconciliation.classification,
                label: "Novelty not confirmed",
                explanation: "This review may be stale, so Cider is not claiming this suggestion is genuinely new.",
                likelyMatches: likelyMatches,
                isIncomplete: true
            )
        }

        let label: String
        let explanation: String
        switch reconciliation.status {
        case .ambiguous:
            label = "Several possible matches"
            explanation = reconciliation.explanation
        case .classificationWithheld:
            label = "Comparison incomplete"
            explanation = "The bounded comparison was partial, so Cider does not claim this suggestion is new. \(reconciliation.explanation)"
        case .unsupported:
            label = "Not compared yet"
            explanation = reconciliation.explanation
        case .matched:
            switch reconciliation.classification {
            case .repeated:
                label = "Likely repeated mention"
            case .newUpdate:
                label = "Likely new update"
            case .correctionOrConflict:
                label = "Possible correction or conflict"
            case .genuinelyNew:
                label = "Possible new information"
            case nil:
                label = "Likely existing match"
            }
            explanation = reconciliation.explanation
        case .noMatch:
            if reconciliation.classification == .genuinelyNew, !scanIsIncomplete {
                label = "No likely existing match"
                explanation = reconciliation.explanation
            } else {
                label = "No match confirmed"
                explanation = "Cider did not confirm a match, but it is not claiming novelty from an incomplete comparison. \(reconciliation.explanation)"
            }
        }

        return JournalIntelligenceReviewReconciliation(
            status: reconciliation.status,
            classification: reconciliation.classification,
            label: label,
            explanation: explanation,
            likelyMatches: likelyMatches,
            isIncomplete: scanIsIncomplete || reconciliation.status == .classificationWithheld
        )
    }

    private static func friendlyKind(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }
}

struct JournalIntelligenceReviewProposal: Equatable, Identifiable {
    var id: String { candidateRef }
    var candidateRef: String
    var family: String
    var category: JournalIntelligenceCategory
    var value: String
    var candidateType: String
    var confidenceReason: String
    var reviewState: String
    var truthBoundary: String
    var candidateUpdatedAt: Date
    var statusLabel: String
    var sectionID: String
    var source: JournalIntelligenceReviewSource
    var sourceNavigation: JournalIntelligenceSourceNavigation
    var reconciliation: JournalIntelligenceReviewReconciliation
    var actions: JournalIntelligenceReviewActionSet
}

struct JournalIntelligenceReviewGroup: Equatable, Identifiable {
    var id: String { category.rawValue }
    var category: JournalIntelligenceCategory
    var label: String
    var proposals: [JournalIntelligenceReviewProposal]
}

struct JournalIntelligenceDayReviewModel: Equatable {
    var date: String
    var statement: String
    var health: JournalIntelligenceDayReviewHealth
    var healthMessage: String
    var truthBoundary: String
    var truthBoundaryCopy: String
    var suppressedCount: Int
    var groups: [JournalIntelligenceReviewGroup]
    var reviewedGroups: [JournalIntelligenceReviewGroup]

    func proposal(candidateRef: String) -> JournalIntelligenceReviewProposal? {
        groups.flatMap(\.proposals).first { $0.candidateRef == candidateRef }
    }

    func reviewedProposal(candidateRef: String) -> JournalIntelligenceReviewProposal? {
        reviewedGroups.flatMap(\.proposals).first { $0.candidateRef == candidateRef }
    }

    static func make(
        receipt: JournalIntelligenceDailyReceipt,
        day: JournalLibraryDay,
        actionSets: [String: JournalIntelligenceReviewActionSet] = [:]
    ) -> JournalIntelligenceDayReviewModel {
        let latestSourceUpdate = day.sourceEntries.map(\.note.modifiedAt).max()
        let isStale = latestSourceUpdate.map { latest in
            guard let dataAsOf = receipt.dataAsOf else { return true }
            return dataAsOf < latest
        } ?? false

        var seenCandidateRefs = Set<String>()
        let receiptProposals = Dictionary(
            grouping: receipt.groups.flatMap(\.proposals),
            by: \.category
        )
        let groups = JournalIntelligenceCategory.allCases.compactMap { category -> JournalIntelligenceReviewGroup? in
            let proposals = (receiptProposals[category] ?? []).compactMap { proposal -> JournalIntelligenceReviewProposal? in
                guard seenCandidateRefs.insert(proposal.candidateRef).inserted else { return nil }
                return presentationProposal(
                    proposal,
                    day: day,
                    receiptIsStale: isStale,
                    actionSet: actionSets[proposal.candidateRef],
                    reviewed: false
                )
            }
            guard !proposals.isEmpty else { return nil }
            return JournalIntelligenceReviewGroup(
                category: category,
                label: friendlyCategoryLabel(category),
                proposals: proposals
            )
        }
        let reviewedGroups = JournalIntelligenceCategory.allCases.compactMap { category -> JournalIntelligenceReviewGroup? in
            let proposals = receipt.reviewedGroups
                .first { $0.category == category }?
                .proposals
                .map { proposal in
                    presentationProposal(
                        proposal,
                        day: day,
                        receiptIsStale: false,
                        actionSet: actionSets[proposal.candidateRef],
                        reviewed: true
                    )
                } ?? []
            guard !proposals.isEmpty else { return nil }
            return JournalIntelligenceReviewGroup(
                category: category,
                label: friendlyCategoryLabel(category),
                proposals: proposals
            )
        }
        let proposalCount = groups.reduce(0) { $0 + $1.proposals.count }
        let isPartial = groups.flatMap(\.proposals).contains { $0.reconciliation.isIncomplete }
        let health: JournalIntelligenceDayReviewHealth
        if receipt.journalOwners.isEmpty, !day.sourceEntries.isEmpty {
            health = .unavailable
        } else if isStale {
            health = .stale
        } else if isPartial {
            health = .partial
        } else if proposalCount > 0 {
            health = .ready
        } else if receipt.suppressedCount > 0 {
            health = .suppressed
        } else {
            health = .empty
        }
        let noun = proposalCount == 1 ? "thing" : "things"

        return JournalIntelligenceDayReviewModel(
            date: receipt.date,
            statement: "Cider found \(proposalCount) \(noun) worth reviewing.",
            health: health,
            healthMessage: health.message,
            truthBoundary: "reviewable_candidate_not_truth",
            truthBoundaryCopy: "These are reviewable suggestions, not accepted Cider truth. Displaying them does not create, change, or approve anything.",
            suppressedCount: receipt.suppressedCount,
            groups: groups,
            reviewedGroups: reviewedGroups
        )
    }

    private static func presentationProposal(
        _ proposal: JournalIntelligenceProposal,
        day: JournalLibraryDay,
        receiptIsStale: Bool,
        actionSet: JournalIntelligenceReviewActionSet?,
        reviewed: Bool
    ) -> JournalIntelligenceReviewProposal {
        let fallbackActions = reviewed
            ? JournalIntelligenceReviewActionSet.reviewed(family: proposal.family, reviewState: proposal.reviewState)
            : JournalIntelligenceReviewActionSet.unsupported(
                family: proposal.family,
                reviewState: proposal.reviewState,
                guidance: "Refresh Journal Review to verify the canonical action contract."
            )
        let resolvedActions = receiptIsStale
            ? (actionSet ?? fallbackActions).blocked("Journal Review is stale. Refresh before taking an action.")
            : (actionSet ?? fallbackActions)
        return JournalIntelligenceReviewProposal(
            candidateRef: proposal.candidateRef,
            family: proposal.family,
            category: proposal.category,
            value: proposal.value,
            candidateType: friendlyCandidateType(proposal.candidateType),
            confidenceReason: proposal.confidenceReason,
            reviewState: proposal.reviewState,
            truthBoundary: proposal.truthBoundary,
            candidateUpdatedAt: proposal.candidateUpdatedAt,
            statusLabel: statusLabel(family: proposal.family, reviewState: proposal.reviewState),
            sectionID: proposal.section.id,
            source: JournalIntelligenceReviewSource(
                timestamp24Hour: proposal.section.timestamp24Hour,
                typeLabel: sourceTypeLabel(proposal.captureEvent),
                channelLabel: sourceChannelLabel(proposal.captureEvent),
                sourceKind: proposal.captureEvent.sourceKind,
                coordinateSpace: proposal.source.coordinateSpace,
                spanStart: proposal.source.spanStart,
                spanEnd: proposal.source.spanEnd,
                quote: proposal.source.quote
            ),
            sourceNavigation: sourceNavigation(for: proposal, day: day),
            reconciliation: JournalIntelligenceReviewReconciliation.make(
                reconciliation: proposal.crossTimeReconciliation,
                receiptIsStale: receiptIsStale
            ),
            actions: resolvedActions
        )
    }

    private static func statusLabel(family: String, reviewState: String) -> String {
        switch reviewState {
        case "accepted":
            return family == "memory_candidate"
                ? "Approved as accepted memory truth"
                : "Approved as an accepted graph link"
        case "rejected":
            return "Rejected, not accepted truth"
        case "deferred":
            return "Deferred suggestion, not accepted truth"
        default:
            return "Suggestion, not accepted truth"
        }
    }

    private static func sourceNavigation(
        for proposal: JournalIntelligenceProposal,
        day: JournalLibraryDay
    ) -> JournalIntelligenceSourceNavigation {
        if let exactCard = day.captureCards.first(where: {
            $0.id == proposal.section.id
                && $0.sourceEntry.note.id.uuidString == proposal.journalOwner.id
        }) {
            return JournalIntelligenceSourceNavigation(
                captureCardID: exactCard.id,
                sectionID: proposal.section.id,
                precision: .exactCaptureMoment,
                actionLabel: "Show exact capture",
                boundaryCopy: "Opens the exact timestamped capture in this Journal day."
            )
        }
        if let sourceEntryCard = day.captureCards.first(where: {
            $0.sourceEntry.note.id.uuidString == proposal.journalOwner.id
        }) {
            return JournalIntelligenceSourceNavigation(
                captureCardID: sourceEntryCard.id,
                sectionID: proposal.section.id,
                precision: .sourceEntry,
                actionLabel: "Show source entry",
                boundaryCopy: "This legacy day can navigate to the preserved source entry, not a narrower capture card."
            )
        }
        return JournalIntelligenceSourceNavigation(
            captureCardID: nil,
            sectionID: proposal.section.id,
            precision: .evidenceOnly,
            actionLabel: "Source shown here",
            boundaryCopy: "Exact capture-card navigation is not available for this entry yet; the timestamp and exact source quote remain visible here."
        )
    }

    private static func friendlyCategoryLabel(_ category: JournalIntelligenceCategory) -> String {
        switch category {
        case .people: return "People updates"
        case .places: return "Places"
        case .activities: return "Activities"
        case .preferences: return "Preferences"
        case .commitments: return "Commitments"
        case .tasks: return "Tasks"
        case .artifactsMedia: return "Artifacts & media"
        case .tripPlans: return "Trip plans"
        case .durableMemory: return "Memories"
        }
    }

    private static func friendlyCandidateType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }

    private static func sourceTypeLabel(_ event: JournalIntelligenceCaptureEvent) -> String {
        let raw = [event.inputKind, event.surface, event.channel, event.sourceKind]
            .compactMap { $0?.localizedLowercase }
            .joined(separator: " ")
        if raw.contains("voice") || raw.contains("audio") { return "Voice transcript" }
        if raw.contains("photo") || raw.contains("image") { return "Photo capture" }
        if raw.contains("file") { return "File capture" }
        if raw.contains("link") || raw.contains("url") { return "Link capture" }
        return "Text capture"
    }

    private static func sourceChannelLabel(_ event: JournalIntelligenceCaptureEvent) -> String {
        let raw = (event.channel ?? event.surface ?? event.sourceKind)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "Cider" }
        let normalized = raw.replacingOccurrences(of: "_", with: " ")
        if normalized.localizedLowercase == "cider-cli text" { return "Cider CLI text" }
        return normalized.split(separator: " ").map { word in
            switch word.localizedLowercase {
            case "cli": return "CLI"
            case "ios": return "iOS"
            case "macos": return "macOS"
            default: return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
        }.joined(separator: " ")
    }
}

enum JournalIntelligenceDayReviewLoadState: Equatable {
    case loading
    case ready(JournalIntelligenceDayReviewModel)
    case unavailable(String)
}

@MainActor
final class JournalIntelligenceDayReviewService {
    private let receiptService: JournalIntelligenceDailyReceiptService
    private let actionService: JournalIntelligenceReviewActionService

    init(database: CiderDatabase = .shared) {
        receiptService = JournalIntelligenceDailyReceiptService(database: database)
        actionService = JournalIntelligenceReviewActionService(database: database)
    }

    func review(for day: JournalLibraryDay) throws -> JournalIntelligenceDayReviewModel {
        let receipt = try receiptService.receipt(date: day.dateLabel)
        let candidateRefs = (receipt.groups + receipt.reviewedGroups)
            .flatMap(\.proposals)
            .map(\.candidateRef)
        let actionSets = try actionService.actionSets(candidateRefs: candidateRefs)
        return JournalIntelligenceDayReviewModel.make(receipt: receipt, day: day, actionSets: actionSets)
    }
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
