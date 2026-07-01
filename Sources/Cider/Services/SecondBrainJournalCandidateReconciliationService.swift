import Foundation

struct SecondBrainJournalCandidateReconciliationCandidate: Codable, Equatable {
    var candidateID: String
    var candidateRef: String
    var kind: String
    var value: String
    var evidence: String
    var previousReviewState: String
    var proposedReviewState: String
    var reasonCodes: [String]
    var sourceRefs: [String]
    var sourceEvidenceRef: String?
}

struct SecondBrainJournalCandidateReconciliationReport: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var readOnly: Bool
    var changed: Bool
    var totalStoredCandidateCount: Int
    var currentExtractionCandidateCount: Int
    var candidateCount: Int
    var candidates: [SecondBrainJournalCandidateReconciliationCandidate]
    var appliedCandidateIDs: [String]
    var truthBoundary: String
    var safeNextCommands: [String]
}

@MainActor
final class SecondBrainJournalCandidateReconciliationService {
    enum ReconciliationError: LocalizedError, Equatable {
        case noSelectedCandidates
        case selectedCandidateNotDiagnosed(String)

        var errorDescription: String? {
            switch self {
            case .noSelectedCandidates:
                return "Apply requires at least one explicit candidate ID."
            case .selectedCandidateNotDiagnosed(let id):
                return "Candidate '\(id)' was not diagnosed as safely supersedable for this journal source."
            }
        }
    }

    private let outputService: SecondBrainEnrichmentOutputService

    init(database: CiderDatabase = .shared) {
        self.outputService = SecondBrainEnrichmentOutputService(database: database)
    }

    func diagnose(
        owner: SecondBrainOwnerRef,
        rawContent: String,
        date: String? = nil,
        time: String? = nil,
        limit: Int = 100
    ) throws -> SecondBrainJournalCandidateReconciliationReport {
        try makeReport(
            owner: owner,
            rawContent: rawContent,
            date: date,
            time: time,
            selectedCandidateIDs: [],
            apply: false,
            actor: "system",
            reason: nil,
            limit: limit
        )
    }

    func apply(
        owner: SecondBrainOwnerRef,
        rawContent: String,
        selectedCandidateIDs: Set<String>,
        actor: String,
        reason: String?,
        date: String? = nil,
        time: String? = nil,
        limit: Int = 100
    ) throws -> SecondBrainJournalCandidateReconciliationReport {
        guard !selectedCandidateIDs.isEmpty else { throw ReconciliationError.noSelectedCandidates }
        return try makeReport(
            owner: owner,
            rawContent: rawContent,
            date: date,
            time: time,
            selectedCandidateIDs: selectedCandidateIDs,
            apply: true,
            actor: actor,
            reason: reason,
            limit: limit
        )
    }

    private func makeReport(
        owner: SecondBrainOwnerRef,
        rawContent: String,
        date: String?,
        time: String?,
        selectedCandidateIDs: Set<String>,
        apply: Bool,
        actor: String,
        reason: String?,
        limit: Int
    ) throws -> SecondBrainJournalCandidateReconciliationReport {
        let stored = try storedJournalCandidates(owner: owner)
        let current = SecondBrainJournalGraphCandidateExtractor().extract(
            sourceOwner: owner,
            rawContent: rawContent,
            date: date,
            time: time
        ).outputs
        let currentKeys = Set(current.map(candidateStableKey))
        let currentValues = Set(current.map { normalized($0.value) })
        let currentEvidence = Set(current.map { normalized($0.evidence) })

        let diagnosed = stored.compactMap { output -> SecondBrainJournalCandidateReconciliationCandidate? in
            guard isReviewable(output.reviewState) else { return nil }
            let reasons = reconciliationReasons(
                for: output,
                currentKeys: currentKeys,
                currentValues: currentValues,
                currentEvidence: currentEvidence
            )
            guard reasons.contains(where: isNoiseReason) else { return nil }
            return candidateView(for: output, reasonCodes: reasons)
        }
        .prefix(max(0, limit))
        .map { $0 }

        var applied: [String] = []
        if apply {
            let diagnosedByID = Dictionary(uniqueKeysWithValues: diagnosed.map { ($0.candidateID, $0) })
            for id in selectedCandidateIDs.sorted() {
                guard diagnosedByID[id] != nil else { throw ReconciliationError.selectedCandidateNotDiagnosed(id) }
                var output = try requiredOutput(id: id)
                output.reviewState = "superseded"
                output.updatedAt = Date()
                output.metadata["reconciliation_state"] = "superseded"
                output.metadata["reconciliation_reason"] = trimmed(reason) ?? "Superseded by current journal candidate extraction."
                output.metadata["reconciled_at"] = ISO8601DateFormatter().string(from: output.updatedAt)
                output.metadata["reconciled_by"] = trimmed(actor) ?? "system"
                output.metadata["review_boundary"] = "reviewable_candidate_not_truth"
                output.metadata["accepted_as_truth"] = "false"
                output.metadata["superseded_by"] = "current_journal_candidate_extraction"
                output.metadata["supersedes_ref"] = candidateRef(for: output)
                try outputService.record(output)
                applied.append(id)
            }
        }

        return SecondBrainJournalCandidateReconciliationReport(
            owner: owner,
            readOnly: !apply,
            changed: !applied.isEmpty,
            totalStoredCandidateCount: stored.count,
            currentExtractionCandidateCount: current.count,
            candidateCount: diagnosed.count,
            candidates: diagnosed,
            appliedCandidateIDs: applied,
            truthBoundary: "reviewable_candidate_not_truth",
            safeNextCommands: safeNextCommands(owner: owner, candidates: diagnosed)
        )
    }

