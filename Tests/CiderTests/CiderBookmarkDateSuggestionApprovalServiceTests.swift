import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Bookmark Date Suggestion Approval Service Tests")
@MainActor
struct CiderBookmarkDateSuggestionApprovalServiceTests {
    @Test("approving a bookmark date suggestion creates and links a date card")
    func approvingSuggestionCreatesLinkedDateCard() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Forza Horizon 6 launches October 23, 2026",
            urlString: "https://example.com/forza",
            notes: "Official release date."
        )
        let suggestion = makeSuggestion(bookmark: bookmark, kind: "release_date")
        var dateCards: [DateCard] = []
        var linkedPairs: [(LibraryEntityRef, LibraryEntityRef)] = []

        let service = CiderBookmarkDateSuggestionApprovalService(
            bookmarkProvider: { [bookmark] },
            dateCardProvider: { dateCards },
            dateSuggestionProvider: { _ in [suggestion] },
            createDateCard: { draft in
                let card = DateCard(
                    title: draft.title,
                    details: draft.details,
                    startAt: draft.startAt,
                    allDay: draft.allDay,
                    actionURLString: draft.actionURLString
                )
                dateCards.append(card)
                return card
            },
            linkItems: { source, target in
                linkedPairs.append((source, target))
                guard let index = dateCards.firstIndex(where: { $0.id == target.entityID }) else { return }
                dateCards[index].linkedEntities.append(source)
            }
        )

        let result = try service.approve(bookmarkID: bookmark.id, suggestionIndex: 0)

        #expect(result.action == .createdDateCard)
        #expect(result.created)
        #expect(result.dateCard?.title == bookmark.title)
        #expect(result.dateCard?.details.contains("Date suggestion kind: release_date") == true)
        #expect(result.dateCard?.details.contains("Evidence: \(suggestion.sourceSnippet)") == true)
        #expect(result.dateCard?.actionURLString == bookmark.urlString)
        #expect(result.dateCard?.linkedEntities == [LibraryEntityRef(type: .bookmark, entityID: bookmark.id)])
        #expect(linkedPairs.count == 1)
        #expect(linkedPairs.first?.0 == LibraryEntityRef(type: .bookmark, entityID: bookmark.id))
        let dateCard = try #require(result.dateCard)
        #expect(linkedPairs.first?.1 == LibraryEntityRef(type: .dateCard, entityID: dateCard.id))
    }

    @Test("approving a bookmark date suggestion by stable key creates and links a date card")
    func approvingSuggestionByStableKeyCreatesLinkedDateCard() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            title: "Concert September 12, 2026",
            urlString: "https://example.com/concert",
            notes: "Tickets open soon."
        )
        let olderSuggestion = makeSuggestion(bookmark: bookmark, kind: "event_date")
        var targetSuggestion = makeSuggestion(bookmark: bookmark, kind: "presale_date")
        targetSuggestion.sourceSnippet = "Presale starts September 12, 2026"
        var dateCards: [DateCard] = []

        let service = CiderBookmarkDateSuggestionApprovalService(
            bookmarkProvider: { [bookmark] },
            dateCardProvider: { dateCards },
            dateSuggestionProvider: { _ in [olderSuggestion, targetSuggestion] },
            createDateCard: { draft in
                let card = DateCard(
                    title: draft.title,
                    details: draft.details,
                    startAt: draft.startAt,
                    allDay: draft.allDay,
                    actionURLString: draft.actionURLString
                )
                dateCards.append(card)
                return card
            },
            linkItems: { source, target in
                guard let index = dateCards.firstIndex(where: { $0.id == target.entityID }) else { return }
                dateCards[index].linkedEntities.append(source)
            }
        )

        let result = try service.approve(bookmarkID: bookmark.id, suggestionKey: targetSuggestion.suggestionKey)

        #expect(result.action == .createdDateCard)
        #expect(result.suggestion == targetSuggestion)
        #expect(result.dateCard?.details.contains("Date suggestion kind: presale_date") == true)
    }

    @Test("re-approving the same bookmark suggestion reuses existing linked date card")
    func approvingSuggestionReusesExistingLinkedDateCard() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Tickets on sale May 30, 2026 at 10:00 AM",
            urlString: "https://example.com/tickets"
        )
        let suggestion = makeSuggestion(bookmark: bookmark, kind: "presale_date")
        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        let existing = DateCard(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: bookmark.title,
            details: "Date suggestion kind: presale_date\nSource bookmark: \(bookmark.urlString)",
            startAt: suggestion.date,
            allDay: false,
            linkedEntities: [bookmarkRef],
            actionURLString: bookmark.urlString
        )
        var dateCards = [existing]
        var createCount = 0
        var linkCount = 0

        let service = CiderBookmarkDateSuggestionApprovalService(
            bookmarkProvider: { [bookmark] },
            dateCardProvider: { dateCards },
            dateSuggestionProvider: { _ in [suggestion] },
            createDateCard: { _ in
                createCount += 1
                let card = DateCard(title: "Unexpected", startAt: suggestion.date)
                dateCards.append(card)
                return card
            },
            linkItems: { _, _ in linkCount += 1 }
        )

        let result = try service.approve(bookmarkID: bookmark.id, suggestionIndex: 0)

        #expect(result.action == .reusedExistingDateCard)
        #expect(result.reused)
        #expect(result.dateCard?.id == existing.id)
        #expect(createCount == 0)
        #expect(linkCount == 0)
    }

    @Test("approving a deadline date suggestion creates and links a todo")
    func approvingDeadlineSuggestionCreatesLinkedTodo() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            title: "Apply by May 30, 2026",
            urlString: "https://example.com/apply"
        )
        let suggestion = makeSuggestion(bookmark: bookmark, kind: "deadline")
        var dateCards: [DateCard] = []
        var todos: [TodoCard] = []
        var linkedPairs: [(LibraryEntityRef, LibraryEntityRef)] = []

        let service = CiderBookmarkDateSuggestionApprovalService(
            bookmarkProvider: { [bookmark] },
            dateCardProvider: { dateCards },
            todoProvider: { todos },
            dateSuggestionProvider: { _ in [suggestion] },
            createDateCard: { draft in
                let card = DateCard(title: draft.title, details: draft.details, startAt: draft.startAt)
                dateCards.append(card)
                return card
            },
            createTodo: { draft in
                let todo = TodoCard(
                    title: draft.title,
                    details: draft.details,
                    dueDate: draft.dueDate,
                    actionURLString: draft.actionURLString
                )
                todos.append(todo)
                return todo
            },
            linkItems: { source, target in
                linkedPairs.append((source, target))
                guard let index = todos.firstIndex(where: { $0.id == target.entityID }) else { return }
                todos[index].linkedEntities.append(source)
            }
        )

        let result = try service.approve(bookmarkID: bookmark.id, suggestionIndex: 0)

        #expect(result.action == .createdTodo)
        #expect(result.created)
        #expect(result.createdItemType == .todo)
        #expect(result.todo?.title == bookmark.title)
        #expect(result.todo?.details.contains("Date suggestion kind: deadline") == true)
        #expect(result.todo?.dueDate == suggestion.date)
        #expect(result.todo?.actionURLString == bookmark.urlString)
        #expect(result.todo?.linkedEntities == [LibraryEntityRef(type: .bookmark, entityID: bookmark.id)])
        #expect(result.dateCard == nil)
        #expect(dateCards.isEmpty)
        #expect(linkedPairs.first?.1.type == .todo)
    }

    @Test("re-approving the same deadline suggestion reuses existing linked todo")
    func approvingDeadlineSuggestionReusesExistingLinkedTodo() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            title: "Application deadline May 30, 2026",
            urlString: "https://example.com/deadline"
        )
        let suggestion = makeSuggestion(bookmark: bookmark, kind: "deadline")
        let bookmarkRef = LibraryEntityRef(type: .bookmark, entityID: bookmark.id)
        let existing = TodoCard(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            title: bookmark.title,
            details: "Date suggestion kind: deadline\nSource bookmark: \(bookmark.urlString)",
            dueDate: suggestion.date,
            linkedEntities: [bookmarkRef],
            actionURLString: bookmark.urlString
        )
        var todos = [existing]
        var createCount = 0
        var linkCount = 0

        let service = CiderBookmarkDateSuggestionApprovalService(
            bookmarkProvider: { [bookmark] },
            dateCardProvider: { [] },
            todoProvider: { todos },
            dateSuggestionProvider: { _ in [suggestion] },
            createDateCard: { _ in DateCard(title: "Unexpected", startAt: suggestion.date) },
            createTodo: { _ in
                createCount += 1
                let todo = TodoCard(title: "Unexpected", dueDate: suggestion.date)
                todos.append(todo)
                return todo
            },
            linkItems: { _, _ in linkCount += 1 }
        )

        let result = try service.approve(bookmarkID: bookmark.id, suggestionIndex: 0)

        #expect(result.action == .reusedExistingTodo)
        #expect(result.reused)
        #expect(result.createdItemType == .todo)
        #expect(result.todo?.id == existing.id)
        #expect(createCount == 0)
        #expect(linkCount == 0)
    }

    @Test("approval JSON exposes mutation and link state")
    func approvalJSONExposesMutationAndLinkState() throws {
        let bookmarkID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let dateCardID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let suggestion = CiderBookmarkDateSuggestion(
            bookmarkID: bookmarkID,
            bookmarkTitle: "Concert September 12, 2026",
            sourceURL: "https://example.com/concert",
            kind: "event_date",
            confidence: 0.84,
            date: Date(timeIntervalSince1970: 1_789_171_200),
            sourceField: "title",
            sourceSnippet: "Concert September 12, 2026",
            nextSafeAction: "review_date_suggestion"
        )
        let dateCard = DateCard(
            id: dateCardID,
            title: suggestion.bookmarkTitle,
            startAt: suggestion.date,
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: bookmarkID)]
        )
        let result = CiderBookmarkDateSuggestionApprovalResult(
            command: "bookmark.date-suggestion.approve",
            bookmarkID: bookmarkID,
            bookmarkTitle: suggestion.bookmarkTitle,
            sourceURL: suggestion.sourceURL,
            suggestion: suggestion,
            action: .createdDateCard,
            dateCard: dateCard,
            todo: nil
        )

        let dict = bookmarkDateSuggestionApprovalResultToDict(result)

        #expect(dict["command"] as? String == "bookmark.date-suggestion.approve")
        #expect(dict["action"] as? String == "created_date_card")
        #expect(dict["created"] as? Bool == true)
        let card = try #require(dict["dateCard"] as? [String: Any])
        #expect(card["id"] as? String == dateCardID.uuidString)
        let links = try #require(dict["links"] as? [[String: Any]])
        #expect(links.count == 1)
        let firstLinkType = links[0]["type"] as? String
        #expect(firstLinkType == "bookmark")
    }

    @Test("approval JSON exposes todo mutation shape")
    func approvalJSONExposesTodoMutationShape() throws {
        let bookmarkID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let todoID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let suggestion = CiderBookmarkDateSuggestion(
            bookmarkID: bookmarkID,
            bookmarkTitle: "Apply by May 30, 2026",
            sourceURL: "https://example.com/apply",
            kind: "deadline",
            confidence: 0.84,
            date: Date(timeIntervalSince1970: 1_779_840_000),
            sourceField: "title",
            sourceSnippet: "Apply by May 30, 2026",
            nextSafeAction: "review_date_suggestion"
        )
        let todo = TodoCard(
            id: todoID,
            title: suggestion.bookmarkTitle,
            dueDate: suggestion.date,
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: bookmarkID)]
        )
        let result = CiderBookmarkDateSuggestionApprovalResult(
            command: "bookmark.date-suggestion.approve",
            bookmarkID: bookmarkID,
            bookmarkTitle: suggestion.bookmarkTitle,
            sourceURL: suggestion.sourceURL,
            suggestion: suggestion,
            action: .createdTodo,
            dateCard: nil,
            todo: todo
        )

        let dict = bookmarkDateSuggestionApprovalResultToDict(result)

        #expect(dict["createdItemType"] as? String == "todo")
        #expect(dict["action"] as? String == "created_todo")
        #expect(dict["todoID"] as? String == todoID.uuidString)
        let todoDict = try #require(dict["todo"] as? [String: Any])
        #expect(todoDict["id"] as? String == todoID.uuidString)
        #expect(dict["dateCard"] == nil)
    }

    private func makeSuggestion(bookmark: Bookmark, kind: String) -> CiderBookmarkDateSuggestion {
        CiderBookmarkDateSuggestion(
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            kind: kind,
            confidence: 0.9,
            date: Date(timeIntervalSince1970: 1_793_037_600),
            sourceField: "title",
            sourceSnippet: bookmark.title,
            nextSafeAction: "review_date_suggestion"
        )
    }
}
