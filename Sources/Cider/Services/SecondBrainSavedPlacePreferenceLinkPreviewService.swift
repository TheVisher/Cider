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

struct SecondBrainSavedPlacePreferenceLinkPreviewReport: Codable, Equatable {
    var readOnly: Bool = true
    var changed: Bool = false
    var truthBoundary: String = "reviewable_candidate_not_truth"
    var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate]
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

    private struct PreferenceEvidence {
        var output: SecondBrainEnrichmentOutput
        var sourceEvidenceRef: String?
    }

    private let database: CiderDatabase

    init(database: CiderDatabase = .shared) {
        self.database = database
    }

    func preview(limit: Int = 20) throws -> SecondBrainSavedPlacePreferenceLinkPreviewReport {
        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else {
            return report(candidates: [])
        }

        let bookmarks = try savedPlaceBookmarks()
        let preferences = try journalFoodPreferences()
        var candidates: [SecondBrainSavedPlacePreferenceLinkCandidate] = []

        for bookmark in bookmarks {
            for preference in preferences {
                guard let match = match(bookmark: bookmark, preference: preference.output) else { continue }
                candidates.append(candidate(bookmark: bookmark, preference: preference, match: match))
            }
        }

        candidates.sort {
            if $0.confidence != $1.confidence { return $0.confidence > $1.confidence }
            return $0.savedItem.title.localizedCaseInsensitiveCompare($1.savedItem.title) == .orderedAscending
        }
        return report(candidates: Array(candidates.prefix(boundedLimit)))
    }

    private func report(candidates: [SecondBrainSavedPlacePreferenceLinkCandidate]) -> SecondBrainSavedPlacePreferenceLinkPreviewReport {
        let safeCommands = ["cider-cli item saved-place-preference-links --json"]
        return SecondBrainSavedPlacePreferenceLinkPreviewReport(
            candidates: candidates,
            safeVerificationCommands: safeCommands,
            safeNextCommands: safeCommands
        )
    }

    private func savedPlaceBookmarks() throws -> [SavedBookmark] {
        let stmt = try database.prepare("""
            SELECT i.id, i.title, i.relative_path, b.url
            FROM items i
            JOIN bookmarks b ON b.item_id = i.id
            WHERE i.type = 'bookmark'
            ORDER BY i.created_at DESC, i.title COLLATE NOCASE ASC;
            """)

        var bookmarks: [SavedBookmark] = []
        while try stmt.step() {
            let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: stmt.string(at: 0))
            let title = stmt.string(at: 1)
            let relativePath = stmt.optionalString(at: 2)
            let url = stmt.string(at: 3)
            let extraction = SecondBrainBookmarkGraphCandidateExtractor().extract(
                sourceOwner: owner,
                urlString: url,
                title: title
            )
            guard let output = extraction.outputs.first else { continue }
            let objectTypes = DatabaseHelpers.decodeStringArray(
                output.metadata[SecondBrainGraphCandidateContract.MetadataKey.objectTypeGuesses]
            )
            guard objectTypes.contains("restaurant") || objectTypes.contains("place") else { continue }
            let terms = cuisineTerms(in: "\(title) \(url)")
            guard !terms.isEmpty else { continue }
            bookmarks.append(
                SavedBookmark(
                    owner: owner,
                    title: title,
                    url: url,
                    relativePath: relativePath,
                    placeTerms: terms,
                    bookmarkConfidence: output.confidence ?? 0.72
                )
            )
        }
        return bookmarks
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
                    reason: "Saved restaurant looks \(term.capitalized) and journal evidence says the user likes Asian food."
                )
            }
        }

        if let term = bookmark.placeTerms.first(where: { preferenceText.contains($0) || preferenceTerms.contains($0) }) {
            return Match(
                term: term,
                confidence: min(0.92, max(bookmark.bookmarkConfidence, preference.confidence ?? 0.76) - 0.08),
                reason: "Saved restaurant and journal preference share '\(term)'."
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
            reasonCodes: ["saved_restaurant_matches_food_preference", "source_backed_journal_preference", "read_only_preview"],
            sourceRefs: sourceRefs,
            truthBoundary: "reviewable_candidate_not_truth",
            safeVerificationCommands: safeVerificationCommands,
            safeNextCommands: safeNextCommands
        )
    }

    private func cuisineTerms(in text: String) -> [String] {
        let normalized = " \(text.lowercased()) "
        let candidates = [
            "asian", "thai", "japanese", "korean", "chinese", "vietnamese",
            "sushi", "ramen", "pho", "dim sum", "taco", "tacos", "mexican",
            "italian", "pizza", "indian", "curry", "burger", "bbq"
        ]
        return candidates.filter { term in
            normalized.contains(" \(term) ") || normalized.contains("-\(term)-") || normalized.contains("/\(term)")
        }
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
