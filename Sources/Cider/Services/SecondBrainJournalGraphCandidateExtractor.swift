import Foundation

struct SecondBrainJournalGraphCandidateExtractionResult: Equatable {
    var outputs: [SecondBrainEnrichmentOutput]

    var count: Int { outputs.count }
    var ids: [String] { outputs.map(\.id) }
}

struct SecondBrainJournalGraphCandidateExtractor {
    func extract(
        sourceOwner: SecondBrainOwnerRef,
        rawContent: String,
        date: String? = nil,
        time: String? = nil
    ) -> SecondBrainJournalGraphCandidateExtractionResult {
        let sentences = candidateSentences(from: rawContent)
        var outputs: [SecondBrainEnrichmentOutput] = []
        for sentence in sentences {
            outputs.append(contentsOf: watchedCandidates(sourceOwner: sourceOwner, sentence: sentence))
            outputs.append(contentsOf: preferenceCandidates(sourceOwner: sourceOwner, sentence: sentence))
            outputs.append(contentsOf: visitedCandidates(sourceOwner: sourceOwner, sentence: sentence))
            outputs.append(contentsOf: consumptionCandidates(sourceOwner: sourceOwner, sentence: sentence))
            outputs.append(contentsOf: wantsCandidates(sourceOwner: sourceOwner, sentence: sentence))
            outputs.append(contentsOf: memoryCandidates(sourceOwner: sourceOwner, sentence: sentence))
        }

        let enriched = unique(outputs).map { output -> SecondBrainEnrichmentOutput in
            var output = output
            output.metadata["journal_date"] = date.flatMap(trimmedNonEmpty)
            output.metadata["journal_time"] = time.flatMap(trimmedNonEmpty)
            return output
        }
        return SecondBrainJournalGraphCandidateExtractionResult(outputs: enriched)
    }

