import Foundation

struct CiderBookmarkDateSuggestionApprovalDraft: Equatable {
    let title: String
    let details: String
    let startAt: Date
    let allDay: Bool
    let actionURLString: String?
}

struct CiderBookmarkDateSuggestionTodoApprovalDraft: Equatable {
    let title: String
    let details: String
    let dueDate: Date
    let actionURLString: String?
}

enum CiderBookmarkDateSuggestionApprovalAction: String, Equatable {
    case createdDateCard = "created_date_card"
    case reusedExistingDateCard = "reused_existing_date_card"
    case createdTodo = "created_todo"
    case reusedExistingTodo = "reused_existing_todo"
}

struct CiderBookmarkDateSuggestionApprovalResult: Equatable {
    let command: String
    let bookmarkID: UUID
    let bookmarkTitle: String
    let sourceURL: String
    let suggestion: CiderBookmarkDateSuggestion
    let action: CiderBookmarkDateSuggestionApprovalAction
    let dateCard: DateCard?
    let todo: TodoCard?

    var created: Bool {
        switch action {
        case .createdDateCard, .createdTodo: true
        case .reusedExistingDateCard, .reusedExistingTodo: false
        }
    }

    var reused: Bool { !created }

    var createdItemType: LibraryEntityType {
        todo == nil ? .dateCard : .todo
    }
}

enum CiderBookmarkDateSuggestionApprovalError: Error, LocalizedError, Equatable {
    case bookmarkNotFound(UUID)
    case suggestionNotFound(bookmarkID: UUID, index: Int)
    case suggestionKeyNotFound(bookmarkID: UUID, key: String)
    case createFailed(bookmarkID: UUID)
    case linkFailed(String)

    var errorDescription: String? {
        switch self {
        case .bookmarkNotFound(let id):
            return "No bookmark found with id \(id.uuidString)"
        case .suggestionNotFound(let bookmarkID, let index):
            return "No date suggestion \(index) found for bookmark \(bookmarkID.uuidString)"
        case .suggestionKeyNotFound(let bookmarkID, let key):
            return "No date suggestion key \(key) found for bookmark \(bookmarkID.uuidString)"
        case .createFailed(let bookmarkID):
            return "Failed to create approved date suggestion item for bookmark \(bookmarkID.uuidString)"
        case .linkFailed(let message):
            return "Failed to link date suggestion approval: \(message)"
        }
    }
}

@MainActor
final class CiderBookmarkDateSuggestionApprovalService {
    private let bookmarkProvider: () -> [Bookmark]
    private let dateCardProvider: () -> [DateCard]
    private let todoProvider: () -> [TodoCard]
    private let dateSuggestionProvider: (Bookmark) -> [CiderBookmarkDateSuggestion]
    private let createDateCard: (CiderBookmarkDateSuggestionApprovalDraft) -> DateCard?
    private let createTodo: (CiderBookmarkDateSuggestionTodoApprovalDraft) -> TodoCard?
    private let linkItems: (LibraryEntityRef, LibraryEntityRef) throws -> Void
    private let calendar: Calendar

    init(
        bookmarkService: VaultBookmarkService = .shared,
        dateCardStorage: DateCardStorage = .shared,
        dateSuggestionService: CiderBookmarkDateSuggestionService = CiderBookmarkDateSuggestionService(),
        itemLinkService: ItemLinkService = .shared,
        calendar: Calendar = .current
    ) {
        self.bookmarkProvider = { bookmarkService.bookmarks }
        self.dateCardProvider = { dateCardStorage.dateCards }
        self.todoProvider = { TodoCardStorage.shared.todoCards }
        self.dateSuggestionProvider = { dateSuggestionService.suggestions(for: $0) }
        self.createDateCard = { draft in
            var card = dateCardStorage.createDateCard(
                title: draft.title,
                startAt: draft.startAt,
                allDay: draft.allDay
            )
            guard dateCardStorage.dateCard(for: card.id) != nil else { return nil }
            card.details = draft.details
            card.actionURLString = draft.actionURLString
            _ = dateCardStorage.updateDateCard(card)
            _ = try? CiderRoutingDecisionService().recordCreateProvenance(
                itemID: card.id,
                source: "bookmark.date_suggestion.date_card.create",
                reviewReason: "Cider created a date card from a bookmark date suggestion and kept it in Inbox for review.",
                acceptedReason: "Cider created a date card from an approved bookmark date suggestion."
            )
            return dateCardStorage.dateCard(for: card.id) ?? card
        }
        self.createTodo = { draft in
            var todo = TodoCardStorage.shared.createTodoCard(
                title: draft.title,
                dueDate: draft.dueDate
            )
            guard TodoCardStorage.shared.todoCards.contains(where: { $0.id == todo.id }) else { return nil }
            todo.details = draft.details
            todo.actionURLString = draft.actionURLString
            _ = TodoCardStorage.shared.updateTodoCard(todo)
            _ = try? CiderRoutingDecisionService().recordCreateProvenance(
                itemID: todo.id,
                source: "bookmark.date_suggestion.todo.create",
                reviewReason: "Cider created a todo from a bookmark date suggestion and kept it in Inbox for review.",
                acceptedReason: "Cider created a todo from an approved bookmark date suggestion."
            )
            return TodoCardStorage.shared.todoCards.first(where: { $0.id == todo.id }) ?? todo
        }
        self.linkItems = { source, target in
            try itemLinkService.addLink(from: source, to: target)
        }
        self.calendar = calendar
    }

