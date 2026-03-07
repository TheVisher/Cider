import Combine
import Foundation

private struct TodoCardsSnapshot: Codable {
    var todoCards: [TodoCard]
}

@MainActor
final class TodoCardStorage: ObservableObject {
    static let shared = TodoCardStorage()

    @Published private(set) var todoCards: [TodoCard] = []

    private let fileName = "_cider_todo_cards.json"
    private var fileURL: URL {
        let dir = StoragePaths.directoryURL(for: .todos)
        StoragePaths.ensureDirectory(dir)
        return StoragePaths.jsonFileURL(fileName: fileName, in: dir)
    }

    private init() {
        load()
    }

    func reload() {
        load()
    }

    @discardableResult
    func createTodoCard(title: String, dueDate: Date? = nil, priority: TodoPriority? = nil) -> TodoCard {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = trimmed.isEmpty ? "Untitled Todo" : trimmed
        let todoCard = TodoCard(
            title: finalTitle,
            dueDate: dueDate,
            priority: priority
        )
        todoCards.append(todoCard)
        sortCards()
        persist()
        return todoCard
    }

    @discardableResult
    func updateTodoCard(_ updated: TodoCard) -> Bool {
        guard let idx = todoCards.firstIndex(where: { $0.id == updated.id }) else { return false }
        var copy = updated
        copy.updatedAt = Date()
        todoCards[idx] = copy
        sortCards()
        persist()
        return true
    }

    @discardableResult
    func deleteTodoCard(_ id: UUID) -> TrashItem? {
        guard let todoCard = todoCards.first(where: { $0.id == id }) else { return nil }
        let trashItem = TrashStorage.shared.trashTodoCard(todoCard, todoCardsDir: StoragePaths.cachedDirectoryURL(for: .todos))
        todoCards.removeAll { $0.id == id }
        persist()
        return trashItem
    }

    @discardableResult
    func markCompleted(_ id: UUID, completed: Bool) -> Bool {
        guard let idx = todoCards.firstIndex(where: { $0.id == id }) else { return false }
        todoCards[idx].isCompleted = completed
        todoCards[idx].completedAt = completed ? Date() : nil
        todoCards[idx].updatedAt = Date()
        persist()
        return true
    }

    @discardableResult
    func toggleChecklistItem(_ todoID: UUID, checklistItemID: UUID) -> Bool {
        guard let todoIdx = todoCards.firstIndex(where: { $0.id == todoID }),
              let itemIdx = todoCards[todoIdx].checklist.firstIndex(where: { $0.id == checklistItemID }) else {
            return false
        }
        let wasCompleted = todoCards[todoIdx].checklist[itemIdx].isCompleted
        todoCards[todoIdx].checklist[itemIdx].isCompleted = !wasCompleted
        todoCards[todoIdx].checklist[itemIdx].completedAt = wasCompleted ? nil : Date()
        todoCards[todoIdx].updatedAt = Date()
        persist()
        return true
    }

    @discardableResult
    func assignTodoCard(_ id: UUID, toFolder folderID: UUID?) -> Bool {
        guard let idx = todoCards.firstIndex(where: { $0.id == id }) else { return false }
        todoCards[idx].folderID = folderID
        todoCards[idx].updatedAt = Date()
        persist()
        return true
    }

    func todoCard(for id: UUID) -> TodoCard? {
        todoCards.first { $0.id == id }
    }

    func removeLabelsFromAll(labelID: UUID) {
        var changed = false
        for i in todoCards.indices where todoCards[i].labelIDs.contains(labelID) {
            todoCards[i].labelIDs.removeAll { $0 == labelID }
            todoCards[i].updatedAt = Date()
            changed = true
        }
        if changed { persist() }
    }

    func restoreFromTrash(_ todoCard: TodoCard) {
        guard !todoCards.contains(where: { $0.id == todoCard.id }) else { return }
        todoCards.append(todoCard)
        sortCards()
        persist()
    }

    private func sortCards() {
        todoCards.sort { lhs, rhs in
            // Incomplete before completed
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted
            }
            // By due date (earliest first, nil last)
            switch (lhs.dueDate, rhs.dueDate) {
            case (let l?, let r?):
                if l != r { return l < r }
            case (nil, .some):
                return false
            case (.some, nil):
                return true
            case (nil, nil):
                break
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snapshot = try decoder.decode(TodoCardsSnapshot.self, from: data)
            todoCards = snapshot.todoCards
            sortCards()
        } catch {
            todoCards = []
        }
    }

    private func persist() {
        let snapshot = TodoCardsSnapshot(todoCards: todoCards)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort persistence.
        }
    }
}
