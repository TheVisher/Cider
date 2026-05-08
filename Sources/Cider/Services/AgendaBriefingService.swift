import Foundation

struct AgendaBriefing: Equatable {
    let generatedAt: Date
    let items: [AgendaBriefingItem]
}

struct AgendaBriefingItem: Identifiable, Equatable {
    enum ItemType: String {
        case todo
        case dateCard
    }

    enum Status: String {
        case active
        case completed
        case overdue
        case today
        case upcoming
        case suppressed
        case later
    }

    enum Bucket: String {
        case now
        case today
        case upcoming
        case later
        case suppressed
    }

    let id: UUID
    let itemType: ItemType
    let title: String
    let status: Status
    let bucket: Bucket
    let surfaceToday: Bool
    let reason: String
    let dueAt: Date?
    let nextSurfaceDate: Date?
    let priority: String?
    let actionURLString: String?
}

struct AgendaBriefingOptions: Equatable {
    var todoLeadDays: Int = 7
    var dateCardLeadDays: Int = 7
    var birthdayLeadDays: Int = 14
    var monthlyBillLeadDays: Int = 5

    static let `default` = AgendaBriefingOptions()
}

enum AgendaBriefingService {
    static func build(
        todos: [TodoCard],
        dateCards: [DateCard],
        now: Date = Date(),
        calendar: Calendar = .current,
        options: AgendaBriefingOptions = .default
    ) -> AgendaBriefing {
        let completedTodoTitles = Set(
            todos
                .filter { $0.isCompleted }
                .map { normalizedTitle($0.title) }
        )

        var items: [AgendaBriefingItem] = []
        items += todos.compactMap { todoItem(for: $0, now: now, calendar: calendar, options: options) }
        items += dateCards.compactMap { dateCardItem(for: $0, completedTodoTitles: completedTodoTitles, now: now, calendar: calendar, options: options) }

        return AgendaBriefing(
            generatedAt: now,
            items: items.sorted(by: sortItems)
        )
    }

    private static func todoItem(
        for todo: TodoCard,
        now: Date,
        calendar: Calendar,
        options: AgendaBriefingOptions
    ) -> AgendaBriefingItem? {
        if todo.isCompleted { return nil }
        guard let dueAt = todo.earliestApproachingDate else { return nil }

        let days = daysBetween(now, dueAt, calendar: calendar)
        let status: AgendaBriefingItem.Status
        let bucket: AgendaBriefingItem.Bucket
        let surfaceToday: Bool
        let reason: String
        let nextSurfaceDate: Date?

        if days < 0 {
            status = .overdue
            bucket = .now
            surfaceToday = true
            reason = "overdue"
            nextSurfaceDate = now
        } else if days == 0 {
            status = .today
            bucket = .today
            surfaceToday = true
            reason = "due today"
            nextSurfaceDate = now
        } else if days <= options.todoLeadDays {
            status = .upcoming
            bucket = .upcoming
            surfaceToday = true
            reason = "due in \(days) day\(days == 1 ? "" : "s")"
            nextSurfaceDate = now
        } else {
            status = .later
            bucket = .later
            surfaceToday = false
            reason = "outside reminder window"
            nextSurfaceDate = calendar.date(byAdding: .day, value: -options.todoLeadDays, to: calendar.startOfDay(for: dueAt))
        }

        return AgendaBriefingItem(
            id: todo.id,
            itemType: .todo,
            title: todo.title,
            status: status,
            bucket: bucket,
            surfaceToday: surfaceToday,
            reason: reason,
            dueAt: dueAt,
            nextSurfaceDate: nextSurfaceDate,
            priority: todo.priority?.rawValue,
            actionURLString: todo.actionURLString
        )
    }

    private static func dateCardItem(
        for card: DateCard,
        completedTodoTitles: Set<String>,
        now: Date,
        calendar: Calendar,
        options: AgendaBriefingOptions
    ) -> AgendaBriefingItem? {
        if card.isCompleted { return nil }

        let effectiveDate = card.effectiveDate(now: now)
        let normalized = normalizedTitle(card.title)
        if completedTodoTitles.contains(normalized), calendar.isDate(effectiveDate, equalTo: now, toGranularity: .month) {
            return AgendaBriefingItem(
                id: card.id,
                itemType: .dateCard,
                title: card.title,
                status: .suppressed,
                bucket: .suppressed,
                surfaceToday: false,
                reason: "suppressed by completed same-cycle todo",
                dueAt: effectiveDate,
                nextSurfaceDate: nil,
                priority: nil,
                actionURLString: card.actionURLString
            )
        }

        let leadDays = leadDays(for: card, options: options)
        let days = daysBetween(now, effectiveDate, calendar: calendar)
        let status: AgendaBriefingItem.Status
        let bucket: AgendaBriefingItem.Bucket
        let surfaceToday: Bool
        let reason: String
        let nextSurfaceDate: Date?

        if days < 0 {
            status = .overdue
            bucket = .now
            surfaceToday = true
            reason = "overdue"
            nextSurfaceDate = now
        } else if days == 0 {
            status = .today
            bucket = .today
            surfaceToday = true
            reason = "today"
            nextSurfaceDate = now
        } else if days <= leadDays {
            status = .upcoming
            bucket = .upcoming
            surfaceToday = true
            reason = "upcoming in \(days) day\(days == 1 ? "" : "s")"
            nextSurfaceDate = now
        } else {
            status = .later
            bucket = .later
            surfaceToday = false
            reason = "outside reminder window"
            nextSurfaceDate = calendar.date(byAdding: .day, value: -leadDays, to: calendar.startOfDay(for: effectiveDate))
        }

        return AgendaBriefingItem(
            id: card.id,
            itemType: .dateCard,
            title: card.title,
            status: status,
            bucket: bucket,
            surfaceToday: surfaceToday,
            reason: reason,
            dueAt: effectiveDate,
            nextSurfaceDate: nextSurfaceDate,
            priority: nil,
            actionURLString: card.actionURLString
        )
    }

    private static func leadDays(for card: DateCard, options: AgendaBriefingOptions) -> Int {
        if let explicit = card.rules.first(where: { $0.type == .surfaceDaysBeforeDate && $0.isEnabled })?.integerValue {
            return max(explicit, 0)
        }
        let title = normalizedTitle(card.title)
        if title.contains("birthday") || title.contains("anniversary") {
            return options.birthdayLeadDays
        }
        if card.recurrenceRule?.frequency == .monthly || title.contains("rent") || title.contains("bill") {
            return options.monthlyBillLeadDays
        }
        return options.dateCardLeadDays
    }

    private static func daysBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .split(separator: " ")
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sortItems(_ lhs: AgendaBriefingItem, _ rhs: AgendaBriefingItem) -> Bool {
        if lhs.surfaceToday != rhs.surfaceToday { return lhs.surfaceToday && !rhs.surfaceToday }
        if lhs.bucket != rhs.bucket { return bucketRank(lhs.bucket) < bucketRank(rhs.bucket) }
        return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture)
    }

    private static func bucketRank(_ bucket: AgendaBriefingItem.Bucket) -> Int {
        switch bucket {
        case .now: return 0
        case .today: return 1
        case .upcoming: return 2
        case .later: return 3
        case .suppressed: return 4
        }
    }
}
