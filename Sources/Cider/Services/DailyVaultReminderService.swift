import Foundation

struct DailyVaultReminderService {
    struct Config {
        var resurfacingItemCount: Int = 3
        var resurfacingMinAgeDays: Int = 30
        var resurfacingCooldownDays: Int = 14
        var upcomingDays: Int = 2
        var maxTodaySoonLines: Int = 6
    }

    struct Reminder {
        let message: String
        let resurfacedItemKeys: [String]
    }

    private struct ResurfacedItem {
        let key: String
        let kind: String
        let title: String
        let lastTouchedAt: Date
    }

    static func buildReminder(
        now: Date,
        dateCards: [DateCard],
        todos: [TodoCard],
        bookmarks: [Bookmark],
        notes: [Note],
        resurfacedAt: [String: Date],
        config: Config = Config()
    ) -> Reminder? {
        let todaySoonLines = buildTodaySoonLines(
            now: now,
            dateCards: dateCards,
            todos: todos,
            config: config
        )
        let resurfacedItems = selectResurfacedItems(
            now: now,
            bookmarks: bookmarks,
            notes: notes,
            resurfacedAt: resurfacedAt,
            config: config
        )

        guard !todaySoonLines.isEmpty || !resurfacedItems.isEmpty else { return nil }

        var lines = ["Good morning. Here's your daily vault reminder:"]

        lines.append("")
        lines.append("Today / Soon")
        if todaySoonLines.isEmpty {
            lines.append("- Nothing urgent on deck right now.")
        } else {
            lines.append(contentsOf: todaySoonLines)
        }

        if !resurfacedItems.isEmpty {
            lines.append("")
            lines.append("Resurface \(resurfacedItems.count)")
            lines.append(contentsOf: resurfacedItems.map(formatResurfacedItem))
        }

        return Reminder(
            message: lines.joined(separator: "\n"),
            resurfacedItemKeys: resurfacedItems.map(\.key)
        )
    }

    static func pruneResurfacedHistory(
        _ resurfacedAt: [String: Date],
        now: Date,
        config: Config = Config()
    ) -> [String: Date] {
        let cutoff = now.addingTimeInterval(-Double(max(config.resurfacingCooldownDays, 1)) * 24 * 3600)
        return resurfacedAt.filter { $0.value >= cutoff }
    }

    private static func buildTodaySoonLines(
        now: Date,
        dateCards: [DateCard],
        todos: [TodoCard],
        config: Config
    ) -> [String] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        guard let horizonEnd = calendar.date(byAdding: .day, value: max(config.upcomingDays, 0) + 1, to: startOfToday) else {
            return []
        }

        var lines: [String] = []

