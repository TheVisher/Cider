import Foundation

struct SecondBrainSavedPlacePreferenceLinkPreviewSource: Codable, Equatable {
    var owner: SecondBrainOwnerRef
    var title: String
    var snippet: String
    var url: String?
    var relativePath: String?
    var sourceEvidenceRef: String?
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
}

struct SecondBrainSavedPlacePreferenceLinkDiagnostics: Codable, Equatable {
    var inspectedBookmarkCount: Int
    var savedPlaceBookmarkCount: Int
    var preferenceEvidenceCount: Int
    var candidateCount: Int
    var skippedBookmarkSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    var noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
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
        var output: SecondBrainEnrichmentOutput
        var sourceEvidenceRef: String?
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
                    noMatchSamples: []
                )
            )
        }

        let bookmarkScan = try savedPlaceBookmarks()
        let preferences = try journalFoodPreferences()
        var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate] = []
        var noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow] = []

        for bookmark in bookmarkScan.bookmarks {
            var matchedBookmark = false
            for preference in preferences {
                guard let match = match(bookmark: bookmark, preference: preference.output) else { continue }
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
                noMatchSamples: noMatchSamples
            )
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

    private func diagnostics(
        inspectedBookmarkCount: Int,
        savedPlaceBookmarkCount: Int,
        preferenceEvidenceCount: Int,
        candidateCount: Int,
        skippedBookmarkSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow],
        noMatchSamples: [SecondBrainSavedPlacePreferenceLinkDiagnosticRow]
    ) -> SecondBrainSavedPlacePreferenceLinkDiagnostics {
        SecondBrainSavedPlacePreferenceLinkDiagnostics(
            inspectedBookmarkCount: inspectedBookmarkCount,
            savedPlaceBookmarkCount: savedPlaceBookmarkCount,
            preferenceEvidenceCount: preferenceEvidenceCount,
            candidateCount: candidateCount,
            skippedBookmarkSamples: Array(skippedBookmarkSamples.prefix(20)),
            noMatchSamples: Array(noMatchSamples.prefix(20))
        )
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

    private func journalFoodPreferences() throws -> [PreferenceEvidence] {
        let outputs = try SecondBrainEnrichmentOutputService(database: database).outputs(
            kind: SecondBrainGraphCandidateContract.outputKind,
            reviewStates: nil,
            limit: nil
        )
        return outputs.compactMap { output in
            guard output.metadata[SecondBrainGraphCandidateContract.MetadataKey.sourceKind] == "journal" else { return nil }
            let objectTypes = DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses])
            let relations = DatabaseHelpers.decodeStringArray(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses])
            guard objectTypes.contains("food") || objectTypes.contains("restaurant") || objectTypes.contains("place") else { return nil }
            guard relations.contains("likes_food") || relations.contains("likes") else { return nil }
            let evidenceRef = output.metadata["source_evidence_ref"]
            return PreferenceEvidence(output: output, sourceEvidenceRef: evidenceRef)
        }
    }

    private struct Match {
        var term: String
        var confidence: Double
        var reason: String
        var reasonCodes: [String]
    }

    private func match(bookmark: SavedBookmark, preference: SecondBrainEnrichmentOutput) -> Match? {
        let preferenceText = normalizedWords(preference.value)
        let preferenceTerms = cuisineTerms(in: preference.value)
        if preferenceTerms.contains("asian") {
            let asianTerms = Set(["asian", "thai", "japanese", "korean", "chinese", "vietnamese", "sushi", "ramen", "pho", "dim sum"])
            if let term = bookmark.placeTerms.first(where: { asianTerms.contains($0) }) {
                return Match(
                    term: term,
                    confidence: min(0.96, max(bookmark.bookmarkConfidence, preference.confidence ?? 0.78) - 0.05),
                    reason: "Saved restaurant looks \(term.capitalized) and journal evidence says the user likes Asian food.",
                    reasonCodes: ["saved_restaurant_matches_food_preference", "source_backed_journal_preference", "cuisine_alias_family_match", "read_only_preview"]
                )
            }
        }

        if let aliasMatch = cuisineAliasMatch(bookmarkTerms: bookmark.placeTerms, preferenceTerms: preferenceTerms) {
            return Match(
                term: aliasMatch.bookmarkTerm,
                confidence: min(0.93, max(bookmark.bookmarkConfidence, preference.confidence ?? 0.76) - 0.06),
                reason: "Saved restaurant looks \(aliasMatch.bookmarkDisplay) and journal evidence says the user likes \(aliasMatch.preferenceDisplay) food.",
                reasonCodes: ["saved_restaurant_matches_food_preference", "source_backed_journal_preference", "cuisine_alias_family_match", "read_only_preview"]
            )
        }

        if let term = bookmark.placeTerms.first(where: { preferenceText.contains($0) || preferenceTerms.contains($0) }) {
            return Match(
                term: term,
                confidence: min(0.92, max(bookmark.bookmarkConfidence, preference.confidence ?? 0.76) - 0.08),
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
        let output = preference.output
        let evidenceOwner = output.owner
        let sourceRefs = orderedUnique([
            bookmark.owner.canonicalRef,
            evidenceOwner.canonicalRef,
            "graph_candidate:\(output.id)",
            preference.sourceEvidenceRef,
        ].compactMap { $0 })
        let safeVerificationCommands = [
            "cider-cli item context bookmark \(bookmark.owner.ownerID) --json",
            "cider-cli item context \(evidenceOwner.ownerType) \(evidenceOwner.ownerID) --json",
            "cider-cli item graph-candidate \(output.id) --json",
        ]
        let safeNextCommands = [
            "cider-cli item context bookmark \(bookmark.owner.ownerID) --json",
            "cider-cli item context \(evidenceOwner.ownerType) \(evidenceOwner.ownerID) --json",
            "cider-cli item graph-candidate \(output.id) --json",
        ]
        return SecondBrainSavedPlacePreferenceLinkCandidate(
            id: "saved_place_preference:\(bookmark.owner.ownerID):\(output.id)",
            savedItem: SecondBrainSavedPlacePreferenceLinkPreviewSource(
                owner: bookmark.owner,
                title: bookmark.title,
                snippet: "\(bookmark.title) - \(bookmark.url)",
                url: bookmark.url,
                relativePath: bookmark.relativePath
            ),
            evidenceItem: SecondBrainSavedPlacePreferenceLinkPreviewSource(
                owner: evidenceOwner,
                title: "Journal preference evidence",
                snippet: output.evidence,
                url: nil,
                relativePath: nil,
                sourceEvidenceRef: preference.sourceEvidenceRef
            ),
            preferenceValue: output.value,
            confidence: match.confidence,
            reason: match.reason,
            reasonCodes: match.reasonCodes,
            sourceRefs: sourceRefs,
            truthBoundary: "reviewable_candidate_not_truth",
            safeVerificationCommands: safeVerificationCommands,
            safeNextCommands: safeNextCommands
        )
    }

    private func diagnosticRow(
        owner: SecondBrainOwnerRef,
        title: String,
        reasonCode: String,
        matchedTerms: [String],
        sourceRefs: [String]
    ) -> SecondBrainSavedPlacePreferenceLinkDiagnosticRow {
        SecondBrainSavedPlacePreferenceLinkDiagnosticRow(
            owner: owner,
            title: title,
            reasonCode: reasonCode,
            matchedTerms: orderedUnique(matchedTerms),
            sourceRefs: orderedUnique(sourceRefs)
        )
    }

    private func cuisineTerms(in text: String) -> [String] {
        let normalized = " \(text.lowercased()) "
        let candidates = [
            "asian", "thai", "japanese", "korean", "chinese", "vietnamese",
            "sushi", "ramen", "pho", "dim sum", "udon", "taco", "tacos", "mexican",
            "italian", "pizza", "indian", "curry", "burger", "bbq"
        ]
        var terms = candidates.filter { term in
            normalized.contains(" \(term) ")
                || normalized.contains("-\(term)-")
                || normalized.contains("/\(term)")
                || normalized.contains("#\(term)")
        }
        if normalized.contains("bb.q chicken") || normalized.contains("bbq-chicken") {
            terms.append("korean")
        }
        if normalized.contains(" sando ") || normalized.contains("-sando") || normalized.contains("/sando") {
            terms.append("japanese")
        }
        return orderedUnique(terms)
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
            ("Asian", Set(["asian", "thai", "japanese", "korean", "chinese", "vietnamese", "sushi", "ramen", "pho", "dim sum"])),
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
        return term.capitalized
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
