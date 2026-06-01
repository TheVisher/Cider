import Foundation

@MainActor
enum AgentReminderToolSupport {
    enum FrequencyParseResult {
        case valid(DateCardRecurrenceFrequency?)
        case invalid(String)
    }

    private static var dateCardUpdateHandlerOverride: ((DateCard) -> Bool)?

    static func recurrenceFrequency(from rawValue: String?) -> FrequencyParseResult {
        guard let rawValue else { return .valid(nil) }
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return .valid(nil) }

        switch normalized {
        case "daily": return .valid(.daily)
        case "weekly": return .valid(.weekly)
        case "monthly": return .valid(.monthly)
        case "yearly": return .valid(.yearly)
        default: return .invalid(normalized)
        }
    }

    static func updateDateCard(_ card: DateCard) -> Bool {
        if let dateCardUpdateHandlerOverride {
            return dateCardUpdateHandlerOverride(card)
        }
        return DateCardStorage.shared.updateDateCard(card)
    }

    static func _setDateCardUpdateHandlerForTesting(_ handler: @escaping (DateCard) -> Bool) {
        dateCardUpdateHandlerOverride = handler
    }

    static func _resetDateCardUpdateHandlerForTesting() {
        dateCardUpdateHandlerOverride = nil
    }
}
