import Foundation

struct CiderDailyTrackerSignalRow: Codable, Equatable {
    var id: String
    var candidateRef: String
    var date: String
    var signalType: String
    var value: String
    var amount: String?
    var currency: String?
    var sourceRefs: [String]
    var sourceQuote: String
    var citation: CiderDailyTrackerCitation?
    var reviewState: String
    var truthState: String
    var metadata: [String: String]
    var safeNextCommands: [String]
}

struct CiderDailyTrackerCitation: Codable, Equatable {
    var ownerType: String
    var ownerID: String
    var sourceQuote: String
    var spanStart: Int?
    var spanEnd: Int?
}

struct CiderDailyTrackerRollup: Codable, Equatable {
    var date: String
    var rowCount: Int
    var foodRowCount: Int
    var spendingRowCount: Int
    var routineRowCount: Int
    var acceptedRowCount: Int
    var reviewableRowCount: Int
    var spendingAmount: String?
    var currency: String?
}

struct CiderDailyTrackerReadModelResult: Codable, Equatable {
    var rows: [CiderDailyTrackerSignalRow]
    var rollups: [CiderDailyTrackerRollup]
}

struct CiderDailyTrackerResolvedQuery: Equatable {
    var from: String?
    var to: String?
    var query: String?
    var appliedRelativeDate: String?
}

enum CiderDailyTrackerSortOrder: String, Codable, Equatable {
    case oldest
    case newest
}

@MainActor
final class CiderDailyTrackerReadModelService {
    private let outputService: SecondBrainEnrichmentOutputService
    private let evidenceService: SecondBrainSourceEvidenceService
    private let referenceDateProvider: () -> Date

    init(database: CiderDatabase = .shared, referenceDateProvider: @escaping () -> Date = { Date() }) {
        self.outputService = SecondBrainEnrichmentOutputService(database: database)
        self.evidenceService = SecondBrainSourceEvidenceService(database: database)
        self.referenceDateProvider = referenceDateProvider
    }

    func dailySignals(
        from startDate: String? = nil,
        to endDate: String? = nil,
        query: String? = nil,
        limit: Int? = nil,
        sort: CiderDailyTrackerSortOrder = .oldest
    ) throws -> CiderDailyTrackerReadModelResult {
        let outputs = try outputService.outputs(kind: "memory_candidate", limit: nil)
        let maxRows = limit.map { max(0, $0) }
        let resolvedQuery = Self.resolveQuery(
            from: startDate,
            to: endDate,
            query: query,
            referenceDate: referenceDateProvider()
        )
        let normalizedQuery = normalizedSearchText(resolvedQuery.query)
        guard maxRows != 0 else {
            return CiderDailyTrackerReadModelResult(rows: [], rollups: [])
        }

        var rows = outputs.compactMap(row)
            .filter { row in
                if let startDate = resolvedQuery.from, row.date < startDate { return false }
                if let endDate = resolvedQuery.to, row.date > endDate { return false }
                return true
            }
            .filter { row in
                guard let normalizedQuery else { return true }
                return queryMatches(row: row, rawQuery: resolvedQuery.query ?? "", normalizedQuery: normalizedQuery)
            }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date {
                    return sort == .newest ? lhs.date > rhs.date : lhs.date < rhs.date
                }
                if lhs.signalType != rhs.signalType { return lhs.signalType < rhs.signalType }
                return lhs.value < rhs.value
            }

        if let maxRows, rows.count > maxRows {
            rows = Array(rows.prefix(maxRows))
        }

