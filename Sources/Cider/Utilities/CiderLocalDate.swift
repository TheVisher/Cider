import Foundation

enum CiderLocalDate {
    static func calendar(timeZone: TimeZone = .autoupdatingCurrent) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    static func date(
        year: Int,
        month: Int,
        day: Int,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Date? {
        calendar(timeZone: timeZone).date(from: DateComponents(year: year, month: month, day: day))
    }

    static func parseDashed(_ value: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        parse(value, format: "yyyy-MM-dd", timeZone: timeZone)
    }

    static func formatDashed(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, format: "yyyy-MM-dd", timeZone: timeZone)
    }

    static func parseCompact(_ value: String, timeZone: TimeZone = .autoupdatingCurrent) -> Date? {
        parse(value, format: "yyyyMMdd", timeZone: timeZone)
    }

    static func formatCompact(_ date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        format(date, format: "yyyyMMdd", timeZone: timeZone)
    }

    static func localDate(fromUTCDateOnlyInstant date: Date, timeZone: TimeZone = .autoupdatingCurrent) -> Date {
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year,
              let month = components.month,
              let day = components.day,
              let localDate = self.date(year: year, month: month, day: day, timeZone: timeZone) else {
            return date
        }
        return localDate
    }

    private static func parse(_ value: String, format: String, timeZone: TimeZone) -> Date? {
        formatter(format: format, timeZone: timeZone).date(from: value)
    }

    private static func format(_ date: Date, format: String, timeZone: TimeZone) -> String {
        formatter(format: format, timeZone: timeZone).string(from: date)
    }

    private static func formatter(format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        return formatter
    }
}
