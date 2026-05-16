import Foundation

struct CiderBookmarkDateSuggestionApprovalDraft: Equatable {
    let title: String
    let details: String
    let startAt: Date
    let allDay: Bool
    let actionURLString: String?
}

enum CiderBookmarkDateSuggestionApprovalAction: String, Equatable {
    case createdDateCard = "created_date_card"
    case reusedExistingDateCard = "reused_existing_date_card"
}

struct CiderBookmarkDateSuggestionApprovalResult: Equatable {
    let command: String
    let bookmarkID: UUID
    let bookmarkTitle: String
    let sourceURL: String
    let suggestion: CiderBookmarkDateSuggestion
    let action: CiderBookmarkDateSuggestionApprovalAction
    let dateCard: DateCard

    var created: Bool { action == .createdDateCard }
    var reused: Bool { action == .reusedExistingDateCard }
}

enum CiderBookmarkDateSuggestionApprovalError: Error, LocalizedError, Equatable {
    case bookmarkNotFound(UUID)
    case suggestionNotFound(bookmarkID: UUID, index: Int)
    case createFailed(bookmarkID: UUID)
    case linkFailed(String)

    var errorDescription: String? {
        switch self {
        case .bookmarkNotFound(let id):
            return "No bookmark found with id \(id.uuidString)"
        case .suggestionNotFound(let bookmarkID, let index):
            return "No date suggestion \(index) found for bookmark \(bookmarkID.uuidString)"
        case .createFailed(let bookmarkID):
            return "Failed to create date card for bookmark \(bookmarkID.uuidString)"
        case .linkFailed(let message):
            return "Failed to link date suggestion approval: \(message)"
        }
    }
}

@MainActor
final class CiderBookmarkDateSuggestionApprovalService {
    private let bookmarkProvider: () -> [Bookmark]
    private let dateCardProvider: () -> [DateCard]
    private let dateSuggestionProvider: (Bookmark) -> [CiderBookmarkDateSuggestion]
    private let createDateCard: (CiderBookmarkDateSuggestionApprovalDraft) -> DateCard?
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
            return dateCardStorage.dateCard(for: card.id) ?? card
        }
        self.linkItems = { source, target in
            try itemLinkService.addLink(from: source, to: target)
        }
        self.calendar = calendar
    }

    init(
        bookmarkProvider: @escaping () -> [Bookmark],
        dateCardProvider: @escaping () -> [DateCard],
        dateSuggestionProvider: @escaping (Bookmark) -> [CiderBookmarkDateSuggestion],
        createDateCard: @escaping (CiderBookmarkDateSuggestionApprovalDraft) -> DateCard?,
        linkItems: @escaping (LibraryEntityRef, LibraryEntityRef) throws -> Void,
        calendar: Calendar = .current
    ) {
        self.bookmarkProvider = bookmarkProvider
        self.dateCardProvider = dateCardProvider
        self.dateSuggestionProvider = dateSuggestionProvider
        self.createDateCard = createDateCard
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

    private func result(
        bookmark: Bookmark,
        suggestion: CiderBookmarkDateSuggestion,
        action: CiderBookmarkDateSuggestionApprovalAction,
        dateCard: DateCard
    ) -> CiderBookmarkDateSuggestionApprovalResult {
        CiderBookmarkDateSuggestionApprovalResult(
            command: "bookmark.date-suggestion.approve",
            bookmarkID: bookmark.id,
            bookmarkTitle: bookmark.title,
            sourceURL: bookmark.urlString,
            suggestion: suggestion,
            action: action,
            dateCard: dateCard
        )
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
