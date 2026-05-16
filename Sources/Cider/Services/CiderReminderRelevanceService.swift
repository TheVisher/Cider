import Foundation

struct CiderReminderRelevanceItem: Equatable, Identifiable {
    enum ItemType: String, Equatable {
        case todo
        case dateCard
    }

    let id: UUID
    let itemType: ItemType
    let title: String
    let surfaceToday: Bool
    let dueAt: Date?
    let surfacing: CiderSurfacingExplanation
}

enum CiderReminderRelevanceService {
    static func relevance(
        todos: [TodoCard],
        dateCards: [DateCard],
        now: Date = Date(),
        calendar: Calendar = .current,
        options: AgendaBriefingOptions = .default
    ) -> [CiderReminderRelevanceItem] {
        let agenda = AgendaBriefingService.build(
            todos: todos,
            dateCards: dateCards,
            now: now,
            calendar: calendar,
            options: options
        )
        let agendaItems = agenda.items.map(relevanceItem)
        let missingReminderItems = todos
            .filter { !$0.isCompleted && $0.earliestApproachingDate == nil }
            .map(missingReminderItem)
        return (agendaItems + missingReminderItems).sorted(by: sortItems)
    }

    private static func relevanceItem(_ item: AgendaBriefingItem) -> CiderReminderRelevanceItem {
        CiderReminderRelevanceItem(
            id: item.id,
            itemType: item.itemType == .todo ? .todo : .dateCard,
            title: item.title,
            surfaceToday: item.surfaceToday,
            dueAt: item.dueAt,
            surfacing: CiderSurfacingExplanation(
                reason: item.reason,
                urgency: urgency(for: item),
                sourceSignal: "reminder_relevance",
                reviewState: reviewState(for: item),
                suggestedAction: suggestedAction(for: item),
                actionURLString: item.actionURLString
            )
        )
    }

    private static func missingReminderItem(_ todo: TodoCard) -> CiderReminderRelevanceItem {
        CiderReminderRelevanceItem(
            id: todo.id,
            itemType: .todo,
            title: todo.title,
            surfaceToday: true,
            dueAt: nil,
            surfacing: CiderSurfacingExplanation(
                reason: "Todo is missing a reminder",
                urgency: "review",
                sourceSignal: "reminder_relevance",
                reviewState: "needs_review",
                suggestedAction: "Add reminder",
                actionURLString: todo.actionURLString
            )
        )
    }

    private static func urgency(for item: AgendaBriefingItem) -> String {
        switch item.status {
        case .overdue: return "overdue"
        case .today: return "today"
        case .upcoming: return "upcoming"
        case .active: return "action"
        case .completed, .suppressed, .later: return "normal"
        }
    }

    private static func reviewState(for item: AgendaBriefingItem) -> String {
        if item.itemType == .dateCard && item.actionURLString == nil && item.surfaceToday {
            return "pending"
        }
        return "ok"
    }

    private static func suggestedAction(for item: AgendaBriefingItem) -> String {
        if let suggestedAction = item.suggestedAction {
            return suggestedAction
        }
        if item.itemType == .dateCard && item.actionURLString == nil && item.surfaceToday {
            return "Add action URL"
        }
        return item.surfaceToday ? "Do next" : "Wait"
    }

    private static func sortItems(_ lhs: CiderReminderRelevanceItem, _ rhs: CiderReminderRelevanceItem) -> Bool {
        if lhs.surfaceToday != rhs.surfaceToday { return lhs.surfaceToday && !rhs.surfaceToday }
        if surfaceRank(lhs) != surfaceRank(rhs) { return surfaceRank(lhs) < surfaceRank(rhs) }
        if lhs.dueAt != rhs.dueAt { return (lhs.dueAt ?? .distantFuture) < (rhs.dueAt ?? .distantFuture) }
        if itemTypeRank(lhs.itemType) != itemTypeRank(rhs.itemType) {
            return itemTypeRank(lhs.itemType) < itemTypeRank(rhs.itemType)
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func surfaceRank(_ item: CiderReminderRelevanceItem) -> Int {
        switch item.surfacing.urgency {
        case "overdue": return 0
        case "today": return 1
        case "upcoming", "action": return 2
        case "review": return 3
        default: return 4
        }
    }

    private static func itemTypeRank(_ itemType: CiderReminderRelevanceItem.ItemType) -> Int {
        switch itemType {
        case .todo: return 0
        case .dateCard: return 1
        }
    }
}
