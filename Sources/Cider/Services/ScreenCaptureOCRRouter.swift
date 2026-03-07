import Foundation

// MARK: - Route Types

enum CaptureRouteType {
    case note
    case dateCard
    case contact
}

struct CaptureRoute {
    let type: CaptureRouteType
    let detectedDates: [Date]
    let detectedEmails: [String]
    let detectedPhones: [String]
    let suggestedTitle: String
    let suggestedLocation: String
}

// MARK: - Router

/// Analyzes OCR text and suggests a routing action (note / date card / contact).
/// Uses `NSDataDetector` for structured data extraction.
enum ScreenCaptureOCRRouter {

    static func detectRoute(in text: String) -> CaptureRoute {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CaptureRoute(
                type: .note,
                detectedDates: [],
                detectedEmails: [],
                detectedPhones: [],
                suggestedTitle: "Screen Capture",
                suggestedLocation: ""
            )
        }

        let types: NSTextCheckingResult.CheckingType = [.date, .phoneNumber, .link]
        let detector = try? NSDataDetector(types: types.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []

        var dates: [Date] = []
        var emails: [String] = []
        var phones: [String] = []

        for match in matches {
            switch match.resultType {
            case .date:
                if let date = match.date { dates.append(date) }
            case .phoneNumber:
                if let phone = match.phoneNumber { phones.append(phone) }
            case .link:
                if let url = match.url, url.scheme == "mailto",
                   let email = url.absoluteString.components(separatedBy: ":").last {
                    emails.append(email)
                }
            default:
                break
            }
        }

        // Supplement NSDataDetector dates with explicit time parsing from OCR text
        if !dates.isEmpty {
            dates = dates.map { date in
                mergeExplicitTime(into: date, from: text)
            }
        }

        let lines = classifiedLines(from: text)
        let title = extractTitle(from: lines)
        let location = extractLocation(from: lines, title: title)
        let routeType = classify(dates: dates, emails: emails, phones: phones)

        return CaptureRoute(
            type: routeType,
            detectedDates: dates,
            detectedEmails: emails,
            detectedPhones: phones,
            suggestedTitle: title,
            suggestedLocation: location
        )
    }

    // MARK: - Private

    private static func classify(dates: [Date], emails: [String], phones: [String]) -> CaptureRouteType {
        let hasContactSignal = !emails.isEmpty || !phones.isEmpty
        if hasContactSignal {
            return .contact
        }
        if !dates.isEmpty {
            return .dateCard
        }
        return .note
    }

    // MARK: - Line Classification

    private enum LineType {
        case noise      // PROMOTED, SPONSORED, AD, bullets, etc.
        case dateLike   // Lines that look like dates/times
        case numeric    // Purely numbers/punctuation
        case content    // Meaningful text
    }

    private struct ClassifiedLine {
        let text: String
        let type: LineType
    }

    /// Noise words that appear in event listings but aren't meaningful titles.
    private static let noisePatterns: Set<String> = [
        "promoted", "sponsored", "ad", "advertisement", "tickets",
        "buy tickets", "get tickets", "rsvp", "learn more", "see more",
        "view details", "more info", "interested", "going", "share",
        "save", "follow", "like"
    ]