        return CiderDailyTrackerReadModelResult(
            rows: rows,
            rollups: rollups(for: rows)
        )
    }

    static func resolveQuery(
        from startDate: String?,
        to endDate: String?,
        query: String?,
        referenceDate: Date = Date(),
        calendar: Calendar = CiderDailyTrackerReadModelService.localCalendar()
    ) -> CiderDailyTrackerResolvedQuery {
        guard let query else {
            return CiderDailyTrackerResolvedQuery(from: startDate, to: endDate, query: normalizedRawQuery(query), appliedRelativeDate: nil)
        }

        if searchTokens(query, droppingStopwords: false).contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
            let yesterdayString = localDateString(yesterday, calendar: calendar)
            let remainingQuery = stripRelativeDateTokens(from: query)
            return CiderDailyTrackerResolvedQuery(
                from: startDate ?? yesterdayString,
                to: endDate ?? yesterdayString,
                query: normalizedRawQuery(remainingQuery),
                appliedRelativeDate: yesterdayString
            )
        }

        if let literal = monthDayDateLiteral(in: query, referenceDate: referenceDate, calendar: calendar) {
            return CiderDailyTrackerResolvedQuery(
                from: startDate ?? literal.dateString,
                to: endDate ?? literal.dateString,
                query: normalizedRawQuery(literal.remainingQuery),
                appliedRelativeDate: literal.dateString
            )
        }

        return CiderDailyTrackerResolvedQuery(from: startDate, to: endDate, query: normalizedRawQuery(query), appliedRelativeDate: nil)
    }

    private func row(for output: SecondBrainEnrichmentOutput) -> CiderDailyTrackerSignalRow? {
        guard let date = output.metadata["journal_date"] ?? output.metadata["observed_date"] ?? output.metadata["date_context"] else {
            return nil
        }
        guard let signal = signal(for: output) else { return nil }
        let evidence = (try? evidenceService.record(derivedOwner: SecondBrainOwnerRef(ownerType: "enrichment_output", ownerID: output.id)))
            ?? SecondBrainSourceEvidenceService.recordFromOutput(output)
        let sourceOwner = evidence?.sourceOwner ?? sourceOwner(from: output) ?? output.owner
        let sourceRef = sourceOwner.canonicalRef
        return CiderDailyTrackerSignalRow(
            id: output.id,
            candidateRef: "memory_candidate:\(output.id)",
            date: date,
            signalType: signal.type,
            value: signal.value,
            amount: output.metadata["amount"],
            currency: output.metadata["currency"],
            sourceRefs: [sourceRef],
            sourceQuote: evidence?.sourceQuote ?? output.evidence,
            citation: evidence.map {
                CiderDailyTrackerCitation(
                    ownerType: $0.sourceOwner.ownerType,
                    ownerID: $0.sourceOwner.ownerID,
                    sourceQuote: $0.sourceQuote,
                    spanStart: $0.spanStart,
                    spanEnd: $0.spanEnd
                )
            },
            reviewState: output.reviewState,
            truthState: output.reviewState == "accepted" ? "accepted_memory_candidate" : "reviewable_candidate_not_truth",
            metadata: output.metadata,
            safeNextCommands: safeCommands(sourceOwner: sourceOwner, candidateID: output.id)
        )
    }

    private func signal(for output: SecondBrainEnrichmentOutput) -> (type: String, value: String)? {
        let memoryKind = output.metadata["memory_kind"] ?? output.metadata["candidate_kind"]
        if memoryKind == "spending_fact" {
            return ("spending", output.metadata["spending_category"] ?? output.metadata["fact_type"] ?? "spending")
        }

        switch memoryKind {
        case "food_routine", "food_preference":
            return ("food", output.metadata["meal"] ?? output.metadata["food_item"] ?? output.metadata["merchant"] ?? memoryKind ?? "food")
        case "schedule_plan":
            return ("routine", output.metadata["plan_type"] ?? output.metadata["plan_status"] ?? "schedule_plan")
        case "routine_signal":
            return ("routine", output.metadata["routine_type"] ?? output.metadata["routine_status"] ?? "routine")
        default:
            return nil
        }
    }

    private func rollups(for rows: [CiderDailyTrackerSignalRow]) -> [CiderDailyTrackerRollup] {
        Dictionary(grouping: rows, by: \.date)
            .map { date, rows in
                let spendingRows = rows.filter { $0.signalType == "spending" }
                let spendingTotal = spendingRows.compactMap { decimalAmount($0.amount) }.reduce(Decimal(0), +)
                return CiderDailyTrackerRollup(
                    date: date,
                    rowCount: rows.count,
                    foodRowCount: rows.filter { $0.signalType == "food" }.count,
                    spendingRowCount: spendingRows.count,
                    routineRowCount: rows.filter { $0.signalType == "routine" }.count,
                    acceptedRowCount: rows.filter { $0.truthState == "accepted_memory_candidate" }.count,
                    reviewableRowCount: rows.filter { $0.truthState != "accepted_memory_candidate" }.count,
                    spendingAmount: spendingRows.isEmpty ? nil : fixedCurrencyString(spendingTotal),
                    currency: spendingRows.first?.currency
                )
            }
            .sorted { $0.date < $1.date }
    }

    private func safeCommands(sourceOwner: SecondBrainOwnerRef, candidateID: String) -> [String] {
        var commands: [String] = []
        switch sourceOwner.ownerType {
        case "note":
            commands.append("cider-cli item context note \(sourceOwner.ownerID) --json")
        default:
            commands.append("cider-cli item owner-get \(sourceOwner.ownerType) \(sourceOwner.ownerID) --json")
        }
        commands.append("cider-cli item memory-facts inspect \(candidateID) --json")
        commands.append("cider-cli capture review-queue --kind memory_candidate --json")
        var seen = Set<String>()
        return commands.filter { seen.insert($0).inserted }
    }

    private func sourceOwner(from output: SecondBrainEnrichmentOutput) -> SecondBrainOwnerRef? {
        guard let ref = output.metadata["source_owner_ref"] else { return nil }
        let parts = ref.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        return SecondBrainOwnerRef(ownerType: parts[0], ownerID: parts[1])
    }

    private func searchableText(for row: CiderDailyTrackerSignalRow) -> String {
        var parts: [String] = [
            row.id,
            row.candidateRef,
            row.date,
            row.signalType,
            row.value,
            row.sourceQuote,
            row.reviewState,
            row.truthState,
        ]
        if let amount = row.amount { parts.append(amount) }
        if let currency = row.currency { parts.append(currency) }
        parts.append(contentsOf: row.sourceRefs)
        parts.append(contentsOf: row.safeNextCommands)
        if let citation = row.citation {
            parts.append(contentsOf: [
                citation.ownerType,
                citation.ownerID,
                citation.sourceQuote,
            ])
            if let spanStart = citation.spanStart { parts.append(String(spanStart)) }
            if let spanEnd = citation.spanEnd { parts.append(String(spanEnd)) }
        }
        for (key, value) in row.metadata {
            parts.append(key)
            parts.append(value)
        }
        return normalizedSearchText(parts.joined(separator: " ")) ?? ""
    }

    private func queryMatches(row: CiderDailyTrackerSignalRow, rawQuery: String, normalizedQuery: String) -> Bool {
        let searchable = searchableText(for: row)
        if searchable.contains(normalizedQuery) {
            return true
        }

        let queryTokens = searchTokens(rawQuery, droppingStopwords: true)
            .filter { !queryContextTokens.contains($0) }
        guard !queryTokens.isEmpty else { return false }
        let rowTokens = Set(searchTokens(searchable, droppingStopwords: false))
        return queryTokens.allSatisfy { queryTokenMatches($0, rowTokens: rowTokens) }
    }

    private func queryTokenMatches(_ token: String, rowTokens: Set<String>) -> Bool {
        if rowTokens.contains(token) {
            return true
        }
        if foodQueryTokens.contains(token) {
            return rowTokens.contains("food")
        }
        if token == "fillup" {
            return rowTokens.contains("gas")
                || rowTokens.contains("fuel")
                || (rowTokens.contains("fill") && rowTokens.contains("up"))
                || rowTokens.contains("filled")
        }
        if token == "fill" {
            return rowTokens.contains("fill")
                || rowTokens.contains("filled")
                || rowTokens.contains("fillup")
                || rowTokens.contains("gas")
                || rowTokens.contains("fuel")
        }
        if token == "gas" {
            return rowTokens.contains("gas") || rowTokens.contains("fuel")
        }
        if token == "fuel" {
            return rowTokens.contains("fuel") || rowTokens.contains("gas")
        }
        if token == "gallon" || token == "gallons" {
            return rowTokens.contains("gallon") || rowTokens.contains("gallons")
        }
        if spendingQueryTokens.contains(token) {
            return rowTokens.contains("spending")
        }
        return false
    }

    private let spendingQueryTokens: Set<String> = [
        "bought", "cost", "paid", "pay", "price", "purchase", "purchased", "spend", "spending", "spent",
    ]

    private let foodQueryTokens: Set<String> = [
        "ate", "eat", "eating", "had", "have",
    ]

    private let queryContextTokens: Set<String> = [
        "context", "location", "locations", "place", "places",
    ]

    private static func searchTokens(_ value: String, droppingStopwords: Bool) -> [String] {
        let normalized = normalizedSearchText(value) ?? ""
        let tokenText = normalized
            .replacingOccurrences(of: #"(?<=[A-Za-z])-(?=[A-Za-z])"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[^a-z0-9.]+"#, with: " ", options: .regularExpression)
        let stopwords: Set<String> = [
            "a", "an", "and", "buy", "did", "do", "for", "get", "how", "i", "last", "latest", "many", "me",
            "most", "much", "my", "of", "on", "recent", "the", "that", "time", "to", "was", "what", "when",
            "where",
        ]
        return tokenText
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
            .filter { !droppingStopwords || !stopwords.contains($0) }
    }

    private func searchTokens(_ value: String, droppingStopwords: Bool) -> [String] {
        Self.searchTokens(value, droppingStopwords: droppingStopwords)
    }

    private static func normalizedSearchText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    private func normalizedSearchText(_ value: String?) -> String? {
        Self.normalizedSearchText(value)
    }

    private static func normalizedRawQuery(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func stripRelativeDateTokens(from query: String) -> String {
        query
            .replacingOccurrences(of: #"\byesterday\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func monthDayDateLiteral(
        in query: String,
        referenceDate: Date,
        calendar: Calendar
    ) -> (dateString: String, remainingQuery: String)? {
        let pattern = #"\b(january|jan\.?|february|feb\.?|march|mar\.?|april|apr\.?|may|june|jun\.?|july|jul\.?|august|aug\.?|september|sept\.?|sep\.?|october|oct\.?|november|nov\.?|december|dec\.?)\s+([0-9]{1,2})(?:st|nd|rd|th)?(?:,?\s+([0-9]{4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsQuery = query as NSString
        let fullRange = NSRange(location: 0, length: nsQuery.length)
        guard let match = regex.firstMatch(in: query, range: fullRange),
              match.numberOfRanges >= 3,
              let monthRange = Range(match.range(at: 1), in: query),
              let dayRange = Range(match.range(at: 2), in: query),
              let month = monthNumber(String(query[monthRange])),
              let day = Int(query[dayRange])
        else {
            return nil
        }

        let year: Int
        if match.numberOfRanges >= 4,
           match.range(at: 3).location != NSNotFound,
           let yearRange = Range(match.range(at: 3), in: query),
           let explicitYear = Int(query[yearRange]) {
            year = explicitYear
        } else {
            year = calendar.component(.year, from: referenceDate)
        }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day,
              let literalRange = Range(match.range, in: query)
        else {
            return nil
        }

        let remaining = query
            .replacingCharacters(in: literalRange, with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (localDateString(date, calendar: calendar), remaining)
    }

    private static func monthNumber(_ value: String) -> Int? {
        switch value.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) {
        case "january", "jan": return 1
        case "february", "feb": return 2
        case "march", "mar": return 3
        case "april", "apr": return 4
        case "may": return 5
        case "june", "jun": return 6
        case "july", "jul": return 7
        case "august", "aug": return 8
        case "september", "sept", "sep": return 9
        case "october", "oct": return 10
        case "november", "nov": return 11
        case "december", "dec": return 12
        default: return nil
        }
    }

    private static func localCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .current
        return calendar
    }

    private static func localDateString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func decimalAmount(_ value: String?) -> Decimal? {
        guard let value else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func fixedCurrencyString(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue.contains(".")
            ? String(format: "%.2f", NSDecimalNumber(decimal: rounded).doubleValue)
            : "\(NSDecimalNumber(decimal: rounded).stringValue).00"
    }
}