    private func storedJournalCandidates(owner: SecondBrainOwnerRef) throws -> [SecondBrainEnrichmentOutput] {
        try outputService.outputs(for: owner).filter { output in
            (output.kind == SecondBrainGraphCandidateContract.outputKind || output.kind == "memory_candidate")
                && (output.metadata["source_kind"] == "journal" || output.source.localizedCaseInsensitiveContains("journal"))
        }
    }

    private func reconciliationReasons(
        for output: SecondBrainEnrichmentOutput,
        currentKeys: Set<String>,
        currentValues: Set<String>,
        currentEvidence: Set<String>
    ) -> [String] {
        var reasons: [String] = []
        let stableKey = candidateStableKey(output)
        let normalizedValue = normalized(output.value)
        let normalizedEvidence = normalized(output.evidence)
        if !currentKeys.contains(stableKey)
            && !currentValues.contains(normalizedValue)
            && !currentEvidence.contains(normalizedEvidence) {
            reasons.append("not_emitted_by_current_extractor")
        }
        let text = "\(output.value) \(output.evidence)"
        if isNoisyClauseSpan(text) { reasons.append("noisy_clause_span") }
        if isEpisodeCountSpan(text) { reasons.append("episode_count_span") }
        if output.confidence.map({ $0 < 0.4 }) == true { reasons.append("low_confidence_stored_candidate") }
        return reasons
    }

    private func candidateView(
        for output: SecondBrainEnrichmentOutput,
        reasonCodes: [String]
    ) -> SecondBrainJournalCandidateReconciliationCandidate {
        var sourceRefs = [output.owner.canonicalRef, candidateRef(for: output)]
        if let sourceEvidenceRef = output.metadata["source_evidence_ref"] {
            sourceRefs.append(sourceEvidenceRef)
        }
        return SecondBrainJournalCandidateReconciliationCandidate(
            candidateID: output.id,
            candidateRef: candidateRef(for: output),
            kind: output.kind,
            value: output.value,
            evidence: output.evidence,
            previousReviewState: output.reviewState,
            proposedReviewState: "superseded",
            reasonCodes: reasonCodes,
            sourceRefs: Array(NSOrderedSet(array: sourceRefs)) as? [String] ?? sourceRefs,
            sourceEvidenceRef: output.metadata["source_evidence_ref"]
        )
    }

    private func requiredOutput(id: String) throws -> SecondBrainEnrichmentOutput {
        if let output = try outputService.output(id: id) { return output }
        throw ReconciliationError.selectedCandidateNotDiagnosed(id)
    }

    private func candidateStableKey(_ output: SecondBrainEnrichmentOutput) -> String {
        [
            output.kind,
            normalized(output.metadata["memory_key"] ?? ""),
            normalized(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.candidateKind] ?? ""),
            normalized(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.mentionText] ?? output.value),
            normalized(output.evidence),
        ].joined(separator: "|")
    }

    private func candidateRef(for output: SecondBrainEnrichmentOutput) -> String {
        SecondBrainReviewLifecycleService.candidateRef(for: output) ?? "enrichment_output:\(output.id)"
    }

    private func isReviewable(_ state: String) -> Bool {
        ["suggested", "needs_review", "deferred"].contains(state.lowercased())
    }

    private func isNoiseReason(_ reason: String) -> Bool {
        ["noisy_clause_span", "episode_count_span", "low_confidence_stored_candidate"].contains(reason)
    }

    private func isNoisyClauseSpan(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains(";")
            || lower.contains("random things")
            || (lower.contains("money seemed") && lower.contains("gift"))
            || lower.contains("guessing a gift")
    }

    private func isEpisodeCountSpan(_ text: String) -> Bool {
        text.range(of: #"(?i)\b(?:through|at least)\s+(?:\w+\s+)?\d+\s+episodes?\b"#, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func safeNextCommands(
        owner: SecondBrainOwnerRef,
        candidates: [SecondBrainJournalCandidateReconciliationCandidate]
    ) -> [String] {
        var commands = [
            "cider-cli item journal-candidate-reconcile \(owner.ownerType) \(owner.ownerID) --dry-run --json",
        ]
        for candidate in candidates.prefix(5) {
            if candidate.kind == SecondBrainGraphCandidateContract.outputKind {
                commands.append("cider-cli item graph-candidate \(candidate.candidateID) --json")
            } else if candidate.kind == "memory_candidate" {
                commands.append("cider-cli item memory-facts inspect \(candidate.candidateID) --json")
            }
        }
        return commands
    }
}