    init(
        bookmarkProvider: @escaping () -> [Bookmark],
        dateCardProvider: @escaping () -> [DateCard],
        todoProvider: @escaping () -> [TodoCard] = { [] },
        dateSuggestionProvider: @escaping (Bookmark) -> [CiderBookmarkDateSuggestion],
        createDateCard: @escaping (CiderBookmarkDateSuggestionApprovalDraft) -> DateCard?,
        createTodo: @escaping (CiderBookmarkDateSuggestionTodoApprovalDraft) -> TodoCard? = { _ in nil },
        linkItems: @escaping (LibraryEntityRef, LibraryEntityRef) throws -> Void,
        calendar: Calendar = .current
    ) {
        self.bookmarkProvider = bookmarkProvider
        self.dateCardProvider = dateCardProvider
        self.todoProvider = todoProvider
        self.dateSuggestionProvider = dateSuggestionProvider
        self.createDateCard = createDateCard
        self.createTodo = createTodo
        self.linkItems = linkItems
        self.calendar = calendar
    }

    func approve(bookmarkID: UUID, suggestionIndex: Int) throws -> CiderBookmarkDateSuggestionApprovalResult {
        guard let bookmark = bookmarkProvider().first(where: { $0.id == bookmarkID }) else {
            throw CiderBookmarkDateSuggestionApprovalError.bookmarkNotFound(bookmarkID)
        }

        let suggestions = dateSuggestionProvider(bookmark)
        guard suggestions.indices.contains(suggestionIndex) else {
            throw CiderBookmarkDateSuggestionApprovalError.suggestionNotFound(
                bookmarkID: bookmarkID,
                index: suggestionIndex
            )
        }
        let suggestion = suggestions[suggestionIndex]

        return try approve(bookmark: bookmark, suggestion: suggestion)
    }

    func approve(bookmarkID: UUID, suggestionKey: String) throws -> CiderBookmarkDateSuggestionApprovalResult {
        guard let bookmark = bookmarkProvider().first(where: { $0.id == bookmarkID }) else {
            throw CiderBookmarkDateSuggestionApprovalError.bookmarkNotFound(bookmarkID)
        }

        guard let suggestion = dateSuggestionProvider(bookmark).first(where: { $0.suggestionKey == suggestionKey }) else {
            throw CiderBookmarkDateSuggestionApprovalError.suggestionKeyNotFound(
                bookmarkID: bookmarkID,
                key: suggestionKey
            )
        }

        return try approve(bookmark: bookmark, suggestion: suggestion)
    }

    private func approve(
        bookmark: Bookmark,
        suggestion: CiderBookmarkDateSuggestion
    ) throws -> CiderBookmarkDateSuggestionApprovalResult {
        if shouldCreateTodo(for: suggestion) {
            return try approveTodoSuggestion(bookmark: bookmark, suggestion: suggestion)
        }

        return try approveDateCardSuggestion(bookmark: bookmark, suggestion: suggestion)
    }

