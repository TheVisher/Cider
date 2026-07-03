import Foundation

/// Reads and writes TodoCard and DateCard models as iCalendar (.ics) files.
/// Standard fields (SUMMARY, DESCRIPTION, DUE, PRIORITY, STATUS, etc.) are
/// interoperable with Apple Calendar, Google Calendar, Outlook, etc.
/// Cider-specific fields use X-CIDER-* properties.
enum ICalendarSerializer {

    // MARK: - Todo (VTODO)

    /// Serializes a TodoCard to iCalendar VTODO format.
    static func serializeTodo(_ todo: TodoCard) -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCALENDAR")
        lines.append("VERSION:2.0")
        lines.append("PRODID:-//Cider//NONSGML v1.0//EN")
        lines.append("BEGIN:VTODO")
        lines.append("UID:\(todo.id.uuidString)")
        lines.append("SUMMARY:\(escapeICalText(todo.title))")

        if !todo.details.isEmpty {
            lines.append("DESCRIPTION:\(escapeICalText(todo.details))")
        }
        if let dueDate = todo.dueDate {
            if isLocalStartOfDay(dueDate) {
                lines.append("DUE;VALUE=DATE:\(CiderLocalDate.formatCompact(dueDate))")
            } else {
                lines.append("DUE:\(dateTimeFormatter.string(from: dueDate))")
            }
        }
        if let priority = todo.priority {
            // RFC 5545: 1-4 = high, 5 = medium, 6-9 = low
            let icalPriority: Int
            switch priority {
            case .high: icalPriority = 1
            case .medium: icalPriority = 5
            case .low: icalPriority = 9
            }
            lines.append("PRIORITY:\(icalPriority)")
        }
        lines.append("STATUS:\(todo.isCompleted ? "COMPLETED" : "NEEDS-ACTION")")
        if let completedAt = todo.completedAt {
            lines.append("COMPLETED:\(dateTimeFormatter.string(from: completedAt))")
        }
        lines.append("CREATED:\(dateTimeFormatter.string(from: todo.createdAt))")
        lines.append("LAST-MODIFIED:\(dateTimeFormatter.string(from: todo.updatedAt))")

