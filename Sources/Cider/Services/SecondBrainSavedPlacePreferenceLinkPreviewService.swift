import Foundation

struct SecondBrainSavedPlacePreferenceLinkPreviewSource: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var snippet: String
    var url: String?
    var relativePath: String?
    var sourceEvidenceRef: String?
    var sourceSpan: SecondBrainSavedPlacePreferenceLinkSourceSpan?
}

struct SecondBrainSavedPlacePreferenceLinkSourceSpan: Codable, Equatable {
    var sourceItemRef: String
    var sourceField: String
    var snippet: String
    var matchedText: String
    var startOffset: Int
    var endOffset: Int
    var selector: String
    var sourceEvidenceRef: String?
    var syntheticSourceEvidenceRef: String?
    var truthBoundary: String
}

struct SecondBrainSavedPlacePreferenceLinkCandidate: Identifiable, Codable, Equatable {
    var id: String
    var savedItem: SecondBrainSavedPlacePreferenceLinkPreviewSource
    var evidenceItem: SecondBrainSavedPlacePreferenceLinkPreviewSource
    var preferenceValue: String
    var confidence: Double
    var reason: String
    var reasonCodes: [String]
    var sourceRefs: [String]
    var truthBoundary: String
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]
}

struct SecondBrainSavedPlacePreferenceLinkDiagnosticRow: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var reasonCode: String
    var matchedTerms: [String]
    var sourceRefs: [String]
    var sourceSpan: SecondBrainSavedPlacePreferenceLinkSourceSpan?
    var safeVerificationCommands: [String]
}

struct SecondBrainSavedPlacePreferenceLinkDiagnostics: Codable, Equatable {
    var inspectedBookmarkCount: Int
    var savedPlaceBookmarkCount: Int
    var preferenceEvidenceCount: Int
    var candidateCount: Int
    var skippedBookmarkSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    var noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    var evidenceSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    var evidenceRejectedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
}

struct SecondBrainSavedPlacePreferenceLinkPreviewReport: Codable, Equatable {
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "reviewable_candidate_not_truth"
    var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate]
    var diagnostics: SecondBrainSavedPlacePreferenceLinkDiagnostics
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]
}

struct SecondBrainPreferenceSavedPlaceLinkGroup: Identifiable, Codable, Equatable {
    var id: String
    var evidenceItem: SecondBrainSavedPlacePreferenceLinkPreviewSource
    var preferenceValue: String
    var sourceRefs: [String]
    var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate]
    var truthBoundary: String
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]
}

struct SecondBrainPreferenceSavedPlaceLinkPreviewReport: Codable, Equatable {
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "reviewable_candidate_not_truth"
    var groups: [SecondBrainPreferenceSavedPlaceLinkGroup]
    var diagnostics: SecondBrainSavedPlacePreferenceLinkDiagnostics
    var safeVerificationCommands: [String]
    var safeNextCommands: [String]
}

@MainActor
final class SecondBrainSavedPlacePreferenceLinkPreviewService {
    private struct SavedBookmark {
        var owner: SecondBrainOwnerRef
        var title: String
        var url: String
        var relativePath: String?
        var placeTerms: [String]
        var bookmarkConfidence: Double
    }

    private struct SavedBookmarkScan {
        var inspectedCount: Int
        var bookmarks: [SavedBookmark]
        var skippedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    }

    private struct PreferenceEvidence {
        var id: String
        var owner: SecondBrainOwnerRef
        var title: String
        var value: String
        var evidence: String
        var confidence: Double
        var sourceEvidenceRef: String?
        var sourceSpan: SecondBrainSavedPlacePreferenceLinkSourceSpan?
        var sourceRefs: [String]
        var terms: [String]
    }

    private struct SavedPlaceClassification {
        var isPlace: Bool
        var confidence: Double
    }

    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func preview(limit: Int = 20) throws -> SecondBrainSavedPlacePreferenceLinkPreviewReport {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else {
            return report(
                candidates: [],
                diagnostics: diagnostics(
                    inspectedBookmarkCount: 0,
                    savedPlaceBookmarkCount: 0,
                    preferenceEvidenceCount: 0,
                    candidateCount: 0,
                    skippedBookmarkSamples: [],
                    noMatchSamples: [],
                    evidenceSamples: [],
                    evidenceRejectedSamples: []
                )
            )
        }

        let bookmarkScan = try savedPlaceBookmarks()
        let preferenceScan = try journalFoodPreferences()
        let preferences = preferenceScan.evidence
        var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate] = []
        var noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []

