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

    /// Extract a meaningful title from the first non-trivial line of OCR text.
    private static func extractTitle(from text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 3 && !$0.allSatisfy { $0.isNumber || $0.isPunctuation || $0 == " " } }
        guard let first = lines.first else { return "Screen Capture" }
        return String(first.prefix(60)).capitalized
    }
}