    private static func classifiedLines(from text: String) -> [ClassifiedLine] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                if line.count < 3 || line.allSatisfy({ $0.isNumber || $0.isPunctuation || $0 == " " }) {
                    return ClassifiedLine(text: line, type: .numeric)
                }
                let lower = line.lowercased()
                    .trimmingCharacters(in: .punctuationCharacters)
                    .trimmingCharacters(in: .whitespaces)
                if noisePatterns.contains(lower) {
                    return ClassifiedLine(text: line, type: .noise)
                }
                // Lines starting with bullet-like prefixes
                if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("·") {
                    let stripped = line.dropFirst().trimmingCharacters(in: .whitespaces).lowercased()
                    if noisePatterns.contains(stripped) {
                        return ClassifiedLine(text: line, type: .noise)
                    }
                }
                if looksLikeDate(line) {
                    return ClassifiedLine(text: line, type: .dateLike)
                }
                return ClassifiedLine(text: line, type: .content)
            }
    }

    /// Extract a meaningful title — the first content line that isn't noise or a date.
    private static func extractTitle(from lines: [ClassifiedLine]) -> String {
        guard let first = lines.first(where: { $0.type == .content }) else {
            return "Screen Capture"
        }
        // Strip leading bullet/dash characters
        var title = first.text
        if let firstChar = title.first, "•·-–—".contains(firstChar) {
            title = String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return String(title.prefix(60))
    }

    /// Extract a location — the content line after the title that looks like a venue name.
    /// Venue names are typically short lines without dates that appear near the title.
    private static func extractLocation(from lines: [ClassifiedLine], title: String) -> String {
        guard let titleIndex = lines.firstIndex(where: { $0.type == .content && $0.text.contains(title.prefix(20)) }) else {
            return ""
        }

        // Look at the next few content lines after the title for a location candidate
        let candidates = lines.suffix(from: lines.index(after: titleIndex))
            .prefix(3)
            .filter { $0.type == .content }

        for candidate in candidates {
            let text = candidate.text
            // Skip if it looks like a price, count, or URL
            if text.contains("$") || text.contains("http") || text.contains("www.") { continue }
            // Skip very short fragments (likely OCR noise like "88 31")
            if text.count < 4 { continue }
            // Skip if it's mostly numbers
            let letterCount = text.filter(\.isLetter).count
            if letterCount < text.count / 2 { continue }
            return String(text.prefix(60))
        }
        return ""
    }

    // MARK: - Time Merging

    /// NSDataDetector often returns dates at 12:00 PM (noon) when it can't parse the time.
    /// This scans the OCR text for explicit time patterns and merges them into the date.
    private static func mergeExplicitTime(into date: Date, from text: String) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        // Only override if the date looks like a noon default (12:00 exactly)
        guard hour == 12 && minute == 0 else { return date }

        // Scan for explicit time patterns: "7:00 PM", "8:00 pm", "6:10 PM", "19:00"
        let timePatterns = [
            // 12-hour with minutes: "7:00 PM", "6:10 pm", "8:00PM"
            "\\b(1[0-2]|[1-9]):(\\d{2})\\s*(AM|PM|am|pm|a\\.m\\.|p\\.m\\.)\\b",
            // 12-hour without minutes: "7 PM", "8pm"
            "\\b(1[0-2]|[1-9])\\s*(AM|PM|am|pm|a\\.m\\.|p\\.m\\.)\\b",
            // 24-hour: "19:00", "18:30"
            "\\b([01]?\\d|2[0-3]):(\\d{2})\\b"
        ]

        for pattern in timePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                continue
            }

            let matchedString = String(text[Range(match.range, in: text)!])
            let parsed = parseTime(matchedString)
            if let (h, m) = parsed {
                return calendar.date(bySettingHour: h, minute: m, second: 0, of: date) ?? date
            }
        }
        return date
    }

    /// Parse a time string like "7:00 PM", "8pm", "19:00" into (hour24, minute).
    private static func parseTime(_ string: String) -> (Int, Int)? {
        let formats = ["h:mm a", "h:mma", "h a", "ha", "H:mm", "HH:mm"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: string.trimmingCharacters(in: .whitespaces)) {
                let cal = Calendar.current
                return (cal.component(.hour, from: date), cal.component(.minute, from: date))
            }
        }
        return nil
    }

    /// Heuristic: a line looks like a date if NSDataDetector finds a date covering most of it.
    private static func looksLikeDate(_ line: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return false }
        let range = NSRange(line.startIndex..., in: line)
        let matches = detector.matches(in: line, options: [], range: range)
        let coveredLength = matches.reduce(0) { $0 + $1.range.length }
        // If date patterns cover more than half the line, it's a date line
        return coveredLength > line.count / 2
    }
}