        for bookmark in bookmarkScan.bookmarks {
            var matchedBookmark = false
            for preference in preferences {
                guard let match = match(bookmark: bookmark, preference: preference) else { continue }
                candidates.append(candidate(bookmark: bookmark, preference: preference, match: match))
                matchedBookmark = true
            }
            if !matchedBookmark {
                noMatchSamples.append(
                    diagnosticRow(
                        owner: bookmark.owner,
                        title: bookmark.title,
                        reasonCode: preferences.isEmpty ? "no_preference_evidence" : "no_shared_cuisine_alias",
                        matchedTerms: bookmark.placeTerms,
                        sourceRefs: [bookmark.owner.canonicalRef]
                    )
                )
            }
        }

        candidates.sort {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.savedItem.title.localizedCaseInsensitiveCompare($1.savedItem.title) == .orderedAscending
        }
        let boundedCandidates = Array(candidates.prefix(boundedLimit))
        return report(
            candidates: boundedCandidates,
            diagnostics: diagnostics(
                inspectedBookmarkCount: bookmarkScan.inspectedCount,
                savedPlaceBookmarkCount: bookmarkScan.bookmarks.count,
                preferenceEvidenceCount: preferences.count,
                candidateCount: boundedCandidates.count,
                skippedBookmarkSamples: bookmarkScan.skippedSamples,
                noMatchSamples: noMatchSamples,
                evidenceSamples: preferenceScan.evidenceSamples,
                evidenceRejectedSamples: preferenceScan.rejectedSamples
            )
        )
    }

    func reciprocalPreview(
        ownerSelector: String? = nil,
        limit: Int = 20
    ) throws -> SecondBrainPreferenceSavedPlaceLinkPreviewReport {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else {
            return reciprocalReport(
                groups: [],
                diagnostics: diagnostics(
                    inspectedBookmarkCount: 0,
                    savedPlaceBookmarkCount: 0,
                    preferenceEvidenceCount: 0,
                    candidateCount: 0,
                    skippedBookmarkSamples: [],
                    noMatchSamples: [],
                    evidenceSamples: [],
                    evidenceRejectedSamples: []
                ),
                ownerSelector: ownerSelector
            )
        }

        let bookmarkScan = try savedPlaceBookmarks()
        let preferenceScan = try journalFoodPreferences()
        let selectedPreferences = preferenceScan.evidence.filter { preferenceMatchesSelector($0, selector: ownerSelector) }
        var groups: [SecondBrainPreferenceSavedPlaceLinkGroup] = []
        var noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []

        for preference in selectedPreferences {
            var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate] = []
            for bookmark in bookmarkScan.bookmarks {
                guard let match = match(bookmark: bookmark, preference: preference) else { continue }
                candidates.append(candidate(bookmark: bookmark, preference: preference, match: match))
            }
            candidates.sort {
                if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
                return $0.savedItem.title.localizedCaseInsensitiveCompare($1.savedItem.title) == .orderedAscending
            }
            let boundedCandidates = Array(candidates.prefix(boundedLimit))
            if boundedCandidates.isEmpty {
                noMatchSamples.append(
                    diagnosticRow(
                        owner: preference.owner,
                        title: preference.title,
                        reasonCode: bookmarkScan.bookmarks.isEmpty ? "no_saved_place_candidates" : "no_related_saved_place_matches",
                        matchedTerms: preference.terms,
                        sourceRefs: preference.sourceRefs,
                        sourceSpan: preference.sourceSpan
                    )
                )
                continue
            }
            groups.append(reciprocalGroup(preference: preference, candidates: boundedCandidates, ownerSelector: ownerSelector))
        }

        groups.sort {
            if $0.candidates.count != $1.candidates.count { return $0.candidates.count > $1.candidates.count }
            return $0.evidenceItem.title.localizedCaseInsensitiveCompare($1.evidenceItem.title) == .orderedAscending
        }
        let boundedGroups = Array(groups.prefix(boundedLimit))
        let returnedCandidateCount = boundedGroups.flatMap(\.candidates).count
        return reciprocalReport(
            groups: boundedGroups,
            diagnostics: diagnostics(
                inspectedBookmarkCount: bookmarkScan.inspectedCount,
                savedPlaceBookmarkCount: bookmarkScan.bookmarks.count,
                preferenceEvidenceCount: selectedPreferences.count,
                candidateCount: returnedCandidateCount,
                skippedBookmarkSamples: bookmarkScan.skippedSamples,
                noMatchSamples: noMatchSamples,
                evidenceSamples: preferenceScan.evidenceSamples.filter { diagnosticMatchesSelector($0, selector: ownerSelector) },
                evidenceRejectedSamples: preferenceScan.rejectedSamples
            ),
            ownerSelector: ownerSelector
        )
    }

    private func report(
        candidates: [SecondBrainSavedPlacePreferenceLinkCandidate],
        diagnostics: SecondBrainSavedPlacePreferenceLinkDiagnostics
    ) -> SecondBrainSavedPlacePreferenceLinkPreviewReport {
        let safeCommands = ["cider-cli item saved-place-preference-links --json"]
        return SecondBrainSavedPlacePreferenceLinkPreviewReport(
            candidates: candidates,
            diagnostics: diagnostics,
            safeVerificationCommands: safeCommands,
            safeNextCommands: safeCommands
        )
    }

    private func reciprocalReport(
        groups: [SecondBrainPreferenceSavedPlaceLinkGroup],
        diagnostics: SecondBrainSavedPlacePreferenceLinkDiagnostics,
        ownerSelector: String?
    ) -> SecondBrainPreferenceSavedPlaceLinkPreviewReport {
        let safeCommands = [reciprocalCommand(ownerSelector: ownerSelector)]
        return SecondBrainPreferenceSavedPlaceLinkPreviewReport(
            groups: groups,
            diagnostics: diagnostics,
            safeVerificationCommands: safeCommands,
            safeNextCommands: safeCommands
        )
    }

    private func reciprocalCommand(ownerSelector: String?) -> String {
        if let ownerSelector, !ownerSelector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "cider-cli item preference-saved-place-links --owner \(ownerSelector) --json"
        }
        return "cider-cli item preference-saved-place-links --json"
    }

    private func diagnostics(
        inspectedBookmarkCount: Int,
        savedPlaceBookmarkCount: Int,
        preferenceEvidenceCount: Int,
        candidateCount: Int,
        skippedBookmarkSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow],
        noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow],
        evidenceSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow],
        evidenceRejectedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    ) -> SecondBrainSavedPlacePreferenceLinkDiagnostics {
        SecondBrainSavedPlacePreferenceLinkDiagnostics(
            inspectedBookmarkCount: inspectedBookmarkCount,
            savedPlaceBookmarkCount: savedPlaceBookmarkCount,
            preferenceEvidenceCount: preferenceEvidenceCount,
            candidateCount: candidateCount,
            skippedBookmarkSamples: Array(skippedBookmarkSamples.prefix(20)),
            noMatchSamples: Array(noMatchSamples.prefix(20)),
            evidenceSamples: Array(evidenceSamples.prefix(20)),
            evidenceRejectedSamples: Array(evidenceRejectedSamples.prefix(20))
        )
    }

    private func reciprocalGroup(
        preference: PreferenceEvidence,
        candidates: [SecondBrainSavedPlacePreferenceLinkCandidate],
        ownerSelector: String?
    ) -> SecondBrainPreferenceSavedPlaceLinkGroup {
        let sourceRefs = orderedUnique(preference.sourceRefs + candidates.flatMap(\.sourceRefs))
        let safeCommands = orderedUnique(
            ["cider-cli item context \(preference.owner.ownerType) \(preference.owner.ownerID) --json"]
                + graphCandidateCommand(for: preference)
                + candidates.flatMap(\.safeVerificationCommands)
                + [reciprocalCommand(ownerSelector: ownerSelector)]
        )
        return SecondBrainPreferenceSavedPlaceLinkGroup(
            id: "preference_saved_places:\(preference.id)",
            evidenceItem: SecondBrainSavedPlacePreferenceLinkPreviewSource(
                owner: preference.owner,
                title: preference.title,
                snippet: preference.evidence,
                url: nil,
                relativePath: nil,
                sourceEvidenceRef: preference.sourceEvidenceRef,
                sourceSpan: preference.sourceSpan
            ),
            preferenceValue: preference.value,
            sourceRefs: sourceRefs,
            candidates: candidates,
            truthBoundary: "reviewable_candidate_not_truth",
            safeVerificationCommands: safeCommands,
            safeNextCommands: safeCommands
        )
    }

    private func preferenceMatchesSelector(_ preference: PreferenceEvidence, selector: String?) -> Bool {
        guard let rawSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSelector.isEmpty else {
            return true
        }
        let candidates = [
            preference.owner.ownerID,
            preference.owner.canonicalRef,
            "\(preference.owner.ownerType):\(preference.owner.ownerID)",
            preference.id,
            preference.sourceEvidenceRef,
        ].compactMap { $0 }
        return candidates.contains { $0 == rawSelector || $0.hasPrefix(rawSelector) }
    }

    private func diagnosticMatchesSelector(_ row: SecondBrainSavedPlacePreferenceLinkDiagnosticRow, selector: String?) -> Bool {
        guard let rawSelector = selector?.trimmingCharacters(in: .whitespacesAndNewlines), !rawSelector.isEmpty else {
            return true
        }
        let refs = [row.owner.ownerID, row.owner.canonicalRef, "\(row.owner.ownerType):\(row.owner.ownerID)"] + row.sourceRefs
        return refs.contains { $0 == rawSelector || $0.hasPrefix(rawSelector) }
    }

    private func savedPlaceBookmarks() throws -> SavedBookmarkScan {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, i.relative_path, b.url, b.ocr_text
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.type = 'bookmark'
            ORDER BY i.created_at DESC, i.title COLLATE NOCASE ASC;
            """)

        var bookmarks: [SavedBookmark] = []
        var skippedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []
        var inspectedCount = 0
        while try stmt.step() {
            inspectedCount += 1
            let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: stmt.string(at: 0))
            let title = stmt.string(at: 1)
            let relativePath = stmt.optionalString(at: 2)
            let url = stmt.string(at: 3)
            let ocrText = stmt.optionalString(at: 4) ?? ""
            let extraction = SecondBrainBookmarkGraphCandidateExtractor().extract(
                sourceOwner: owner,
                urlString: url,
                title: title
            )
            let classification = savedPlaceClassification(
                title: title,
                url: url,
                ocrText: ocrText,
                extractionOutput: extraction.outputs.first
            )
            guard classification.isPlace else {
                skippedSamples.append(
                    diagnosticRow(owner: owner, title: title, reasonCode: "not_saved_place_candidate", matchedTerms: [], sourceRefs: [owner.canonicalRef])
                )
                continue
            }
            let terms = cuisineTerms(in: "\(title) \(url) \(ocrText)")
            guard !terms.isEmpty else {
                skippedSamples.append(
                    diagnosticRow(owner: owner, title: title, reasonCode: "no_supported_cuisine_terms", matchedTerms: [], sourceRefs: [owner.canonicalRef])
                )
                continue
            }
            bookmarks.append(
                SavedBookmark(
                    owner: owner,
                    title: title,
                    url: url,
                    relativePath: relativePath,
                    placeTerms: terms,
                    bookmarkConfidence: classification.confidence
                )
            )
        }
        return SavedBookmarkScan(
            inspectedCount: inspectedCount,
            bookmarks: bookmarks,
            skippedSamples: Array(skippedSamples.prefix(20))
        )
    }

    private struct PreferenceEvidenceScan {
        var evidence: [PreferenceEvidence]
        var evidenceSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
        var rejectedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    }

    private func journalFoodPreferences() throws -> PreferenceEvidenceScan {
        let outputs = try SecondBrainEnrichmentOutputService(database: database).outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: nil,
            limit: nil
        )
        var evidence: [PreferenceEvidence] = []
        var evidenceSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []
        var rejectedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []

        for output in outputs {
            guard output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceKind] == "journal" else { continue }
            let objectTypes = DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses])
            let relations = DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses])
            guard objectTypes.contains("food") || objectTypes.contains("restaurant") || objectTypes.contains("place") else { continue }
            guard relations.contains("likes_food") || relations.contains("likes") else { continue }
            let evidenceRef = output.metadata["source_evidence_ref"]
            let terms = cuisineTerms(in: "\(output.value) \(output.evidence)")
            evidence.append(
                PreferenceEvidence(
                    id: output.id,
                    owner: output.owner,
                    title: "Journal preference evidence",
                    value: output.value,
                    evidence: output.evidence,
                    confidence: output.confidence ?? 0.78,
                    sourceEvidenceRef: evidenceRef,
                    sourceSpan: nil,
                    sourceRefs: [output.owner.canonicalRef, "graph_candidate:\(output.id)", evidenceRef].compactMap { $0 },
                    terms: terms
                )
            )
            evidenceSamples.append(
                diagnosticRow(
                    owner: output.owner,
                    title: "Journal preference evidence",
                    reasonCode: "usable_graph_food_preference_evidence",
                    matchedTerms: terms,
                    sourceRefs: [output.owner.canonicalRef, "graph_candidate:\(output.id)", evidenceRef].compactMap { $0 }
                )
            )
        }

        let noteScan = try noteFoodPreferences()
        evidence.append(contentsOf: noteScan.evidence)
        evidenceSamples.append(contentsOf: noteScan.evidenceSamples)
        rejectedSamples.append(contentsOf: noteScan.rejectedSamples)
        return PreferenceEvidenceScan(
            evidence: evidence,
            evidenceSamples: evidenceSamples,
            rejectedSamples: rejectedSamples
        )
    }

    private func noteFoodPreferences() throws -> PreferenceEvidenceScan {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, n.content
            FROM items i
            JOIN notes n ON n.item_id = i.id
            WHERE i.type = 'note'
            ORDER BY i.created_at DESC, i.title COLLATE NOCASE ASC;
            """)

        var evidence: [PreferenceEvidence] = []
        var evidenceSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []
        var rejectedSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []
        while try stmt.step() {
            let owner = SecondBrainOwnerRef(ownerType: "note", ownerID: stmt.string(at: 0))
            let title = stmt.string(at: 1)
            let content = stmt.optionalString(at: 2) ?? ""
            for sentence in foodEvidenceSentences(in: content) {
                let terms = cuisineTerms(in: sentence.text)
                guard !terms.isEmpty else { continue }
                let sourceSpan = sourceSpan(
                    owner: owner,
                    sourceField: "notes.content",
                    content: content,
                    sentence: sentence,
                    sourceEvidenceRef: nil
                )
                let sourceRefs = [owner.canonicalRef, sourceSpan.syntheticSourceEvidenceRef].compactMap { $0 }
                if isNoisyOrNegativeFoodPreferenceSentence(sentence.text) {
                    rejectedSamples.append(
                        diagnosticRow(
                            owner: owner,
                            title: title,
                            reasonCode: "negative_or_non_preference_food_mention",
                            matchedTerms: terms,
                            sourceRefs: sourceRefs,
                            sourceSpan: sourceSpan
                        )
                    )
                    continue
                }
                if isPlanningOrAuditFoodMention(title: title, sentence: sentence.text) {
                    rejectedSamples.append(
                        diagnosticRow(
                            owner: owner,
                            title: title,
                            reasonCode: "planning_or_audit_food_mention",
                            matchedTerms: terms,
                            sourceRefs: sourceRefs,
                            sourceSpan: sourceSpan
                        )
                    )
                    continue
                }
                guard hasFoodPreferenceCue(sentence.text) else {
                    rejectedSamples.append(
                        diagnosticRow(
                            owner: owner,
                            title: title,
                            reasonCode: "food_mention_without_preference_cue",
                            matchedTerms: terms,
                            sourceRefs: sourceRefs,
                            sourceSpan: sourceSpan
                        )
                    )
                    continue
                }
                let id = "note_food_preference:\(owner.ownerID):\(terms.joined(separator: "-"))"
                evidence.append(
                    PreferenceEvidence(
                        id: id,
                        owner: owner,
                        title: title,
                        value: displayPreferenceValue(terms: terms),
                        evidence: sentence.text,
                        confidence: 0.76,
                        sourceEvidenceRef: nil,
                        sourceSpan: sourceSpan,
                        sourceRefs: sourceRefs,
                        terms: terms
                    )
                )
                evidenceSamples.append(
                    diagnosticRow(
                        owner: owner,
                        title: title,
                        reasonCode: "usable_food_preference_evidence",
                        matchedTerms: terms,
                        sourceRefs: sourceRefs,
                        sourceSpan: sourceSpan
                    )
                )
            }
        }
        return PreferenceEvidenceScan(evidence: evidence, evidenceSamples: evidenceSamples, rejectedSamples: rejectedSamples)
    }

    private struct Match {
        var term: String
        var confidence: Double
        var reason: String
        var reasonCodes: [String]
    }

    private func match(bookmark: SavedBookmark, preference: PreferenceEvidence) -> Match? {
        let preferenceText = normalizedWords(preference.value)
        let preferenceTerms = orderedUnique(preference.terms + cuisineTerms(in: preference.value))
        if preferenceTerms.contains("asian") {
            let asianTerms = Set(["asian", "thai", "japanese", "korean", "chinese", "vietnamese", "sushi", "ramen", "pho", "dim sum"])
            if let term = bookmark.placeTerms.first(where: { asianTerms.contains($0) }) {
                return Match(
                    term: term,
                    confidence: min(0.96, max(bookmark.bookmarkConfidence, preference.confidence) - 0.05),
                    reason: "Saved restaurant looks \(term.capitalized) and journal evidence says the user likes Asian food.",
                    reasonCodes: ["saved_restaurant_matches_food_preference", "source_backed_journal_preference", "cuisine_alias_family_match", "read_only_preview"]
                )
            }
        }

        if let aliasMatch = cuisineAliasMatch(bookmarkTerms: bookmark.placeTerms, preferenceTerms: preferenceTerms) {
            return Match(
                term: aliasMatch.bookmarkTerm,
                confidence: min(0.93, max(bookmark.bookmarkConfidence, preference.confidence) - 0.06),
                reason: "Saved restaurant looks \(aliasMatch.bookmarkDisplay) and journal evidence says the user likes \(aliasMatch.preferenceDisplay) food.",
                reasonCodes: ["saved_restaurant_matches_food_preference", "source_backed_journal_preference", "cuisine_alias_family_match", "read_only_preview"]
            )
        }

        if let term = bookmark.placeTerms.first(where: { preferenceText.contains($0) || preferenceTerms.contains($0) }) {
            return Match(
                term: term,
                confidence: min(0.92, max(bookmark.bookmarkConfidence, preference.confidence) - 0.08),
                reason: "Saved restaurant and journal preference share '\(term)'.",
                reasonCodes: ["saved_restaurant_matches_food_preference", "source_backed_journal_preference", "read_only_preview"]
            )
        }
        return nil
    }

    private func candidate(
        bookmark: SavedBookmark,
        preference: PreferenceEvidence,
        match: Match
    ) -> SecondBrainSavedPlacePreferenceLinkCandidate {
        let sourceRefs = orderedUnique([
            bookmark.owner.canonicalRef,
            preference.owner.canonicalRef,
            preference.sourceEvidenceRef,
        ].compactMap { $0 } + preference.sourceRefs)
        let safeVerificationCommands = [
            "cider-cli item context bookmark \(bookmark.owner.ownerID) --json",
            "cider-cli item context \(preference.owner.ownerType) \(preference.owner.ownerID) --json",
        ] + graphCandidateCommand(for: preference)
        let safeNextCommands = [
            "cider-cli item context bookmark \(bookmark.owner.ownerID) --json",
            "cider-cli item context \(preference.owner.ownerType) \(preference.owner.ownerID) --json",
        ] + graphCandidateCommand(for: preference)
        return SecondBrainSavedPlacePreferenceLinkCandidate(
            id: "saved_place_preference:\(bookmark.owner.ownerID):\(preference.id)",
            savedItem: SecondBrainSavedPlacePreferenceLinkPreviewSource(
                owner: bookmark.owner,
                title: bookmark.title,
                snippet: "\(bookmark.title) - \(bookmark.url)",
                url: bookmark.url,
                relativePath: bookmark.relativePath,
                sourceEvidenceRef: nil,
                sourceSpan: nil
            ),
            evidenceItem: SecondBrainSavedPlacePreferenceLinkPreviewSource(
                owner: preference.owner,
                title: preference.title,
                snippet: preference.evidence,
                url: nil,
                relativePath: nil,
                sourceEvidenceRef: preference.sourceEvidenceRef,
                sourceSpan: preference.sourceSpan
            ),
            preferenceValue: preference.value,
            confidence: match.confidence,
            reason: match.reason,
            reasonCodes: match.reasonCodes,
            sourceRefs: sourceRefs,
            truthBoundary: "reviewable_candidate_not_truth",
            safeVerificationCommands: safeVerificationCommands,
            safeNextCommands: safeNextCommands
        )
    }

    private func graphCandidateCommand(for preference: PreferenceEvidence) -> [String] {
        preference.sourceRefs.compactMap { ref in
            guard ref.hasPrefix("graph_candidate:") else { return nil }
            return "cider-cli item graph-candidate \(String(ref.dropFirst("graph_candidate:".count))) --json"
        }
    }

    private func diagnosticRow(
        owner: SecondBrainOwnerRef,
        title: String,
        reasonCode: String,
        matchedTerms: [String],
        sourceRefs: [String],
        sourceSpan: SecondBrainSavedPlacePreferenceLinkSourceSpan? = nil
    ) -> SecondBrainSavedPlacePreferenceLinkDiagnosticRow {
        SecondBrainSavedPlacePreferenceLinkDiagnosticRow(
            owner: owner,
            title: title,
            reasonCode: reasonCode,
            matchedTerms: orderedUnique(matchedTerms),
            sourceRefs: orderedUnique(sourceRefs),
            sourceSpan: sourceSpan,
            safeVerificationCommands: ["cider-cli item context \(owner.ownerType) \(owner.ownerID) --json"]
        )
    }

    private func cuisineTerms(in text: String) -> [String] {
        let normalized = text.lowercased()
        let candidates = [
            "asian", "thai", "japanese", "korean", "chinese", "vietnamese",
            "sushi", "ramen", "pho", "dim sum", "udon", "taco", "tacos", "mexican",
            "italian", "pizza", "indian", "curry", "burger", "bbq", "chicken",
            "sandwich", "sandwiches", "sando", "festival"
        ]
        var terms = candidates.filter { containsTokenBoundedTerm($0, in: normalized) }
        if normalized.contains("bb.q chicken") || normalized.contains("bbq-chicken") {
            terms.append("korean")
        }
        if containsTokenBoundedTerm("sando", in: normalized) {
            terms.append("japanese")
            terms.append("sandwich")
        }
        return orderedUnique(terms)
    }

    private func containsTokenBoundedTerm(_ term: String, in normalizedText: String) -> Bool {
        var searchStart = normalizedText.startIndex
        while let range = normalizedText.range(of: term, options: [], range: searchStart..<normalizedText.endIndex) {
            if isTokenBoundary(before: range.lowerBound, in: normalizedText)
                && isTokenBoundary(after: range.upperBound, in: normalizedText) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    private func isTokenBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        return !text[text.index(before: index)].isAlphaNumeric
    }

    private func isTokenBoundary(after index: String.Index, in text: String) -> Bool {
        guard index < text.endIndex else { return true }
        return !text[index].isAlphaNumeric
    }

    private func savedPlaceClassification(
        title: String,
        url: String,
        ocrText: String,
        extractionOutput: SecondBrainEnrichmentOutput?
    ) -> SavedPlaceClassification {
        let text = "\(title) \(url) \(ocrText)"
        if isNoisyNonPlaceFoodSave(text) {
            return SavedPlaceClassification(isPlace: false, confidence: 0)
        }

        if let extractionOutput {
            let objectTypes = DatabaseHelpers.decodeStringArray(
                extractionOutput.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses]
            )
            if objectTypes.contains("restaurant") || objectTypes.contains("place") {
                return SavedPlaceClassification(isPlace: true, confidence: extractionOutput.confidence ?? 0.72)
            }
        }

        let normalized = text.lowercased()
        let terms = cuisineTerms(in: text)
        guard !terms.isEmpty else {
            return SavedPlaceClassification(isPlace: false, confidence: 0)
        }

        let knownRestaurantHost = normalized.contains("toasttab.com")
        let socialHost = normalized.contains("tiktok.com") || normalized.contains("instagram.com")
        let socialFoodPlaceTitle = socialHost
            && (normalized.contains("restaurant") || normalized.contains("place to try") || normalized.contains("places to try"))
        let restaurantTitleSignal = containsAny(
            normalized,
            [
                "restaurant", " ramen", "sushi", "pho ", "dim sum", "tacos",
                "udon", "bar", "grill", "kitchen", "noodle", "food festival",
                "bb.q chicken", "bbq chicken",
            ]
        )
        let locationHint = containsAny(
            normalized,
            [
                " seattle", " lynnwood", " bellevue", " redmond", " kirkland",
                " cap hill", " capitol hill", " ballard", " fremont",
            ]
        )

        if knownRestaurantHost && (restaurantTitleSignal || locationHint) {
            return SavedPlaceClassification(isPlace: true, confidence: 0.74)
        }
        if socialHost && locationHint && containsAny(normalized, ["#food", "foodie", " pop up ", "popup"]) {
            return SavedPlaceClassification(isPlace: true, confidence: 0.73)
        }
        if socialFoodPlaceTitle {
            return SavedPlaceClassification(isPlace: true, confidence: 0.73)
        }
        if locationHint && normalized.contains("food festival") {
            return SavedPlaceClassification(isPlace: true, confidence: 0.72)
        }
        if restaurantTitleSignal && (title.contains("&") || locationHint || normalized.contains("restaurant")) {
            return SavedPlaceClassification(isPlace: true, confidence: 0.72)
        }
        return SavedPlaceClassification(isPlace: false, confidence: 0)
    }

    private func isNoisyNonPlaceFoodSave(_ text: String) -> Bool {
        containsAny(
            text.lowercased(),
            [
                "/products/", " product", " bowl set", " recipe", "/recipes/",
                "homemade", "reaction clip", "funny ", " meme", "/memes/",
                "game", "movie", "trailer",
            ]
        )
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    private func cuisineAliasMatch(
        bookmarkTerms: [String],
        preferenceTerms: [String]
    ) -> (bookmarkTerm: String, bookmarkDisplay: String, preferenceDisplay: String)? {
        let families: [(display: String, terms: Set<String>)] = [
            ("Mexican", Set(["mexican", "taco", "tacos"])),
            ("Italian", Set(["italian", "pizza"])),
            ("Indian", Set(["indian", "curry"])),
            ("BBQ", Set(["bbq"])),
            ("Korean", Set(["korean", "bbq", "chicken"])),
            ("Japanese", Set(["japanese", "sushi", "ramen", "udon", "sando"])),
            ("Sandwich", Set(["sandwich", "sandwiches", "sando"])),
            ("Food festival", Set(["festival"])),
            ("Asian", Set(["asian", "thai", "japanese", "korean", "chinese", "vietnamese", "sushi", "ramen", "pho", "dim sum", "udon"])),
        ]
        for family in families {
            guard let bookmarkTerm = bookmarkTerms.first(where: { family.terms.contains($0) }),
                  preferenceTerms.contains(where: { family.terms.contains($0) }) else {
                continue
            }
            return (
                bookmarkTerm: bookmarkTerm,
                bookmarkDisplay: displayName(for: bookmarkTerm),
                preferenceDisplay: family.display
            )
        }
        return nil
    }

    private func displayName(for term: String) -> String {
        if term == "bbq" { return "BBQ" }
        if term == "sando" { return "Sando" }
        return term.capitalized
    }

    private struct SourceSentence {
        var text: String
        var startOffset: Int
        var endOffset: Int
    }

    private func foodEvidenceSentences(in text: String) -> [SourceSentence] {
        var sentences: [SourceSentence] = []
        var segmentStart = text.startIndex

        func appendSegment(endingAt segmentEnd: String.Index) {
            var trimmedStart = segmentStart
            var trimmedEnd = segmentEnd
            while trimmedStart < trimmedEnd, text[trimmedStart].isWhitespace {
                trimmedStart = text.index(after: trimmedStart)
            }
            while trimmedEnd > trimmedStart {
                let beforeEnd = text.index(before: trimmedEnd)
                guard text[beforeEnd].isWhitespace else { break }
                trimmedEnd = beforeEnd
            }
            guard trimmedStart < trimmedEnd else { return }
            sentences.append(
                SourceSentence(
                    text: String(text[trimmedStart..<trimmedEnd]),
                    startOffset: text.distance(from: text.startIndex, to: trimmedStart),
                    endOffset: text.distance(from: text.startIndex, to: trimmedEnd)
                )
            )
        }

        var index = text.startIndex
        while index < text.endIndex {
            if ".!?\n".contains(text[index]) {
                appendSegment(endingAt: index)
                segmentStart = text.index(after: index)
            }
            index = text.index(after: index)
        }
        appendSegment(endingAt: text.endIndex)
        return sentences
    }

    private func sourceSpan(
        owner: SecondBrainOwnerRef,
        sourceField: String,
        content: String,
        sentence: SourceSentence,
        sourceEvidenceRef: String?
    ) -> SecondBrainSavedPlacePreferenceLinkSourceSpan {
        let contextStart = max(0, sentence.startOffset - 80)
        let contextEnd = min(content.count, sentence.endOffset + 80)
        let syntheticRef = sourceEvidenceRef ?? "synthetic_source_span:\(owner.ownerType):\(owner.ownerID):\(sentence.startOffset)-\(sentence.endOffset)"
        return SecondBrainSavedPlacePreferenceLinkSourceSpan(
            sourceItemRef: owner.canonicalRef,
            sourceField: sourceField,
            snippet: content.substring(characterStart: contextStart, characterEnd: contextEnd),
            matchedText: sentence.text,
            startOffset: sentence.startOffset,
            endOffset: sentence.endOffset,
            selector: "char:\(sentence.startOffset)..\(sentence.endOffset)",
            sourceEvidenceRef: sourceEvidenceRef,
            syntheticSourceEvidenceRef: sourceEvidenceRef == nil ? syntheticRef : nil,
            truthBoundary: "read_only_source_selector_not_accepted_truth"
        )
    }

    private func isPlanningOrAuditFoodMention(title: String, sentence: String) -> Bool {
        let normalizedTitle = title.lowercased()
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlanningSurface = containsAny(
            normalizedTitle,
            [
                "agent", "audit", "contract", "implementation", "memory-trust",
                "roadmap", "qa", "debug", "test"
            ]
        ) || trimmedSentence.hasPrefix("|")
        return isPlanningSurface && !hasExplicitUserFoodPreferenceCue(sentence)
    }

    private func hasExplicitUserFoodPreferenceCue(_ sentence: String) -> Bool {
        let normalized = " \(sentence.lowercased()) "
        return containsAny(
            normalized,
            [
                " i like ", " i love ", " we like ", " we love ",
                " visher’s preference ", " visher's preference ",
                " user preference ", " user's preference ",
                " user likes ", " user loves ",
                " want to try ", " wants to try ", " wanted to try "
            ]
        )
    }

    private func hasFoodPreferenceCue(_ sentence: String) -> Bool {
        let normalized = " \(sentence.lowercased()) "
        return containsAny(
            normalized,
            [
                " i like ", " i love ", " we like ", " we love ", " favorite", " favourite",
                " craving ", " crave ", " want to try ", " wanted to try ", " wants to try ", " wanting to try ",
                " prefer ", " preference", " into ", " go-to", " dinner win"
            ]
        )
    }

    private func isNoisyOrNegativeFoodPreferenceSentence(_ sentence: String) -> Bool {
        containsAny(
            sentence.lowercased(),
            [
                "do not save", "don't save", "not a preference", "not into", "dislike",
                "recipe", "funny", "meme", "clip", "reaction", "product", "bowl set",
                "trailer", "movie", "game"
            ]
        )
    }

    private func displayPreferenceValue(terms: [String]) -> String {
        let preferred = terms.first(where: { !["chicken", "festival"].contains($0) }) ?? terms.first ?? "food"
        return "\(displayName(for: preferred)) food"
    }

    private func normalizedWords(_ text: String) -> Set<String> {
        Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    private func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

private extension String {
    func substring(characterStart: Int, characterEnd: Int) -> String {
        let safeStart = max(0, min(count, characterStart))
        let safeEnd = max(safeStart, min(count, characterEnd))
        let start = index(startIndex, offsetBy: safeStart)
        let end = index(startIndex, offsetBy: safeEnd)
        return String(self[start..<end])
    }
}

private extension Character {
    var isAlphaNumeric: Bool {
        unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
    }
}
