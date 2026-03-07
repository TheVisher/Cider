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
                suggestedTitle: "Screen Capture"
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

        let title = extractTitle(from: text)
        let routeType = classify(dates: dates, emails: emails, phones: phones)

        return CaptureRoute(
            type: routeType,
            detectedDates: dates,
            detectedEmails: emails,
            detectedPhones: phones,
            suggestedTitle: title
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

    /// Extract a meaningful title from OCR text.
    /// Skips lines that look like dates/times or are too short.
    private static func extractTitle(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard line.count >= 3 else { return false }
                // Skip lines that are purely numeric/punctuation/whitespace
                if line.allSatisfy({ $0.isNumber || $0.isPunctuation || $0 == " " }) { return false }
                // Skip lines that look like dates (e.g., "Fri, Mar 13", "March 20 - 7:00 pm")
                if looksLikeDate(line) { return false }
                return true
            }
        guard let first = lines.first else { return "Screen Capture" }
        // Preserve original casing — don't use .capitalized which garbles names
        return String(first.prefix(60))
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
