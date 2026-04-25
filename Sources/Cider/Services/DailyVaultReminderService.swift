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
        displayName: String = "there",
        config: Config = Config()
    ) -> Reminder? {
        let resurfacedItems = selectResurfacedItems(
            now: now,
            bookmarks: bookmarks,
            notes: notes,
            resurfacedAt: resurfacedAt,
            config: config
        )

        let items = makeLibraryItems(
            dateCards: dateCards,
            todos: todos,
            bookmarks: bookmarks,
            notes: notes
        )
        let recentItems = Array(items.sorted { lhs, rhs in
            if lhs.updatedDate == rhs.updatedDate {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.updatedDate > rhs.updatedDate
        }.prefix(8))
        let snapshot = HomeOverviewDataProvider.makeSnapshot(
            items: items,
            recentItems: recentItems,
            folders: [],
            surfacingDays: config.upcomingDays,
            now: now
        )
        let message = telegramMessage(
            from: snapshot,
            resurfacedItems: resurfacedItems,
            displayName: displayName,
            now: now
        )

        guard message.isEmpty == false else { return nil }

        return Reminder(
            message: message,
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

    private static func makeLibraryItems(
        dateCards: [DateCard],
        todos: [TodoCard],
        bookmarks: [Bookmark],
        notes: [Note]
    ) -> [LibraryItemV2] {
        bookmarks.map(LibraryItemV2.bookmark)
            + notes.map(LibraryItemV2.note)
            + dateCards.map(LibraryItemV2.dateCard)
            + todos.map(LibraryItemV2.todo)
    }

    private static func telegramMessage(
        from snapshot: HomeOverviewSnapshot,
        resurfacedItems: [ResurfacedItem],
        displayName: String,
        now: Date
    ) -> String {
        guard snapshot.dailyBrief.focusItems.isEmpty == false
            || snapshot.todoItems.isEmpty == false
            || snapshot.completedTodoItems.isEmpty == false
            || snapshot.upcomingItems.isEmpty == false
            || snapshot.recentItems.isEmpty == false
            || resurfacedItems.isEmpty == false
        else {
            return ""
        }

        var lines = [
            HomeOverviewDataProvider.dailyBriefGreetingText(
                for: snapshot.dailyBrief,
                displayName: displayName,
                now: now
            ),
            snapshot.dailyBrief.dateLabel,
            dailyBriefSummaryText(snapshot.dailyBrief.summaryParts)
        ]

        if !snapshot.dailyBrief.focusItems.isEmpty {
            lines.append("")
            lines.append("Focus")
            lines.append(contentsOf: snapshot.dailyBrief.focusItems.map { "- \($0.title): \($0.subtitle)" })
        }

        let openTodos = snapshot.todoItems.prefix(4).map(formatOpenTodo)
        let completedTodos = snapshot.completedTodoItems.prefix(3).map(formatCompletedTodo)
        if !openTodos.isEmpty || !completedTodos.isEmpty {
            lines.append("")
            lines.append("Action Items")
            if !openTodos.isEmpty {
                lines.append(contentsOf: openTodos)
            }
            if !completedTodos.isEmpty {
                if !openTodos.isEmpty {
                    lines.append("")
                }
                lines.append("Done")
                lines.append(contentsOf: completedTodos)
            }
        }

        let upcomingLines = snapshot.upcomingItems.prefix(4).map { formatUpcomingItem($0, now: now) }
        if !upcomingLines.isEmpty {
            lines.append("")
            lines.append("Today + Upcoming")
            lines.append(contentsOf: upcomingLines)
        }

        let recentLines = snapshot.recentItems.prefix(4).map { formatRecentItem($0, now: now) }
        if !recentLines.isEmpty {
            lines.append("")
            lines.append("Recent Activity")
            lines.append(contentsOf: recentLines)
        }

        if !resurfacedItems.isEmpty {
            lines.append("")
            lines.append("Quiet Threads")
            lines.append(contentsOf: resurfacedItems.map(formatResurfacedItem))
        }

        return lines.joined(separator: "\n")
    }

    private static func dailyBriefSummaryText(_ parts: [HomeDailyBriefSummaryPart]) -> String {
        parts.map { part in
            part.chip?.label ?? part.text
        }
        .joined()
        .replacingOccurrences(of: " ,", with: ",")
    }

    private static func formatOpenTodo(_ todo: TodoCard) -> String {
        var components = ["- \(todo.title)"]
        if let priority = todo.priority {
            components.append("[\(priority.displayName)]")
        }
        if let dueDate = todo.dueDate {
            components.append("due \(formattedDateTime(dueDate, hasExplicitTime: todo.hasExplicitDueTime))")
        }
        return components.joined(separator: " ")
    }

    private static func formatCompletedTodo(_ todo: TodoCard) -> String {
        let completedAt = todo.completedAt ?? todo.updatedAt
        return "- \(todo.title) - done \(formattedDateTime(completedAt, hasExplicitTime: true))"
    }

    private static func formatUpcomingItem(_ item: LibraryItemV2, now: Date) -> String {
        switch item {
        case .dateCard(let dateCard):
            return "- \(formattedOccurrencePrefix(dateCard.effectiveDate(now: now), now: now)): \(dateCard.title) (\(dateCard.allDay ? "all day" : formattedDateTime(dateCard.effectiveDate(now: now), hasExplicitTime: true)))"
        case .todo(let todo):
            return formatOpenTodo(todo)
        default:
            return "- \(item.title)"
        }
    }

    private static func formatRecentItem(_ item: LibraryItemV2, now: Date) -> String {
        let kind: String
        switch item {
        case .bookmark:
            kind = "Bookmark"
        case .note:
            kind = "Note"
        case .dateCard:
            kind = "Event"
        case .contact:
            kind = "Contact"
        case .todo(let todo):
            kind = todo.isCompleted ? "Completed todo" : "Todo"
        case .vaultFile:
            kind = "File"
        }

        return "- \(kind): \(item.title) - \(relativeDateLabel(item.updatedDate, now: now))"
    }

    private static func relativeDateLabel(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
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
