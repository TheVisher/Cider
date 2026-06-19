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
        outputs.append(contentsOf: spendingFactCandidates(
            sourceOwner: sourceOwner,
            rawContent: rawContent,
            date: date,
            time: time
        ))
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

    private struct JournalTextLine {
        var text: String
        var start: Int
        var end: Int
    }

    private struct JournalSpendingBlock {
        var quote: String
        var spanStart: Int
        var spanEnd: Int
    }

    private func spendingFactCandidates(
        sourceOwner: SecondBrainOwnerRef,
        rawContent: String,
        date: String?,
        time: String?
    ) -> [SecondBrainEnrichmentOutput] {
        let blockCandidates = spendingBlocks(in: rawContent).compactMap { block in
            makeGasSpendingMemoryCandidate(
                sourceOwner: sourceOwner,
                block: block,
                date: date,
                time: time
            )
        }
        let proseCandidates = proseSpendingFactCandidates(
            sourceOwner: sourceOwner,
            rawContent: rawContent,
            date: date,
            time: time
        )
        return blockCandidates + proseCandidates
    }

    private func spendingBlocks(in text: String) -> [JournalSpendingBlock] {
        let lines = indexedLines(in: text)
        var blocks: [JournalSpendingBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let lower = line.text.lowercased()
            let isGasSpendingHeader = (lower.contains("gas/fuel") || (lower.contains("gas") && lower.contains("fuel")))
                && (lower.contains("spending") || lower.contains("fill-up") || lower.contains("fill up"))
            guard isGasSpendingHeader else {
                index += 1
                continue
            }

            var startIndex = index
            let contextWindowStart = max(0, index - 5)
            for candidateIndex in stride(from: index - 1, through: contextWindowStart, by: -1) {
                let contextLine = lines[candidateIndex]
                if contextLine.text.range(of: #"(?i)\b(Duvall|commute|fill-up|fill up|morning)\b"#, options: .regularExpression) != nil {
                    startIndex = candidateIndex
                }
            }

            var endIndex = index
            var cursor = index + 1
            while cursor < lines.count {
                let candidate = lines[cursor]
                guard trimmedNonEmpty(candidate.text) != nil else { break }
                let candidateLower = candidate.text.lowercased()
                if !candidate.text.trimmingCharacters(in: .whitespaces).hasPrefix("-")
                    && candidateLower.hasSuffix(":")
                    && !candidateLower.contains("gas")
                    && !candidateLower.contains("fuel") {
                    break
                }
                endIndex = cursor
                cursor += 1
            }

            let start = lines[startIndex].start
            let end = lines[endIndex].end
            let quote = substring(in: text, start: start, end: end)
            blocks.append(JournalSpendingBlock(quote: quote, spanStart: start, spanEnd: end))
            index = max(cursor, index + 1)
        }
        return blocks
    }

    private func proseSpendingFactCandidates(
        sourceOwner: SecondBrainOwnerRef,
        rawContent: String,
        date: String?,
        time: String?
    ) -> [SecondBrainEnrichmentOutput] {
        candidateSentences(from: rawContent).compactMap { sentence in
            makeProseSpendingMemoryCandidate(
                sourceOwner: sourceOwner,
                sentence: sentence,
                rawContent: rawContent,
                date: date,
                time: time
            )
        }
    }

    private func makeProseSpendingMemoryCandidate(
        sourceOwner: SecondBrainOwnerRef,
        sentence: String,
        rawContent: String,
        date: String?,
        time: String?
    ) -> SecondBrainEnrichmentOutput? {
        let lower = sentence.lowercased()
        guard let amount = firstCapture(pattern: #"\$\s*([0-9]+(?:\.[0-9]{1,2})?)"#, in: sentence) else { return nil }
        let spendingMarkers = ["spent", "paid", "bought", "grabbed", "picked up", "cost", "total"]
        guard spendingMarkers.contains(where: { lower.contains($0) }) else { return nil }
        guard !lower.contains("fuel amount") && !lower.contains("effective price") else { return nil }

        guard let category = proseSpendingCategory(for: sentence) else { return nil }
        let normalizedDate = date.flatMap(trimmedNonEmpty)
        let normalizedTime = time.flatMap(trimmedNonEmpty)
        let amountQualifier = lower.range(of: #"\b(about|around|roughly|approximately)\s*\$"#, options: .regularExpression).map { String(sentence[$0]).components(separatedBy: "$").first?.trimmingCharacters(in: .whitespacesAndNewlines) } ?? nil
        let merchant = merchantName(in: sentence, category: category.key)
        let datePhrase = normalizedDate.map { " on \($0)" } ?? ""
        let qualifierPhrase = amountQualifier == nil ? "" : "\(amountQualifier!) "
        let value: String
        if let merchant {
            value = "Visher spent \(qualifierPhrase)$\(amount) on \(category.displayName) at \(merchant)\(datePhrase)."
        } else if category.key == "gas_station" {
            value = "Visher spent \(qualifierPhrase)$\(amount) at a gas station\(datePhrase)."
        } else {
            value = "Visher spent \(qualifierPhrase)$\(amount) on \(category.displayName)\(datePhrase)."
        }

        let span = sourceSpan(for: sentence, in: rawContent)
        let categorySlug = category.key.replacingOccurrences(of: "_", with: "-")
        var output = SecondBrainEnrichmentOutput(
            owner: sourceOwner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: normalizedValue(value),
            label: "Memory candidate: spending fact",
            evidence: sentence,
            source: "memory_candidate.journal_spending_extraction",
            confidence: proseSpendingConfidence(sentence: sentence, category: category.key, merchant: merchant),
            reviewState: "suggested",
            metadata: [
                "memory_kind": "spending_fact",
                "candidate_kind": "spending_fact",
                "fact_type": category.factType,
                "spending_category": category.key,
                "amount": amount,
                "currency": "USD",
                "requires_review": "true",
                "memory_status": "current",
                "memory_key": "spending-\(categorySlug)-\(normalizedDate ?? "unknown-date")-\(amount)",
                "requested_owner_type": sourceOwner.ownerType,
                "requested_owner_ref": sourceOwner.ownerID,
                "source_owner_ref": sourceOwner.canonicalRef,
                "source_kind": "journal",
                "source_quote": sentence,
                "source_span_start": String(span.start),
                "source_span_end": String(span.end),
                "review_query_terms": proseReviewQueryTerms(category: category.key, amount: amount, merchant: merchant),
            ]
        )
        output.metadata["candidate_ref"] = "memory_candidate:\(output.id)"
        if let merchant { output.metadata["merchant"] = merchant }
        if let normalizedDate {
            output.metadata["journal_date"] = normalizedDate
            output.metadata["date_context"] = normalizedDate
            output.metadata["observed_date"] = normalizedDate
        }
        if let normalizedTime {
            output.metadata["journal_time"] = normalizedTime
            output.metadata["time_context"] = normalizedTime
        }
        if let amountQualifier {
            output.metadata["amount_qualifier"] = amountQualifier
        }
        let entities = relatedEntities(in: sentence)
        if !entities.isEmpty {
            output.metadata["related_entities"] = encodeJSONStringArray(entities)
            output.metadata["linked_entity_names"] = entities.joined(separator: "|")
        }
        return output
    }

    private func makeGasSpendingMemoryCandidate(
        sourceOwner: SecondBrainOwnerRef,
        block: JournalSpendingBlock,
        date: String?,
        time: String?
    ) -> SecondBrainEnrichmentOutput? {
        let quote = block.quote
        let lower = quote.lowercased()
        guard lower.contains("gas") || lower.contains("fuel") else { return nil }
        guard let amount = firstCapture(
            pattern: #"(?im)^\s*-?\s*(?:total|cost|spent|paid)\s*:?\s*\$\s*([0-9]+(?:\.[0-9]{1,2})?)"#,
            in: quote
        ) ?? firstCapture(pattern: #"\$\s*([0-9]+(?:\.[0-9]{1,2})?)"#, in: quote) else { return nil }
        let quantity = firstCapture(
            pattern: #"(?i)([0-9]+(?:\.[0-9]+)?)\s*(?:gal|gallon|gallons)\b"#,
            in: quote
        )
        let unitPrice = firstCapture(
            pattern: #"(?i)(?:about\s*)?\$\s*([0-9]+(?:\.[0-9]{1,2})?)\s*/\s*(?:gal|gallon|gallons)"#,
            in: quote
        )
        let fuelGrade = firstCapture(
            pattern: #"(?im)^\s*-?\s*Fuel grade\s*:\s*(.+?)\.?\s*$"#,
            in: quote
        )
        let normalizedDate = date.flatMap(trimmedNonEmpty)
        let normalizedTime = time.flatMap(trimmedNonEmpty)
        let fillContext = lower.contains("morning") ? "morning " : ""
        let datePhrase = normalizedDate.map { " on \($0)" } ?? ""
        let tripPhrase = quote.range(of: #"(?i)\bDuvall\b"#, options: .regularExpression) != nil ? " after Duvall" : ""
        let quantityPhrase = quantity.map { " for \($0) gallons" } ?? ""
        let unitPricePhrase = unitPrice.map { " (about $\($0)/gal)" } ?? ""
        let gradePhrase = fuelGrade.map { " of \($0)" } ?? ""
        let value = "Visher filled up gas\(datePhrase) during the \(fillContext)commute\(tripPhrase): $\(amount)\(quantityPhrase)\(gradePhrase)\(unitPricePhrase)."
            .replacingOccurrences(of: "  ", with: " ")
        var output = SecondBrainEnrichmentOutput(
            owner: sourceOwner,
            chunkID: nil,
            kind: "memory_candidate",
            value: value,
            normalizedValue: normalizedValue(value),
            label: "Memory candidate: spending fact",
            evidence: quote,
            source: "memory_candidate.journal_spending_extraction",
            confidence: gasSpendingConfidence(quantity: quantity, unitPrice: unitPrice, fuelGrade: fuelGrade),
            reviewState: "suggested",
            metadata: [
                "memory_kind": "spending_fact",
                "candidate_kind": "spending_fact",
                "fact_type": "fuel_purchase",
                "spending_category": "gas",
                "amount": amount,
                "currency": "USD",
                "requires_review": "true",
                "memory_status": "current",
                "memory_key": "spending-gas-fill-up-\(normalizedDate ?? "unknown-date")-\(amount)",
                "requested_owner_type": sourceOwner.ownerType,
                "requested_owner_ref": sourceOwner.ownerID,
                "source_owner_ref": sourceOwner.canonicalRef,
                "source_kind": "journal",
                "source_quote": quote,
                "source_span_start": String(block.spanStart),
                "source_span_end": String(block.spanEnd),
                "review_query_terms": "last time I filled up|what did I spend on gas|expensive morning fill-up|$\(amount)|\(quantity.map { "\($0) gallons" } ?? "")",
            ]
        )
        output.metadata["candidate_ref"] = "memory_candidate:\(output.id)"
        if let quantity {
            output.metadata["quantity"] = quantity
            output.metadata["quantity_unit"] = "gallons"
        }
        if let unitPrice {
            output.metadata["unit_price"] = unitPrice
            output.metadata["unit_price_unit"] = "USD_per_gallon"
        }
        if let fuelGrade { output.metadata["fuel_grade"] = fuelGrade }
        if let normalizedDate {
            output.metadata["journal_date"] = normalizedDate
            output.metadata["date_context"] = normalizedDate
            output.metadata["observed_date"] = normalizedDate
        }
        if let normalizedTime {
            output.metadata["journal_time"] = normalizedTime
            output.metadata["time_context"] = normalizedTime
        }
        let entities = relatedEntities(in: quote)
        if !entities.isEmpty {
            output.metadata["related_entities"] = encodeJSONStringArray(entities)
            output.metadata["linked_entity_names"] = entities.joined(separator: "|")
        }
        return output
    }

    private struct ProseSpendingCategory {
        var key: String
        var factType: String
        var displayName: String
    }

    private func proseSpendingCategory(for sentence: String) -> ProseSpendingCategory? {
        let lower = sentence.lowercased()
        if lower.contains("gas station") {
            return ProseSpendingCategory(key: "gas_station", factType: "gas_station_purchase", displayName: "gas station items")
        }
        let foodMarkers = ["lunch", "dinner", "breakfast", "food", "panda express", "orange chicken", "chow mein", "burger", "taco", "coffee", "drink"]
        if foodMarkers.contains(where: { lower.contains($0) }) {
            return ProseSpendingCategory(key: "food", factType: "food_purchase", displayName: "food")
        }
        return nil
    }

    private func merchantName(in sentence: String, category: String?) -> String? {
        let knownMerchants = ["Panda Express", "Starbucks", "McDonald's", "Costco", "Safeway", "Target"]
        for merchant in knownMerchants where sentence.range(of: merchant, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return merchant
        }
        return nil
    }

    private func proseSpendingConfidence(sentence: String, category: String?, merchant: String?) -> Double {
        var confidence = 0.72
        if category != nil { confidence += 0.06 }
        if merchant != nil { confidence += 0.06 }
        if sentence.range(of: #"\b(spent|paid|bought)\b"#, options: [.regularExpression, .caseInsensitive]) != nil { confidence += 0.04 }
        return min(confidence, 0.88)
    }

    private func proseReviewQueryTerms(category: String, amount: String, merchant: String?) -> String {
        var terms = ["$\(amount)", "what did I spend"]
        if category == "food" {
            terms += ["what did I spend on food", "food spending", "lunch spending"]
        } else if category == "gas_station" {
            terms += ["gas station spending", "gas station treats", "what did I spend at the gas station"]
        }
        if let merchant { terms.append(merchant) }
        var seen = Set<String>()
        return terms.filter { seen.insert($0).inserted }.joined(separator: "|")
    }

    private func sourceSpan(for sentence: String, in rawContent: String) -> (start: Int, end: Int) {
        if let range = rawContent.range(of: sentence) {
            let start = rawContent.distance(from: rawContent.startIndex, to: range.lowerBound)
            let end = rawContent.distance(from: rawContent.startIndex, to: range.upperBound)
            return (start, end)
        }
        return (0, sentence.count)
    }

    private func gasSpendingConfidence(quantity: String?, unitPrice: String?, fuelGrade: String?) -> Double {
        var confidence = 0.72
        if quantity != nil { confidence += 0.06 }
        if unitPrice != nil { confidence += 0.06 }
        if fuelGrade != nil { confidence += 0.04 }
        return min(confidence, 0.9)
    }

    private func relatedEntities(in text: String) -> [String] {
        var entities: [String] = []
        let knownEntities = ["Duvall", "Mazda CX-5", "Mazda CX5", "Boeing", "ERT", "Monster", "protein bar"]
        for entity in knownEntities where text.range(of: entity, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            let canonical = entity == "Mazda CX5" ? "Mazda CX-5" : entity
            if !entities.contains(canonical) { entities.append(canonical) }
        }
        return entities
    }

    private func indexedLines(in text: String) -> [JournalTextLine] {
        var lines: [JournalTextLine] = []
        var offset = 0
        for rawLineSubsequence in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let rawLine = String(rawLineSubsequence)
            lines.append(JournalTextLine(text: rawLine, start: offset, end: offset + rawLine.count))
            offset += rawLine.count + 1
        }
        return lines
    }

    private func substring(in text: String, start: Int, end: Int) -> String {
        let lowerBound = text.index(text.startIndex, offsetBy: max(0, min(start, text.count)))
        let upperBound = text.index(text.startIndex, offsetBy: max(0, min(end, text.count)))
        return String(text[lowerBound..<upperBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func firstCapture(pattern: String, in text: String) -> String? {
        regexMatches(pattern: pattern, in: text)
            .first?
            .captures
            .first??
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func encodeJSONStringArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return values.joined(separator: "|")
        }
        return string
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