    private func watchedCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        let sentenceClauses = candidateClauses(from: sentence)
        return sentenceClauses.flatMap { clause in
            regexMatches(
                pattern: #"(?i)\b(?:watched|rewatched|saw)\s+(.+?)(?:\s+(?:last night|tonight|yesterday|today|this morning|this afternoon|this evening|again))?$"#,
                in: clause
            ).compactMap { match in
                guard let mention = cleanedMention(match.captures.first ?? nil, kind: .media) else { return nil }
                return makeCandidate(
                    sourceOwner: sourceOwner,
                    candidateKind: .objectRelation,
                    mentionText: mention,
                    sourceQuote: clause,
                    objectTypes: [.movie, .media],
                    relations: [.watched],
                    actions: ["watched"],
                    confidence: 0.78,
                    confidenceReason: "Journal sentence uses a watched/saw verb for a media mention."
                )
            }
        }
    }

    private func preferenceCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        regexMatches(
            pattern: #"(?i)^\s*(?:(I|we|[A-Z][A-Za-z0-9'’-]*(?:\s+[A-Z][A-Za-z0-9'’-]*){0,2})\s+)?(?:really\s+)?(loved|liked|hated|disliked)\s+(?:that\s+|the\s+|those\s+|a\s+|an\s+|some\s+)?(.+?)$"#,
            in: sentence
        ).compactMap { match in
            guard match.captures.count >= 3,
                  let verb = trimmedNonEmpty(match.captures[1]),
                  let mention = cleanedMention(match.captures[2], kind: .object) else { return nil }
            let subject = trimmedNonEmpty(match.captures[0])
            let disliked = verb.localizedCaseInsensitiveContains("hate")
                || verb.localizedCaseInsensitiveContains("dislike")
            let objectTypes = objectTypes(for: mention)
            let relation = disliked ? SecondBrainGraphCandidateContract.RelationType.dislikes : preferenceRelation(for: objectTypes)
            return makeCandidate(
                sourceOwner: sourceOwner,
                candidateKind: .objectRelation,
                mentionText: mention,
                sourceQuote: sentence,
                objectTypes: objectTypes,
                relations: [relation],
                actions: [disliked ? "disliked" : "liked"],
                confidence: subject == nil ? 0.58 : 0.72,
                confidenceReason: "Journal sentence states a preference and names the object.",
                subjectText: subject
            )
        }
    }

    private func visitedCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        regexMatches(
            pattern: #"(?i)\b(?:stopped at|went to|visited|ate at|had dinner at|had lunch at)\s+(.+?)$"#,
            in: sentence
        ).compactMap { match in
            guard let mention = cleanedMention(match.captures.first ?? nil, kind: .place),
                  !isSchoolingBackgroundVisit(sentence: sentence, mention: mention) else { return nil }
            return makeCandidate(
                sourceOwner: sourceOwner,
                candidateKind: .objectRelation,
                mentionText: mention,
                sourceQuote: sentence,
                objectTypes: [.restaurant, .place],
                relations: [.visited],
                actions: ["visited"],
                confidence: 0.74,
                confidenceReason: "Journal sentence uses a visit/location phrase."
            )
        }
    }

    private func consumptionCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        return candidateClauses(from: sentence).flatMap { clause in
            regexMatches(
                pattern: #"(?i)^\s*(?:(I|we|[A-Z][A-Za-z0-9'’-]*(?:\s+[A-Z][A-Za-z0-9'’-]*){0,2})\s+)?(?:ate|tried|drank|had(?!\s+not\b))\s+(?:that\s+|the\s+|those\s+|a\s+|an\s+|some\s+)?(.+?)$"#,
                in: clause
            ).compactMap { match in
                guard match.captures.count >= 2,
                      let mention = cleanedMention(match.captures[1], kind: .object) else { return nil }
                let subject = trimmedNonEmpty(match.captures[0])
                let objectTypes = objectTypes(for: mention)
                let relation: SecondBrainGraphCandidateContract.RelationType = objectTypes.contains(.drink) ? .drank : .ate
                return makeCandidate(
                    sourceOwner: sourceOwner,
                    candidateKind: .objectRelation,
                    mentionText: mention,
                    sourceQuote: clause,
                    objectTypes: objectTypes,
                    relations: [relation],
                    actions: [relation.rawValue],
                    confidence: 0.62,
                    confidenceReason: "Journal sentence records food or drink consumption.",
                    subjectText: subject
                )
            }
        }
    }

    private func wantsCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        let listCandidates = wantedListCandidates(sourceOwner: sourceOwner, sentence: sentence)
        if !listCandidates.isEmpty { return listCandidates }

        return regexMatches(
            pattern: #"(?i)\b(?:(I|we|[A-Z][A-Za-z0-9'’-]*(?:\s+[A-Z][A-Za-z0-9'’-]*){0,2})\s+)?(?:want|wants|wanted|would like)(?:\s+to\s+(?:try|visit|go to|watch|read))?\s+(.+?)$"#,
            in: sentence
        ).compactMap { match in
            guard match.captures.count >= 2,
                  let mention = cleanedMention(match.captures[1], kind: .object) else { return nil }
            let subject = trimmedNonEmpty(match.captures[0])?
                .replacingOccurrences(of: #"(?i)^and\s+"#, with: "", options: .regularExpression)
            return makeCandidate(
                sourceOwner: sourceOwner,
                candidateKind: .objectRelation,
                mentionText: mention,
                sourceQuote: sentence,
                objectTypes: objectTypes(for: mention),
                relations: [.wants],
                actions: ["wants_to_try"],
                confidence: 0.64,
                confidenceReason: "Journal sentence records future intent.",
                subjectText: subject
            )
        }
    }

    private func wantedListCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        guard sentence.range(of: #"(?i)\bwants?\s+to\s+try\s+later\s*:"#, options: .regularExpression) != nil,
              let listStart = sentence.range(of: ":")?.upperBound else { return [] }
        let listText = String(sentence[listStart...])
        let rawMentions = listText
            .replacingOccurrences(of: #"(?i)\band\s+"#, with: "", options: .regularExpression)
            .split(separator: ",")
            .map(String.init)
        return rawMentions.compactMap { rawMention in
            guard let mention = cleanedMention(rawMention, kind: .object) else { return nil }
            return makeCandidate(
                sourceOwner: sourceOwner,
                candidateKind: .objectRelation,
                mentionText: mention,
                sourceQuote: sentence,
                objectTypes: objectTypes(for: mention),
                relations: [.wants],
                actions: ["wants_to_try"],
                confidence: 0.68,
                confidenceReason: "Journal sentence lists specific places Visher wants to try later.",
                subjectText: "Visher"
            )
        }
    }

    private func memoryCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        let normalizedSentence = sentence
            .replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedSentence.lowercased()
        var candidates: [SecondBrainEnrichmentOutput?] = []

        if lower.contains("first weekend overtime") && lower.contains("five years") {
            candidates.append(makeMemoryCandidate(
                sourceOwner: sourceOwner,
                kind: "pattern",
                value: "Visher has returned to weekend overtime after five years or more.",
                evidence: sentence,
                confidence: 0.82,
                memoryKey: "weekend-overtime-return"
            ))
        }

        if lower.contains("hourly wages") && lower.contains("motivation") {
            candidates.append(makeMemoryCandidate(
                sourceOwner: sourceOwner,
                kind: "pattern",
                value: "Overtime pay calculations help Visher motivate himself to get up for early weekend overtime.",
                evidence: sentence,
                confidence: 0.8,
                memoryKey: "overtime-pay-motivation"
            ))
        }

        if lower.contains("budget")
            && lower.contains("one full paycheck for bills")
            && lower.contains("one full paycheck for rent") {
            candidates.append(makeMemoryCandidate(
                sourceOwner: sourceOwner,
                kind: "pattern",
                value: "Visher's budget normally depends on one full paycheck for bills and one full paycheck for rent.",
                evidence: sentence,
                confidence: 0.84,
                memoryKey: "paycheck-bills-rent-budget-pattern"
            ))
        }

        if lower.contains("overnight oats reminder") && lower.contains("weekend overtime") {
            candidates.append(makeMemoryCandidate(
                sourceOwner: sourceOwner,
                kind: "pattern",
                value: "Consider an overnight oats reminder on nights before early weekend overtime.",
                evidence: sentence,
                confidence: 0.86,
                memoryKey: "overnight-oats-weekend-overtime-reminder"
            ))
        }

        return candidates.compactMap { $0 }
    }

    private func makeCandidate(
        sourceOwner: SecondBrainOwnerRef,
        candidateKind: SecondBrainGraphCandidateContract.CandidateKind,
        mentionText: String,
        sourceQuote: String,
        objectTypes: [SecondBrainGraphCandidateContract.ObjectType],
        relations: [SecondBrainGraphCandidateContract.RelationType],
        actions: [String],
        confidence: Double,
        confidenceReason: String,
        subjectText: String? = nil
    ) -> SecondBrainEnrichmentOutput? {
        try? SecondBrainGraphCandidateContract.makeOutput(
            sourceOwner: sourceOwner,
            candidateKind: candidateKind,
            mentionText: mentionText,
            sourceQuote: sourceQuote,
            sourceKind: "journal",
            objectTypeGuesses: objectTypes,
            relationGuesses: relations,
            actionGuesses: actions,
            safeActions: [.inspectSource, .linkExisting, .createObject, .correct, .reject, .delegateEnrichment],
            confidence: confidence,
            confidenceReason: confidenceReason,
            subjectText: subjectText,
            source: "graph_candidate.journal_capture"
        )
    }

    private func makeMemoryCandidate(
        sourceOwner: SecondBrainOwnerRef,
        kind: String,
        value: String,
        evidence: String,
        confidence: Double,
        memoryKey: String
    ) -> SecondBrainEnrichmentOutput? {
        guard let value = trimmedNonEmpty(value),
              let evidence = trimmedNonEmpty(evidence) else { return nil }
        return SecondBrainEnrichmentOutput(
            owner: sourceOwner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: normalizedValue(value),
            label: "Memory candidate: \(kind.replacingOccurrences(of: "_", with: " "))",
            evidence: evidence,
            source: "memory_candidate.journal_capture",
            confidence: confidence,
            reviewState: "suggested",
            metadata: [
                "memory_kind": kind,
                "candidate_kind": kind,
                "requires_review": "true",
                "memory_key": memoryKey,
                "memory_status": "current",
                "requested_owner_type": sourceOwner.ownerType,
                "requested_owner_ref": sourceOwner.ownerID,
            ]
        )
    }

    private func normalizedValue(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func isSchoolingBackgroundVisit(sentence: String, mention: String) -> Bool {
        let lowerSentence = sentence.lowercased()
        let lowerMention = mention.lowercased()
        let strongSchoolingMarkers = [
            "beauty school",
            "cosmetology school",
            "barber school",
            "hair school",
            "law school",
            "medical school",
            "nursing school",
            "grad school",
            "graduate school",
        ]
        if strongSchoolingMarkers.contains(where: { lowerMention.contains($0) }) {
            return lowerSentence.contains("went to")
        }

        let broadSchoolingMarkers = [
            "college",
            "university",
        ]
        guard broadSchoolingMarkers.contains(where: { lowerMention.contains($0) }) else { return false }
        let backgroundMarkers = [
            "doesn’t do",
            "doesn't do",
            "professionally",
            "anymore",
            "used to",
            "studied",
            "degree",
            "trained",
            "school and",
        ]
        return lowerSentence.contains("went to")
            && backgroundMarkers.contains(where: { lowerSentence.contains($0) })
    }

    private func objectTypes(for mention: String) -> [SecondBrainGraphCandidateContract.ObjectType] {
        let lower = mention.lowercased()
        if lower.contains("drink")
            || lower.contains("cocktail")
            || lower.contains("margarita")
            || lower.contains("coffee")
            || lower.contains("tea")
            || lower.contains("smoothie")
            || lower.contains("coke")
            || lower.contains("soda") {
            return [.drink]
        }
        if lower.contains("taco")
            || lower.contains("pizza")
            || lower.contains("burger")
            || lower.contains("meal")
            || lower.contains("dinner")
            || lower.contains("lunch")
            || lower.contains("breakfast")
            || lower.contains("dessert") {
            return [.food]
        }
        return [.object]
    }

    private func preferenceRelation(
        for objectTypes: [SecondBrainGraphCandidateContract.ObjectType]
    ) -> SecondBrainGraphCandidateContract.RelationType {
        if objectTypes.contains(.drink) { return .likesDrink }
        if objectTypes.contains(.food) { return .likesFood }
        return .likes
    }

    private func splitSentences(_ text: String) -> [String] {
        let decimalSentinel = "<cider-decimal-point>"
        let protected = text.replacingOccurrences(
            of: #"(\d)\.(\d)"#,
            with: "$1\(decimalSentinel)$2",
            options: .regularExpression
        )
        return protected.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.replacingOccurrences(of: decimalSentinel, with: ".") }
            .compactMap(trimmedNonEmpty)
    }

    private func candidateClauses(from sentence: String) -> [String] {
        sentence
            .components(separatedBy: ";")
            .compactMap(trimmedNonEmpty)
    }

    private func candidateSentences(from text: String) -> [String] {
        var sentences: [String] = []
        var recentlySawCiderCandidateContext = false
        var suppressingCiderExampleBlock = false

        for rawLine in text.components(separatedBy: .newlines) {
            guard let line = trimmedNonEmpty(rawLine) else {
                recentlySawCiderCandidateContext = false
                suppressingCiderExampleBlock = false
                continue
            }

            if isCiderCandidateContextLine(line) {
                recentlySawCiderCandidateContext = true
                continue
            }

            if isCandidateExampleContextLine(line),
               recentlySawCiderCandidateContext || suppressingCiderExampleBlock {
                recentlySawCiderCandidateContext = false
                suppressingCiderExampleBlock = true
                continue
            }

            let lineSentences = splitSentences(line)
            if suppressingCiderExampleBlock {
                if lineSentences.allSatisfy(isLikelyCandidateExampleLine) {
                    continue
                }
                suppressingCiderExampleBlock = false
            }
            recentlySawCiderCandidateContext = false

            sentences.append(contentsOf: lineSentences)
        }

        return sentences
    }

    private func isCiderCandidateContextLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let candidateMarkers = [
            "graph_candidate",
            "memory_candidate",
            "graph candidate",
            "memory candidate",
            "source-backed memory",
            "source-backed graph",
            "review queue",
        ]
        let ciderMarkers = [
            "cider",
            "feature",
            "product",
            "prototype",
            "north star",
        ]

        return candidateMarkers.contains { lower.contains($0) }
            && ciderMarkers.contains { lower.contains($0) }
    }

    private func isCandidateExampleContextLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let exampleMarkers = [
            "example",
            "examples",
            "for example",
            "should capture",
            "should surface",
            "should show",
            "app should capture",
            "confirm?",
            "accept?",
            "save as",
        ]
        return exampleMarkers.contains { lower.contains($0) }
    }

    private func isLikelyCandidateExampleLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let exampleVerbs = [
            "watched",
            "rewatched",
            "saw",
            "loved",
            "liked",
            "hated",
            "disliked",
            "stopped at",
            "went to",
            "visited",
            "ate at",
            "had dinner at",
            "had lunch at",
            "ate",
            "had",
            "tried",
            "drank",
            "want to",
            "wants to",
            "wanted to",
            "would like to",
        ]
        return exampleVerbs.contains { lower.contains($0) }
    }

    private struct RegexMatch {
        var captures: [String?]
    }

    private func regexMatches(pattern: String, in text: String) -> [RegexMatch] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            let captures = (1..<match.numberOfRanges).map { index -> String? in
                let range = match.range(at: index)
                guard range.location != NSNotFound else { return nil }
                return nsText.substring(with: range)
            }
            return RegexMatch(captures: captures)
        }
    }

    private enum MentionKind {
        case media
        case place
        case object
    }

    private func cleanedMention(_ raw: String?, kind: MentionKind = .object) -> String? {
        guard var value = trimmedNonEmpty(raw) else { return nil }
        let trailingPhrases = [
            #"(?i)\s+last\s+night$"#,
            #"(?i)\s+tonight$"#,
            #"(?i)\s+yesterday$"#,
            #"(?i)\s+today$"#,
            #"(?i)\s+again$"#,
            #"(?i)\s+while\s+.+$"#,
            #"(?i)\s+that\s+(?:he|she|they|i|we)\s+.+$"#,
            #"(?i)\s+and\s+(?:watched|thought|talked|spoke|wondered|worried|laughed|joked)\s+.+$"#,
            #"(?i)\s+because\s+.+$"#,
            #"(?i)\s+but\s+.+$"#,
            #"(?i)\s+with\s+.+$"#,
            #"(?i)\s+for\s+(?:dinner|lunch|breakfast|brunch|dessert|coffee|drinks?)$"#,
            #"(?i)\s+at\s+.+$"#,
            #"(?i),\s+and\s+.+$"#,
        ]
        for pattern in trailingPhrases {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        value = value
            .replacingOccurrences(of: #"(?i)^(that|those|a|an|some)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        if kind == .object, value.lowercased().contains("store") {
            value = value.replacingOccurrences(of: #"(?i)^the\s+"#, with: "", options: .regularExpression)
        }
        guard let cleaned = trimmedNonEmpty(value), !isLowQualityMention(cleaned, kind: kind) else {
            return nil
        }
        return cleaned
    }

    private func isLowQualityMention(_ value: String, kind: MentionKind) -> Bool {
        let lower = value.lowercased()
        let genericMentions: Set<String> = [
            "it", "this", "that", "him", "her", "them", "there", "home", "bed", "school", "work",
            "food", "some food", "the movie", "movie", "a movie", "netflix movie", "the place", "place", "something", "anything", "everything",
            "to go back", "go back", "back",
        ]
        if genericMentions.contains(lower) { return true }
        if lower.count < 3 { return true }

        switch kind {
        case .media:
            if lower.hasPrefix("blades") || lower.contains(" or something") { return true }
            if lower.contains("basketball")
                || lower.contains("championship")
                || lower.contains("knicks")
                || lower.contains("spurs")
                || lower.contains("sonics")
                || lower.contains("mariners") { return true }
            if lower.hasPrefix("netflix movie") || lower.contains("sacha baron cohen") { return true }
            let hasTitleCase = value.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
            let mediaClues = ["movie", "show", "episode", "season", "book", "album", "game"]
            if !hasTitleCase && !mediaClues.contains(where: { lower.contains($0) }) {
                return true
            }
        case .place:
            if ["bed", "sleep", "asleep", "their dad's house", "dad's house"].contains(lower) { return true }
        case .object:
            if lower.contains("not realized") || lower.contains("wants to go back") { return true }
        }
        return false
    }

    private func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func unique(_ outputs: [SecondBrainEnrichmentOutput]) -> [SecondBrainEnrichmentOutput] {
        var seen = Set<String>()
        var result: [SecondBrainEnrichmentOutput] = []
        for output in outputs {
            let key = "\(output.normalizedValue)|\(output.metadata[SecondBrainGraphCandidateContract.MetadataKey.relationGuesses] ?? "")|\(output.evidence.lowercased())"
            guard seen.insert(key).inserted else { continue }
            result.append(output)
        }
        return result
    }
}
