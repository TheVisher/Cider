import Foundation

enum CiderReminderActionItemType: String, Equatable {
    case todo
    case dateCard
}

enum CiderReminderAction: String, Equatable {
    case complete
    case snooze
}

struct CiderReminderActionResult: Equatable {
    let itemType: CiderReminderActionItemType
    let id: UUID
    let title: String
    let action: CiderReminderAction
    let completed: Bool
    let snoozedUntil: Date?
    let surfacing: CiderReminderRelevanceItem?
}

enum CiderReminderActionError: Error, LocalizedError {
    case itemNotFound(CiderReminderActionItemType, UUID)
    case updateFailed(CiderReminderActionItemType, UUID)
    case invalidSnoozeDate

    var errorDescription: String? {
        switch self {
        case .itemNotFound(let itemType, let id):
            return "No \(itemType.rawValue) reminder found with id \(id.uuidString)"
        case .updateFailed(let itemType, let id):
            return "Failed to update \(itemType.rawValue) reminder \(id.uuidString)"
        case .invalidSnoozeDate:
            return "Snooze date must be in the future"
        }
    }
}

@MainActor
final class CiderReminderActionService {
    private let todoProvider: () -> [TodoCard]
    private let dateCardProvider: () -> [DateCard]
    private let updateTodo: (TodoCard) -> Bool
    private let updateDateCard: (DateCard) -> Bool
    private let nowProvider: () -> Date
    private let calendar: Calendar

    init(
        todoStorage: TodoCardStorage = .shared,
        dateCardStorage: DateCardStorage = .shared,
        nowProvider: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.todoProvider = { todoStorage.todoCards }
        self.dateCardProvider = { dateCardStorage.dateCards }
        self.updateTodo = { todoStorage.updateTodoCard($0) }
        self.updateDateCard = { dateCardStorage.updateDateCard($0) }
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    init(
        todoProvider: @escaping () -> [TodoCard],
        dateCardProvider: @escaping () -> [DateCard],
        updateTodo: @escaping (TodoCard) -> Bool,
        updateDateCard: @escaping (DateCard) -> Bool,
        nowProvider: @escaping () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.todoProvider = todoProvider
        self.dateCardProvider = dateCardProvider
        self.updateTodo = updateTodo
        self.updateDateCard = updateDateCard
        self.nowProvider = nowProvider
        self.calendar = calendar
    }

    func complete(_ itemType: CiderReminderActionItemType, id: UUID) throws -> CiderReminderActionResult {
        let now = nowProvider()
        switch itemType {
        case .todo:
            var todo = try todo(id)
            todo.isCompleted = true
            todo.completedAt = now
            todo.snoozedUntil = nil
            todo.updatedAt = now
            guard updateTodo(todo) else { throw CiderReminderActionError.updateFailed(itemType, id) }
            return result(for: todo, action: .complete)

        case .dateCard:
            var dateCard = try dateCard(id)
            dateCard.isCompleted = true
            dateCard.completedAt = now
            dateCard.snoozedUntil = nil
            dateCard.updatedAt = now
            guard updateDateCard(dateCard) else { throw CiderReminderActionError.updateFailed(itemType, id) }
            return result(for: dateCard, action: .complete)
        }
    }

    func snooze(_ itemType: CiderReminderActionItemType, id: UUID, until snoozedUntil: Date) throws -> CiderReminderActionResult {
        let now = nowProvider()
        guard snoozedUntil > now else {
            throw CiderReminderActionError.invalidSnoozeDate
        }

        switch itemType {
        case .todo:
            var todo = try todo(id)
            todo.snoozedUntil = snoozedUntil
            todo.updatedAt = now
            guard updateTodo(todo) else { throw CiderReminderActionError.updateFailed(itemType, id) }
            return result(for: todo, action: .snooze)

        case .dateCard:
            var dateCard = try dateCard(id)
            dateCard.snoozedUntil = snoozedUntil
            dateCard.updatedAt = now
            guard updateDateCard(dateCard) else { throw CiderReminderActionError.updateFailed(itemType, id) }
            return result(for: dateCard, action: .snooze)
        }
    }

    private func todo(_ id: UUID) throws -> TodoCard {
        guard let todo = todoProvider().first(where: { $0.id == id }) else {
            throw CiderReminderActionError.itemNotFound(.todo, id)
        }
        return todo
    }

    private func dateCard(_ id: UUID) throws -> DateCard {
        guard let dateCard = dateCardProvider().first(where: { $0.id == id }) else {
            throw CiderReminderActionError.itemNotFound(.dateCard, id)
        }
        return dateCard
    }

    private func result(for todo: TodoCard, action: CiderReminderAction) -> CiderReminderActionResult {
        CiderReminderActionResult(
            itemType: .todo,
            id: todo.id,
            title: todo.title,
            action: action,
            completed: todo.isCompleted,
            snoozedUntil: todo.snoozedUntil,
            surfacing: surfacing(for: .todo, id: todo.id)
        )
    }

    private func result(for dateCard: DateCard, action: CiderReminderAction) -> CiderReminderActionResult {
        CiderReminderActionResult(
            itemType: .dateCard,
            id: dateCard.id,
            title: dateCard.title,
            action: action,
            completed: dateCard.isCompleted,
            snoozedUntil: dateCard.snoozedUntil,
            surfacing: surfacing(for: .dateCard, id: dateCard.id)
        )
    }

    private func surfacing(for itemType: CiderReminderActionItemType, id: UUID) -> CiderReminderRelevanceItem? {
        let relevanceType: CiderReminderRelevanceItem.ItemType = itemType == .todo ? .todo : .dateCard
        return CiderReminderRelevanceService.relevance(
            todos: todoProvider(),
            dateCards: dateCardProvider(),
            now: nowProvider(),
            calendar: calendar
        )
        .first { $0.itemType == relevanceType && $0.id == id }
    }
}