    private func approveDateCardSuggestion(
        bookmark: Bookmark,
        suggestion: CiderBookmarkDateSuggestion
    ) throws -> CiderBookmarkDateSuggestionApprovalResult {
        if let existing = existingDateCard(for: suggestion, bookmarkID: bookmark.id) {
            return result(
                bookmark: bookmark,
                suggestion: suggestion,
                action: .reusedExistingDateCard,
                dateCard: existing
            )
        }

        let draft = CiderBookmarkDateSuggestionApprovalDraft(
            title: bookmark.title,
            details: details(for: suggestion),
            startAt: suggestion.date,
            allDay: !sourceSnippetHasExplicitTime(suggestion.sourceSnippet),
            actionURLString: bookmark.urlString
        )
        guard let created = createDateCard(draft) else {
            throw CiderBookmarkDateSuggestionApprovalError.createFailed(bookmarkID: bookmark.id)
        }

        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        let dateCardRef = LibraryEntityRef(type: .dateCard, entityID: created.id)
        do {
            try linkItems(bookmarkRef, dateCardRef)
        } catch {
            throw CiderBookmarkDateSuggestionApprovalError.linkFailed(error.localizedDescription)
        }

        let linkedCard = dateCardProvider().first(where: { $0.id == created.id }) ?? created
        return result(
            bookmark: bookmark,
            suggestion: suggestion,
            action: .createdDateCard,
            dateCard: linkedCard
        )
    }

    private func approveTodoSuggestion(
        bookmark: Bookmark,
        suggestion: CiderBookmarkDateSuggestion
    ) throws -> CiderBookmarkDateSuggestionApprovalResult {
        if let existing = existingTodo(for: suggestion, bookmarkID: bookmark.id) {
            return result(
                bookmark: bookmark,
                suggestion: suggestion,
                action: .reusedExistingTodo,
                todo: existing
            )
        }

        let draft = CiderBookmarkDateSuggestionTodoApprovalDraft(
            title: bookmark.title,
            details: details(for: suggestion),
            dueDate: suggestion.date,
            actionURLString: bookmark.urlString
        )
        guard let created = createTodo(draft) else {
            throw CiderBookmarkDateSuggestionApprovalError.createFailed(bookmarkID: bookmark.id)
        }

        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        let todoRef = LibraryEntityRef(type: .todo, entityID: created.id)
        do {
            try linkItems(bookmarkRef, todoRef)
        } catch {
            throw CiderBookmarkDateSuggestionApprovalError.linkFailed(error.localizedDescription)
        }

        let linkedTodo = todoProvider().first(where: { $0.id == created.id }) ?? created
        return result(
            bookmark: bookmark,
            suggestion: suggestion,
            action: .createdTodo,
            todo: linkedTodo
        )
    }

    private func existingDateCard(for suggestion: CiderBookmarkDateSuggestion, bookmarkID: UUID) -> DateCard? {
        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmarkID)
        return dateCardProvider()
            .filter { card in
                card.linkedEntities.contains(bookmarkRef)
                    && calendar.isDate(card.startAt, inSameDayAs: suggestion.date)
                    && card.details.localizedCaseInsensitiveContains("Date suggestion kind: \(suggestion.kind)")
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    private func existingTodo(for suggestion: CiderBookmarkDateSuggestion, bookmarkID: UUID) -> TodoCard? {
        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmarkID)
        return todoProvider()
            .filter { todo in
                todo.linkedEntities.contains(bookmarkRef)
                    && todo.dueDate.map { calendar.isDate($0, inSameDayAs: suggestion.date) } == true
                    && todo.details.localizedCaseInsensitiveContains("Date suggestion kind: \(suggestion.kind)")
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.id.uuidString < rhs.id.uuidString }
                return lhs.createdAt < rhs.createdAt
            }
            .first
    }

    private func result(
        bookmark: Bookmark,
        suggestion: CiderBookmarkDateSuggestion,
        action: CiderBookmarkDateSuggestionApprovalAction,
        dateCard: DateCard? = nil,
        todo: TodoCard? = nil
    ) -> CiderBookmarkDateSuggestionApprovalResult {
        CiderBookmarkDateSuggestionApprovalResult(
            command: "bookmark.date-suggestion.approve",
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            suggestion: suggestion,
            action: action,
            dateCard: dateCard,
            todo: todo
        )
    }

    private func shouldCreateTodo(for suggestion: CiderBookmarkDateSuggestion) -> Bool {
        switch suggestion.kind {
        case "deadline", "sale_end":
            return true
        default:
            return false
        }
    }

    private func details(for suggestion: CiderBookmarkDateSuggestion) -> String {
        [
            "Date suggestion kind: \(suggestion.kind)",
            "Confidence: \(String(format: "%.2f", suggestion.confidence))",
            "Source field: \(suggestion.sourceField)",
            "Evidence: \(suggestion.sourceSnippet)",
            "Source bookmark: \(suggestion.sourceURL)",
        ].joined(separator: "\n")
    }

    private func sourceSnippetHasExplicitTime(_ snippet: String) -> Bool {
        let pattern = #"(?i)\b(\d{1,2}:\d{2}\s*(am|pm)?|\d{1,2}\s*(am|pm))\b"#
        return snippet.range(of: pattern, options: .regularExpression) != nil
    }
}
