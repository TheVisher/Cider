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
        regexMatches(
            pattern: #"(?i)\b(?:watched|rewatched|saw)\s+(.+?)(?:\s+(?:last night|tonight|yesterday|today|this morning|this afternoon|this evening|again))?$"#,
            in: sentence
        ).compactMap { match in
            guard let mention = cleanedMention(match.captures.first ?? nil) else { return nil }
            return makeCandidate(
                sourceOwner: sourceOwner,
                candidateKind: .objectRelation,
                mentionText: mention,
                sourceQuote: sentence,
                objectTypes: [.movie, .media],
                relations: [.watched],
                actions: ["watched"],
                confidence: 0.78,
                confidenceReason: "Journal sentence uses a watched/saw verb for a media mention."
            )
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
                  let mention = cleanedMention(match.captures[2]) else { return nil }
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
            guard let mention = cleanedMention(match.captures.first ?? nil) else { return nil }
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
        regexMatches(
            pattern: #"(?i)^\s*(?:(I|we|[A-Z][A-Za-z0-9'’-]*(?:\s+[A-Z][A-Za-z0-9'’-]*){0,2})\s+)?(?:ate|had|tried|drank)\s+(?:that\s+|the\s+|those\s+|a\s+|an\s+|some\s+)?(.+?)$"#,
            in: sentence
        ).compactMap { match in
            guard match.captures.count >= 2,
                  let mention = cleanedMention(match.captures[1]) else { return nil }
            let subject = trimmedNonEmpty(match.captures[0])
            let objectTypes = objectTypes(for: mention)
            let relation: SecondBrainGraphCandidateContract.RelationType = objectTypes.contains(.drink) ? .drank : .ate
            return makeCandidate(
                sourceOwner: sourceOwner,
                candidateKind: .objectRelation,
                mentionText: mention,
                sourceQuote: sentence,
                objectTypes: objectTypes,
                relations: [relation],
                actions: [relation.rawValue],
                confidence: 0.62,
                confidenceReason: "Journal sentence records food or drink consumption.",
                subjectText: subject
            )
        }
    }

    private func wantsCandidates(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String
    ) -> [SecondBrainEnrichmentOutput] {
        regexMatches(
            pattern: #"(?i)^\s*(?:(I|we|[A-Z][A-Za-z0-9'’-]*(?:\s+[A-Z][A-Za-z0-9'’-]*){0,2})\s+)?(?:want|wants|wanted|would like)\s+to\s+(?:try|visit|go to|watch|read)\s+(.+?)$"#,
            in: sentence
        ).compactMap { match in
            guard match.captures.count >= 2,
                  let mention = cleanedMention(match.captures[1]) else { return nil }
            let subject = trimmedNonEmpty(match.captures[0])
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

    private func objectTypes(for mention: String) -> [SecondBrainGraphCandidateContract.ObjectType] {
        let lower = mention.lowercased()
        if lower.contains("drink")
            || lower.contains("cocktail")
            || lower.contains("margarita")
            || lower.contains("coffee")
            || lower.contains("tea")
            || lower.contains("smoothie") {
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
        text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
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

    private func cleanedMention(_ raw: String?) -> String? {
        guard var value = trimmedNonEmpty(raw) else { return nil }
        let trailingPhrases = [
            #"(?i)\s+last\s+night$"#,
            #"(?i)\s+tonight$"#,
            #"(?i)\s+yesterday$"#,
            #"(?i)\s+today$"#,
            #"(?i)\s+again$"#,
            #"(?i)\s+with\s+.+$"#,
            #"(?i)\s+at\s+.+$"#,
        ]
        for pattern in trailingPhrases {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        value = value
            .replacingOccurrences(of: #"(?i)^(that|those|a|an|some)\s+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        return trimmedNonEmpty(value)
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