        // Cider-specific extensions
        if !todo.labelIDs.isEmpty {
            lines.append("X-CIDER-LABEL:\(todo.labelIDs.map(\.uuidString).joined(separator: ","))")
        }
        if !todo.linkedEntities.isEmpty {
            let refs = todo.linkedEntities.map { "\($0.type.rawValue):\($0.entityID.uuidString)" }
            lines.append("X-CIDER-LINKED:\(refs.joined(separator: ","))")
        }
        if !todo.notes.isEmpty {
            lines.append("X-CIDER-NOTES:\(escapeICalText(todo.notes))")
        }
        if let actionURLString = todo.actionURLString {
            lines.append("X-CIDER-ACTION-URL:\(escapeICalText(actionURLString))")
        }
        if let snoozedUntil = todo.snoozedUntil {
            lines.append("X-CIDER-SNOOZED-UNTIL:\(dateTimeFormatter.string(from: snoozedUntil))")
        }
        if !todo.rules.isEmpty,
           let jsonData = try? rulesEncoder.encode(todo.rules),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            lines.append("X-CIDER-RULES:\(escapeICalText(jsonString))")
        }
        if !todo.checklist.isEmpty {
            // Checklist is complex (nested subtasks, amounts, etc.) — encode as JSON
            if let jsonData = try? checklistEncoder.encode(todo.checklist),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                lines.append("X-CIDER-CHECKLIST:\(escapeICalText(jsonString))")
            }
        }

        lines.append("END:VTODO")
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Parses an iCalendar VTODO string into a TodoCard. Returns nil if invalid.
    static func parseTodo(_ string: String) -> TodoCard? {
        let lines = unfoldLines(string)

        guard lines.contains(where: { $0.hasPrefix("BEGIN:VTODO") }),
              lines.contains(where: { $0.hasPrefix("END:VTODO") }) else {
            return nil
        }

        var id: UUID?
        var title = ""
        var details = ""
        var dueDate: Date?
        var priority: TodoPriority?
        var isCompleted = false
        var completedAt: Date?
        var labelIDs: [UUID] = []
        var linkedEntities: [LibraryEntityRef] = []
        var notes = ""
        var actionURLString: String?
        var snoozedUntil: Date?
        var rules: [SurfacingRule] = []
        var checklist: [TodoChecklistItem] = []
        var createdAt: Date?
        var updatedAt: Date?

        for line in lines {
            let (key, value) = splitProperty(line)
            let baseKey = key.components(separatedBy: ";").first ?? key

            switch baseKey {
            case "UID":
                id = UUID(uuidString: value)
            case "SUMMARY":
                title = unescapeICalText(value)
            case "DESCRIPTION":
                details = unescapeICalText(value)
            case "DUE":
                dueDate = key.contains("VALUE=DATE")
                    ? CiderLocalDate.parseCompact(value)
                    : parseDateTime(value)
            case "PRIORITY":
                if let p = Int(value) {
                    if p >= 1, p <= 4 { priority = .high }
                    else if p == 5 { priority = .medium }
                    else if p >= 6, p <= 9 { priority = .low }
                }
            case "STATUS":
                isCompleted = value == "COMPLETED"
            case "COMPLETED":
                completedAt = parseDateTime(value)
            case "CREATED":
                createdAt = parseDateTime(value)
            case "LAST-MODIFIED":
                updatedAt = parseDateTime(value)
            case "X-CIDER-LABEL":
                labelIDs = value.components(separatedBy: ",").compactMap {
                    UUID(uuidString: $0.trimmingCharacters(in: .whitespaces))
                }
            case "X-CIDER-LINKED":
                linkedEntities = parseLinkedEntities(value)
            case "X-CIDER-NOTES":
                notes = unescapeICalText(value)
            case "X-CIDER-ACTION-URL":
                actionURLString = unescapeICalText(value)
            case "X-CIDER-SNOOZED-UNTIL":
                snoozedUntil = parseDateTime(value)
            case "X-CIDER-RULES":
                let jsonString = unescapeICalText(value)
                if let jsonData = jsonString.data(using: .utf8) {
                    rules = (try? rulesDecoder.decode([SurfacingRule].self, from: jsonData)) ?? []
                }
            case "X-CIDER-CHECKLIST":
                let jsonString = unescapeICalText(value)
                if let jsonData = jsonString.data(using: .utf8) {
                    checklist = (try? checklistDecoder.decode([TodoChecklistItem].self, from: jsonData)) ?? []
                }
            default:
                break
            }
        }

        guard let todoID = id, !title.isEmpty else { return nil }

        return TodoCard(
            id: todoID,
            title: title,
            details: details,
            checklist: checklist,
            dueDate: dueDate,
            priority: priority,
            isCompleted: isCompleted,
            completedAt: completedAt,
            labelIDs: labelIDs,
            notes: notes,
            linkedEntities: linkedEntities,
            actionURLString: actionURLString,
            snoozedUntil: snoozedUntil,
            rules: rules,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    // MARK: - Date Card (VEVENT)

    /// Serializes a DateCard to iCalendar VEVENT format.
    static func serializeDateCard(_ dc: DateCard) -> String {
        var lines: [String] = []
        lines.append("BEGIN:VCALENDAR")
        lines.append("VERSION:2.0")
        lines.append("PRODID:-//Cider//NONSGML v1.0//EN")
        lines.append("BEGIN:VEVENT")
        lines.append("UID:\(dc.id.uuidString)")
        lines.append("SUMMARY:\(escapeICalText(dc.title))")

        if !dc.details.isEmpty {
            lines.append("DESCRIPTION:\(escapeICalText(dc.details))")
        }

        if dc.allDay {
            // All-day events use DATE (not DATE-TIME)
            lines.append("DTSTART;VALUE=DATE:\(CiderLocalDate.formatCompact(dc.startAt))")
            if let endAt = dc.endAt {
                lines.append("DTEND;VALUE=DATE:\(CiderLocalDate.formatCompact(endAt))")
            }
        } else {
            lines.append("DTSTART:\(dateTimeFormatter.string(from: dc.startAt))")
            if let endAt = dc.endAt {
                lines.append("DTEND:\(dateTimeFormatter.string(from: endAt))")
            }
        }

        if !dc.location.isEmpty {
            lines.append("LOCATION:\(escapeICalText(dc.location))")
        }

        // Recurrence rule → RRULE
        if let rule = dc.recurrenceRule {
            var rrule = "RRULE:FREQ=\(rule.frequency.icalFreq)"
            if rule.interval > 1 {
                rrule += ";INTERVAL=\(rule.interval)"
            }
            if let endDate = rule.endDate {
                rrule += ";UNTIL=\(dateTimeFormatter.string(from: endDate))"
            }
            lines.append(rrule)
        }

        lines.append("STATUS:\(dc.isCompleted ? "CANCELLED" : "CONFIRMED")")
        lines.append("CREATED:\(dateTimeFormatter.string(from: dc.createdAt))")
        lines.append("LAST-MODIFIED:\(dateTimeFormatter.string(from: dc.updatedAt))")

        // Cider-specific extensions
        if let amount = dc.amount {
            lines.append("X-CIDER-AMOUNT:\(amount)")
        }
        if dc.isCompleted {
            lines.append("X-CIDER-COMPLETED:TRUE")
        }
        if let completedAt = dc.completedAt {
            lines.append("X-CIDER-COMPLETED-AT:\(dateTimeFormatter.string(from: completedAt))")
        }
        if !dc.labelIDs.isEmpty {
            lines.append("X-CIDER-LABEL:\(dc.labelIDs.map(\.uuidString).joined(separator: ","))")
        }
        if !dc.linkedEntities.isEmpty {
            let refs = dc.linkedEntities.map { "\($0.type.rawValue):\($0.entityID.uuidString)" }
            lines.append("X-CIDER-LINKED:\(refs.joined(separator: ","))")
        }
        if let actionURLString = dc.actionURLString {
            lines.append("X-CIDER-ACTION-URL:\(escapeICalText(actionURLString))")
        }
        if let snoozedUntil = dc.snoozedUntil {
            lines.append("X-CIDER-SNOOZED-UNTIL:\(dateTimeFormatter.string(from: snoozedUntil))")
        }
        if !dc.rules.isEmpty {
            if let jsonData = try? rulesEncoder.encode(dc.rules),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                lines.append("X-CIDER-RULES:\(escapeICalText(jsonString))")
            }
        }

        lines.append("END:VEVENT")
        lines.append("END:VCALENDAR")
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Parses an iCalendar VEVENT string into a DateCard. Returns nil if invalid.
    static func parseDateCard(_ string: String) -> DateCard? {
        let lines = unfoldLines(string)

        guard lines.contains(where: { $0.hasPrefix("BEGIN:VEVENT") }),
              lines.contains(where: { $0.hasPrefix("END:VEVENT") }) else {
            return nil
        }

        var id: UUID?
        var title = ""
        var details = ""
        var startAt: Date?
        var endAt: Date?
        var allDay = false
        var location = ""
        var amount: Double?
        var recurrenceRule: DateCardRecurrenceRule?
        var isCompleted = false
        var completedAt: Date?
        var labelIDs: [UUID] = []
        var linkedEntities: [LibraryEntityRef] = []
        var actionURLString: String?
        var snoozedUntil: Date?
        var rules: [SurfacingRule] = []
        var createdAt: Date?
        var updatedAt: Date?

        for line in lines {
            let (key, value) = splitProperty(line)
            let baseKey = key.components(separatedBy: ";").first ?? key

            switch baseKey {
            case "UID":
                id = UUID(uuidString: value)
            case "SUMMARY":
                title = unescapeICalText(value)
            case "DESCRIPTION":
                details = unescapeICalText(value)
            case "DTSTART":
                if key.contains("VALUE=DATE") {
                    startAt = CiderLocalDate.parseCompact(value)
                    allDay = true
                } else {
                    startAt = parseDateTime(value)
                }
            case "DTEND":
                if key.contains("VALUE=DATE") {
                    endAt = CiderLocalDate.parseCompact(value)
                } else {
                    endAt = parseDateTime(value)
                }
            case "LOCATION":
                location = unescapeICalText(value)
            case "RRULE":
                recurrenceRule = parseRRule(value)
            case "STATUS":
                // We use X-CIDER-COMPLETED as the authoritative source, but
                // fall back to STATUS:CANCELLED for external .ics files
                if value == "CANCELLED" { isCompleted = true }
            case "CREATED":
                createdAt = parseDateTime(value)
            case "LAST-MODIFIED":
                updatedAt = parseDateTime(value)
            case "X-CIDER-AMOUNT":
                amount = Double(value)
            case "X-CIDER-COMPLETED":
                isCompleted = value == "TRUE"
            case "X-CIDER-COMPLETED-AT":
                completedAt = parseDateTime(value)
            case "X-CIDER-LABEL":
                labelIDs = value.components(separatedBy: ",").compactMap {
                    UUID(uuidString: $0.trimmingCharacters(in: .whitespaces))
                }
            case "X-CIDER-LINKED":
                linkedEntities = parseLinkedEntities(value)
            case "X-CIDER-ACTION-URL":
                actionURLString = unescapeICalText(value)
            case "X-CIDER-SNOOZED-UNTIL":
                snoozedUntil = parseDateTime(value)
            case "X-CIDER-RULES":
                let jsonString = unescapeICalText(value)
                if let jsonData = jsonString.data(using: .utf8) {
                    rules = (try? rulesDecoder.decode([SurfacingRule].self, from: jsonData)) ?? []
                }
            default:
                break
            }
        }

        guard let dcID = id, !title.isEmpty, let start = startAt else { return nil }

        return DateCard(
            id: dcID,
            title: title,
            details: details,
            startAt: start,
            endAt: endAt,
            allDay: allDay,
            location: location,
            amount: amount,
            recurrenceRule: recurrenceRule,
            isCompleted: isCompleted,
            completedAt: completedAt,
            labelIDs: labelIDs,
            linkedEntities: linkedEntities,
            actionURLString: actionURLString,
            snoozedUntil: snoozedUntil,
            rules: rules,
            createdAt: createdAt ?? Date(),
            updatedAt: updatedAt ?? Date()
        )
    }

    /// Parses an RRULE value string like "FREQ=YEARLY;INTERVAL=1;UNTIL=20300101T000000Z"
    private static func parseRRule(_ value: String) -> DateCardRecurrenceRule? {
        var freq: DateCardRecurrenceFrequency?
        var interval = 1
        var endDate: Date?

        for part in value.components(separatedBy: ";") {
            let kv = part.components(separatedBy: "=")
            guard kv.count == 2 else { continue }
            switch kv[0] {
            case "FREQ":
                freq = DateCardRecurrenceFrequency.fromICalFreq(kv[1])
            case "INTERVAL":
                interval = Int(kv[1]) ?? 1
            case "UNTIL":
                endDate = parseDateTime(kv[1])
            default:
                break
            }
        }

        guard let frequency = freq else { return nil }
        return DateCardRecurrenceRule(frequency: frequency, interval: interval, endDate: endDate)
    }

    // MARK: - Shared Helpers

    /// iCalendar line folding: lines starting with a space are continuations.
    static func unfoldLines(_ string: String) -> [String] {
        var result: [String] = []
        for rawLine in string.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if line.isEmpty { continue }
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result
    }

    /// Splits "KEY:value" or "KEY;param:value" into (key, value).
    static func splitProperty(_ line: String) -> (String, String) {
        guard let colonIndex = line.firstIndex(of: ":") else {
            return (line, "")
        }
        let key = String(line[line.startIndex..<colonIndex])
        let value = String(line[line.index(after: colonIndex)...])
        return (key, value)
    }

    /// Escapes special characters for iCalendar text values.
    static func escapeICalText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Unescapes iCalendar text values.
    static func unescapeICalText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    /// Parses "type:uuid,type:uuid" into LibraryEntityRef array.
    static func parseLinkedEntities(_ value: String) -> [LibraryEntityRef] {
        value.components(separatedBy: ",").compactMap { pair in
            let parts = pair.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
            guard parts.count == 2,
                  let type = LibraryEntityType(rawValue: parts[0]),
                  let uuid = UUID(uuidString: parts[1]) else { return nil }
            return LibraryEntityRef(type: type, entityID: uuid)
        }
    }

    /// Parses iCalendar date-time: 20260401T090000Z or 20260401T090000
    static func parseDateTime(_ value: String) -> Date? {
        dateTimeFormatter.date(from: value)
            ?? CiderLocalDate.parseCompact(value)
    }

    static func isLocalStartOfDay(_ date: Date) -> Bool {
        let calendar = Calendar.autoupdatingCurrent
        return date == calendar.startOfDay(for: date)
    }

    // iCalendar uses yyyyMMdd'T'HHmmss'Z' (UTC)
    private static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let checklistEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let checklistDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let rulesEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let rulesDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

// MARK: - iCalendar RRULE frequency mapping

extension DateCardRecurrenceFrequency {
    var icalFreq: String {
        switch self {
        case .daily: "DAILY"
        case .weekly: "WEEKLY"
        case .monthly: "MONTHLY"
        case .yearly: "YEARLY"
        }
    }

    static func fromICalFreq(_ value: String) -> DateCardRecurrenceFrequency? {
        switch value.uppercased() {
        case "DAILY": .daily
        case "WEEKLY": .weekly
        case "MONTHLY": .monthly
        case "YEARLY": .yearly
        default: nil
        }
    }
}