        let overdueTodos = todos
            .filter { !$0.isCompleted && ($0.dueDate ?? .distantFuture) < startOfToday }
            .sorted {
                let lhs = $0.dueDate ?? .distantFuture
                let rhs = $1.dueDate ?? .distantFuture
                if lhs == rhs {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return lhs < rhs
            }

        for todo in overdueTodos.prefix(2) {
            lines.append("- Overdue todo: \(todo.title)\(formattedTodoDate(todo))")
        }

        let dueSoonTodos = todos
            .filter { todo in
                guard !todo.isCompleted, let dueDate = todo.dueDate else { return false }
                return dueDate >= startOfToday && dueDate < horizonEnd
            }
            .sorted {
                let lhs = $0.dueDate ?? .distantFuture
                let rhs = $1.dueDate ?? .distantFuture
                if lhs == rhs {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return lhs < rhs
            }

        for todo in dueSoonTodos.prefix(2) {
            let prefix = calendar.isDateInToday(todo.dueDate ?? now) ? "Today todo" : "Soon todo"
            lines.append("- \(prefix): \(todo.title)\(formattedTodoDate(todo))")
        }

        let occurrences = upcomingOccurrences(
            for: dateCards,
            from: startOfToday,
            to: horizonEnd.addingTimeInterval(-1),
            now: now
        )

        for occurrence in occurrences.prefix(3) {
            lines.append("- \(formattedOccurrencePrefix(occurrence.occurrence, now: now)): \(occurrence.card.title) (\(formattedOccurrenceTime(occurrence)))")
        }

        return Array(lines.prefix(max(config.maxTodaySoonLines, 1)))
    }

    private static func selectResurfacedItems(
        now: Date,
        bookmarks: [Bookmark],
        notes: [Note],
        resurfacedAt: [String: Date],
        config: Config
    ) -> [ResurfacedItem] {
        let minAgeCutoff = now.addingTimeInterval(-Double(max(config.resurfacingMinAgeDays, 1)) * 24 * 3600)
        let cooldownCutoff = now.addingTimeInterval(-Double(max(config.resurfacingCooldownDays, 1)) * 24 * 3600)

        let bookmarkCandidates = bookmarks.map {
            ResurfacedItem(
                key: "bookmark:\($0.id.uuidString)",
                kind: "Bookmark",
                title: $0.title,
                lastTouchedAt: $0.updatedAt
            )
        }

        let noteCandidates = notes.map {
            ResurfacedItem(
                key: "note:\($0.id.uuidString)",
                kind: "Note",
                title: $0.title,
                lastTouchedAt: $0.modifiedAt
            )
        }

        return (bookmarkCandidates + noteCandidates)
            .filter { item in
                guard item.lastTouchedAt <= minAgeCutoff else { return false }
                if let lastSurfacedAt = resurfacedAt[item.key], lastSurfacedAt > cooldownCutoff {
                    return false
                }
                return true
            }
            .sorted {
                if $0.lastTouchedAt == $1.lastTouchedAt {
                    if $0.kind == $1.kind {
                        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                    }
                    return $0.kind < $1.kind
                }
                return $0.lastTouchedAt < $1.lastTouchedAt
            }
            .prefix(max(config.resurfacingItemCount, 0))
            .map { $0 }
    }

    private struct ScheduledOccurrence {
        let card: DateCard
        let occurrence: Date
    }

    private static func upcomingOccurrences(
        for dateCards: [DateCard],
        from start: Date,
        to end: Date,
        now: Date
    ) -> [ScheduledOccurrence] {
        var results: [ScheduledOccurrence] = []

        for card in dateCards {
            if card.isCompleted, card.recurrenceRule == nil { continue }

            if card.recurrenceRule != nil {
                var cursor = card.effectiveDate(now: now)
                while cursor <= end {
                    if cursor >= start {
                        results.append(ScheduledOccurrence(card: card, occurrence: cursor))
                    }
                    guard let next = card.nextOccurrence(after: cursor) else { break }
                    cursor = next
                }
            } else {
                let target = card.startAt
                if target >= start && target <= end {
                    results.append(ScheduledOccurrence(card: card, occurrence: target))
                }
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.occurrence == rhs.occurrence {
                return lhs.card.title.localizedCaseInsensitiveCompare(rhs.card.title) == .orderedAscending
            }
            return lhs.occurrence < rhs.occurrence
        }
    }

    private static func formattedTodoDate(_ todo: TodoCard) -> String {
        guard let dueDate = todo.dueDate else { return "" }
        return " (\(formattedDateTime(dueDate, hasExplicitTime: todo.hasExplicitDueTime)))"
    }

    private static func formattedOccurrencePrefix(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    private static func formattedOccurrenceTime(_ occurrence: ScheduledOccurrence) -> String {
        if occurrence.card.allDay {
            return "all day"
        }
        return formattedDateTime(occurrence.occurrence, hasExplicitTime: true)
    }

    private static func formattedDateTime(_ date: Date, hasExplicitTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = hasExplicitTime ? "MMM d, h:mm a" : "MMM d"
        return formatter.string(from: date)
    }

    private static func formatResurfacedItem(_ item: ResurfacedItem) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = .current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "- \(item.kind): \(item.title) (last touched \(formatter.string(from: item.lastTouchedAt)))"
    }
}
