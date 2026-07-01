import Foundation

struct SecondBrainJournalCandidateReconciliationCandidate: Codable, Equatable {
    var candidateID: String
    var candidateRef: String
    var kind: String
    var value: String
    var evidence: String
    var metadata: [String: String]
    var previousReviewState: String
    var proposedReviewState: String
    var reasonCodes: [String]
    var sourceRefs: [String]
    var sourceEvidenceRef: String?
}

struct SecondBrainJournalCandidateReplacementPreview: Codable, Equatable {
    var previewRef: String
    var kind: String
    var value: String
    var evidence: String
    var metadata: [String: String]
    var replacementForCandidateIDs: [String]
    var replacementForCandidateRefs: [String]
    var sourceRefs: [String]
    var sourceEvidenceRef: String?
    var truthBoundary: String
    var acceptedAsTruth: Bool
}

struct SecondBrainJournalCandidateReconciliationReport: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var readOnly: Bool
    var changed: Bool
    var totalStoredCandidateCount: Int
    var currentExtractionCandidateCount: Int
    var currentExtractionReplacementPreviewCount: Int
    var candidateCount: Int
    var candidates: [SecondBrainJournalCandidateReconciliationCandidate]
    var currentExtractionReplacementPreviews: [SecondBrainJournalCandidateReplacementPreview]
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
        let replacementPreviews = currentExtractionReplacementPreviews(
            owner: owner,
            rawContent: rawContent,
            current: current,
            diagnosed: diagnosed
        )

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
            currentExtractionReplacementPreviewCount: replacementPreviews.count,
            candidateCount: diagnosed.count,
            candidates: diagnosed,
            currentExtractionReplacementPreviews: replacementPreviews,
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
        if isCommunitySupportOutageSpan(text) { reasons.append("community_support_outage_span") }
        if isBareMediaProgressSpan(output) { reasons.append("bare_media_progress_span") }
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
            metadata: output.metadata,
            previousReviewState: output.reviewState,
            proposedReviewState: "superseded",
            reasonCodes: reasonCodes,
            sourceRefs: Array(NSOrderedSet(array: sourceRefs)) as? [String] ?? sourceRefs,
            sourceEvidenceRef: output.metadata["source_evidence_ref"]
        )
    }

    private func currentExtractionReplacementPreviews(
        owner: SecondBrainOwnerRef,
        rawContent: String,
        current: [SecondBrainEnrichmentOutput],
        diagnosed: [SecondBrainJournalCandidateReconciliationCandidate]
    ) -> [SecondBrainJournalCandidateReplacementPreview] {
        guard !diagnosed.isEmpty else { return [] }

        var previews: [SecondBrainJournalCandidateReplacementPreview] = []
        for output in current {
            let replacementMatches = diagnosed.compactMap { diagnosedCandidate in
                replacementPreviewMatch(
                    output,
                    for: diagnosedCandidate,
                    rawContent: rawContent,
                    current: current,
                    diagnosed: diagnosed
                )
            }
            guard !replacementMatches.isEmpty else { continue }

            var sourceRefs = [owner.canonicalRef, previewRef(for: output, index: previews.count)]
            if let sourceEvidenceRef = output.metadata["source_evidence_ref"] {
                sourceRefs.append(sourceEvidenceRef)
            }

            var metadata = output.metadata
            metadata[SecondBrainGraphCandidateContract.MetadataKey.truthBoundary] = "reviewable_candidate_not_truth"
            metadata["accepted_as_truth"] = "false"
            metadata["preview_only"] = "true"
            metadata["replacement_preview"] = "true"
            if let proximityMatch = replacementMatches.first(where: { $0.basis == "source_quote_proximity" }) {
                metadata["replacement_pairing_basis"] = proximityMatch.basis
                metadata["replacement_pairing_owner_ref"] = owner.canonicalRef
                metadata["replacement_pairing_stale_source_quote"] = proximityMatch.staleSourceQuote
                metadata["replacement_pairing_current_source_quote"] = proximityMatch.currentSourceQuote
                metadata["replacement_pairing_source_quote_distance"] = "\(proximityMatch.sourceQuoteDistance)"
            }

            previews.append(
                SecondBrainJournalCandidateReplacementPreview(
                    previewRef: previewRef(for: output, index: previews.count),
                    kind: output.kind,
                    value: output.value,
                    evidence: output.evidence,
                    metadata: metadata,
                    replacementForCandidateIDs: replacementMatches.map(\.candidate.candidateID),
                    replacementForCandidateRefs: replacementMatches.map(\.candidate.candidateRef),
                    sourceRefs: Array(NSOrderedSet(array: sourceRefs)) as? [String] ?? sourceRefs,
                    sourceEvidenceRef: output.metadata["source_evidence_ref"],
                    truthBoundary: "reviewable_candidate_not_truth",
                    acceptedAsTruth: false
                )
            )
        }
        return previews
    }

    private struct ReplacementPreviewMatch {
        var candidate: SecondBrainJournalCandidateReconciliationCandidate
        var basis: String
        var staleSourceQuote: String
        var currentSourceQuote: String
        var sourceQuoteDistance: Int
    }

    private func replacementPreviewMatch(
        _ output: SecondBrainEnrichmentOutput,
        for candidate: SecondBrainJournalCandidateReconciliationCandidate,
        rawContent: String,
        current: [SecondBrainEnrichmentOutput],
        diagnosed: [SecondBrainJournalCandidateReconciliationCandidate]
    ) -> ReplacementPreviewMatch? {
        if isReplacementPreview(output, for: candidate) {
            return ReplacementPreviewMatch(
                candidate: candidate,
                basis: "existing_candidate_evidence_or_metadata",
                staleSourceQuote: "",
                currentSourceQuote: "",
                sourceQuoteDistance: 0
            )
        }
        guard !diagnosed.contains(where: { isReplacementPreview(output, for: $0) }) else { return nil }
        if let proximity = sourceQuoteProximityBoundedReplacement(
            output,
            for: candidate,
            rawContent: rawContent,
            current: current,
            diagnosed: diagnosed
        ) {
            return proximity
        }
        return nil
    }

    private func isReplacementPreview(
        _ output: SecondBrainEnrichmentOutput,
        for candidate: SecondBrainJournalCandidateReconciliationCandidate
    ) -> Bool {
        let outputEvidence = normalized(output.evidence)
        let candidateEvidence = normalized(candidate.evidence)
        let outputValue = normalized(output.value)
        let candidateValue = normalized(candidate.value)
        guard outputValue != candidateValue else { return false }
        let sharesEvidence = !outputEvidence.isEmpty && !candidateEvidence.isEmpty
            && (outputEvidence == candidateEvidence
                || outputEvidence.contains(candidateEvidence)
                || candidateEvidence.contains(outputEvidence))
        let titledMediaReplacement = candidate.reasonCodes.contains("bare_media_progress_span")
            && output.metadata[SecondBrainGraphCandidateContract.MetadataKey.mediaTitle] != nil
            && (outputEvidence.contains(candidateValue) || candidateEvidence.contains(candidateValue))
        let metadataBoundedReplacement = isMetadataBoundedReplacement(output, for: candidate)
        guard sharesEvidence || titledMediaReplacement || metadataBoundedReplacement else { return false }
        return candidate.reasonCodes.contains("not_emitted_by_current_extractor")
            || candidate.reasonCodes.contains("bare_media_progress_span")
            || candidate.reasonCodes.contains("noisy_clause_span")
            || candidate.reasonCodes.contains("community_support_outage_span")
            || candidate.reasonCodes.contains("low_confidence_stored_candidate")
    }

    private func isMetadataBoundedReplacement(
        _ output: SecondBrainEnrichmentOutput,
        for candidate: SecondBrainJournalCandidateReconciliationCandidate
    ) -> Bool {
        guard candidate.reasonCodes.contains("not_emitted_by_current_extractor") else { return false }
        guard normalized(output.metadata["source_kind"] ?? "") == "journal",
              normalized(candidate.metadata["source_kind"] ?? "") == "journal" else { return false }

        for key in metadataReplacementKeys {
            let outputValue = normalized(output.metadata[key] ?? "")
            let candidateValue = normalized(candidate.metadata[key] ?? "")
            if !outputValue.isEmpty && outputValue == candidateValue {
                return true
            }
        }
        return false
    }

    private func sourceQuoteProximityBoundedReplacement(
        _ output: SecondBrainEnrichmentOutput,
        for candidate: SecondBrainJournalCandidateReconciliationCandidate,
        rawContent: String,
        current: [SecondBrainEnrichmentOutput],
        diagnosed: [SecondBrainJournalCandidateReconciliationCandidate]
    ) -> ReplacementPreviewMatch? {
        guard candidate.reasonCodes.contains("not_emitted_by_current_extractor"),
              candidate.reasonCodes.contains(where: isNoiseReason) else { return nil }
        guard normalized(output.metadata["source_kind"] ?? "") == "journal",
              normalized(candidate.metadata["source_kind"] ?? "") == "journal" else { return nil }
        guard !hasSharedMetadataReplacementKey(output, candidate: candidate) else { return nil }

        let candidateQuote = sourceQuote(for: candidate)
        let outputQuote = sourceQuote(for: output)
        guard let candidateLine = sourceQuoteLineIndex(candidateQuote, in: rawContent),
              let outputLine = sourceQuoteLineIndex(outputQuote, in: rawContent) else { return nil }

        let currentDistances = current.compactMap { currentOutput -> (id: String, distance: Int)? in
            guard normalized(currentOutput.metadata["source_kind"] ?? "") == "journal",
                  !hasSharedMetadataReplacementKey(currentOutput, candidate: candidate),
                  let line = sourceQuoteLineIndex(sourceQuote(for: currentOutput), in: rawContent) else {
                return nil
            }
            return (currentOutput.id, abs(line - candidateLine))
        }
        guard let nearestCurrentDistance = currentDistances.map(\.distance).min(),
              nearestCurrentDistance > 0,
              nearestCurrentDistance <= 1,
              currentDistances.filter({ $0.distance == nearestCurrentDistance }).count == 1,
              currentDistances.first(where: { $0.id == output.id })?.distance == nearestCurrentDistance else {
            return nil
        }

        let diagnosedDistances = diagnosed.compactMap { diagnosedCandidate -> (id: String, distance: Int)? in
            guard diagnosedCandidate.candidateID != candidate.candidateID,
                  normalized(diagnosedCandidate.metadata["source_kind"] ?? "") == "journal",
                  let line = sourceQuoteLineIndex(sourceQuote(for: diagnosedCandidate), in: rawContent) else {
                return nil
            }
            return (diagnosedCandidate.candidateID, abs(line - outputLine))
        }
        let targetDistance = abs(outputLine - candidateLine)
        guard diagnosedDistances.filter({ $0.distance == targetDistance }).isEmpty else { return nil }

        return ReplacementPreviewMatch(
            candidate: candidate,
            basis: "source_quote_proximity",
            staleSourceQuote: candidateQuote,
            currentSourceQuote: outputQuote,
            sourceQuoteDistance: targetDistance
        )
    }

    private func hasSharedMetadataReplacementKey(
        _ output: SecondBrainEnrichmentOutput,
        candidate: SecondBrainJournalCandidateReconciliationCandidate
    ) -> Bool {
        metadataReplacementKeys.contains { key in
            let outputValue = normalized(output.metadata[key] ?? "")
            let candidateValue = normalized(candidate.metadata[key] ?? "")
            return !outputValue.isEmpty && outputValue == candidateValue
        }
    }

    private func sourceQuote(for output: SecondBrainEnrichmentOutput) -> String {
        output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceQuote]
            ?? output.metadata["source_quote"]
            ?? output.evidence
    }

    private func sourceQuote(for candidate: SecondBrainJournalCandidateReconciliationCandidate) -> String {
        candidate.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceQuote]
            ?? candidate.metadata["source_quote"]
            ?? candidate.evidence
    }

    private func sourceQuoteLineIndex(_ quote: String, in rawContent: String) -> Int? {
        let normalizedQuote = normalized(quote)
        guard !normalizedQuote.isEmpty else { return nil }
        let lines = rawContent.components(separatedBy: .newlines)
        for (index, line) in lines.enumerated() {
            let normalizedLine = normalized(line)
            guard !normalizedLine.isEmpty else { continue }
            if normalizedLine == normalizedQuote
                || normalizedLine.contains(normalizedQuote)
                || normalizedQuote.contains(normalizedLine) {
                return index
            }
        }
        return nil
    }

    private var metadataReplacementKeys: [String] {
        [
            "memory_key",
            SecondBrainGraphCandidateContract.MetadataKey.mediaTitle,
        ]
    }

    private func previewRef(for output: SecondBrainEnrichmentOutput, index: Int) -> String {
        let value = normalized(output.value)
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suffix = value.isEmpty ? "\(index + 1)" : value
        return "current_extraction_preview:\(output.owner.ownerType):\(output.owner.ownerID):\(suffix)"
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
        [
            "noisy_clause_span",
            "community_support_outage_span",
            "bare_media_progress_span",
            "low_confidence_stored_candidate",
        ].contains(reason)
    }

    private func isNoisyClauseSpan(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains(";")
            || lower.contains("random things")
            || (lower.contains("money seemed") && lower.contains("gift"))
            || lower.contains("guessing a gift")
    }

    private func isEpisodeCountSpan(_ text: String) -> Bool {
        text.range(
            of: #"(?i)\b(?:through|at least)\s+(?:\w+\s+)?(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+episodes?\b"#,
            options: .regularExpression
        ) != nil
    }

    private func isCommunitySupportOutageSpan(_ text: String) -> Bool {
        let lower = text.lowercased()
        let hasCommunitySource = lower.range(of: #"\br/[a-z0-9_]+\b"#, options: .regularExpression) != nil
            || lower.contains("forum")
            || lower.contains("community")
            || lower.contains("support")
        let hasOutageSignal = lower.contains("outage")
            || lower.contains("systems down")
            || lower.contains("system down")
            || lower.contains("cms/")
            || lower.contains("/cms")
        return hasCommunitySource && hasOutageSignal
    }

    private func isBareMediaProgressSpan(_ output: SecondBrainEnrichmentOutput) -> Bool {
        let text = "\(output.value) \(output.evidence)"
        guard isEpisodeCountSpan(text) else { return false }
        let value = normalized(output.value)
        let objectTypes = DatabaseHelpers.decodeStringArray(
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses]
        )
        let relationGuesses = DatabaseHelpers.decodeStringArray(
            output.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses]
        )
        let looksMediaRelated = objectTypes.contains("media")
            || objectTypes.contains("movie")
            || objectTypes.contains("show")
            || objectTypes.contains("video")
            || relationGuesses.contains("watched")
            || relationGuesses.contains("read")
            || relationGuesses.contains("listened_to")
        guard looksMediaRelated else { return false }
        let bareProgressPattern = #"(?i)^(?:watched\s+)?(?:through|at least)\s+(?:\w+\s+)?(?:\d+|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+episodes?$"#
        return value.range(of: bareProgressPattern, options: .regularExpression) != nil
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
