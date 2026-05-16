import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Bookmark Date Suggestion Service Tests")
struct CiderBookmarkDateSuggestionServiceTests {
    @Test("clear release date bookmark returns structured reminder suggestion")
    func clearReleaseDateBookmarkReturnsSuggestion() throws {
        let bookmark = Bookmark(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Forza Horizon 6 launches October 23, 2026",
            urlString: "https://example.com/forza-horizon-6",
            notes: "Official release date confirmed during the showcase."
        )

        let suggestions = CiderBookmarkDateSuggestionService().suggestions(for: bookmark)

        let suggestion = try #require(suggestions.first)
        #expect(suggestion.bookmarkID == bookmark.id)
        #expect(suggestion.kind == "release_date")
        #expect(suggestion.confidence >= 0.85)
        #expect(suggestion.sourceField == "title")
        #expect(suggestion.sourceURL == bookmark.urlString)
        #expect(suggestion.nextSafeAction == "review_date_suggestion")

        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone.current,
            from: suggestion.date
        )
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 23)
    }

    @Test("bookmark with no date returns no reminder suggestions")
    func bookmarkWithNoDateReturnsNoSuggestions() {
        let bookmark = Bookmark(
            title: "Forza Horizon 6 official trailer",
            urlString: "https://example.com/forza-horizon-6",
            notes: "Open world racing trailer and screenshots."
        )

        let suggestions = CiderBookmarkDateSuggestionService().suggestions(for: bookmark)

        #expect(suggestions.isEmpty)
    }

    @Test("dashboard date suggestion scan can be bounded for large text fields")
    func dashboardDateSuggestionScanCanBeBoundedForLargeTextFields() {
        let bookmark = Bookmark(
            title: "Conference notes",
            urlString: "https://example.com/conference",
            notes: String(repeating: "background ", count: 200)
                + "Conference event September 12, 2026"
        )
        let boundedService = CiderBookmarkDateSuggestionService(maximumFieldLength: 120)

        let results = HomeOverviewDataProvider.bookmarkDateSuggestionResults(
            from: [.bookmark(bookmark)],
            service: boundedService
        )

        #expect(results.isEmpty)
    }

    @Test("date suggestion JSON exposes agent safe fields")
    func dateSuggestionJSONExposesAgentSafeFields() throws {
        let suggestion = CiderBookmarkDateSuggestion(
            bookmarkID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            bookmarkTitle: "Tickets on sale May 30, 2026 at 10:00 AM",
            sourceURL: "https://example.com/tickets",
            kind: "presale_date",
            confidence: 0.94,
            date: Date(timeIntervalSince1970: 1_780_150_400),
            sourceField: "notes",
            sourceSnippet: "Tickets on sale May 30, 2026 at 10:00 AM",
            nextSafeAction: "review_date_suggestion"
        )

        let dict = bookmarkDateSuggestionToDict(suggestion)

        #expect(dict["bookmarkID"] as? String == "22222222-2222-2222-2222-222222222222")
        #expect(dict["bookmarkTitle"] as? String == "Tickets on sale May 30, 2026 at 10:00 AM")
        #expect(dict["sourceURL"] as? String == "https://example.com/tickets")
        #expect(dict["kind"] as? String == "presale_date")
        #expect(dict["confidence"] as? Double == 0.94)
        #expect(dict["sourceField"] as? String == "notes")
        #expect(dict["sourceSnippet"] as? String == "Tickets on sale May 30, 2026 at 10:00 AM")
        #expect(dict["nextSafeAction"] as? String == "review_date_suggestion")
        #expect(dict["date"] as? String != nil)
        #expect(dict["suggestionKey"] as? String == suggestion.suggestionKey)
        #expect((dict["suggestionKey"] as? String)?.isEmpty == false)
    }

    @Test("date suggestion key is stable for approval identity")
    func dateSuggestionKeyIsStableForApprovalIdentity() {
        let bookmarkID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let date = Date(timeIntervalSince1970: 1_780_150_400)
        let first = CiderBookmarkDateSuggestion(
            bookmarkID: bookmarkID,
            bookmarkTitle: "Tickets on sale May 30, 2026 at 10:00 AM",
            sourceURL: "https://example.com/tickets",
            kind: "presale_date",
            confidence: 0.94,
            date: date,
            sourceField: "notes",
            sourceSnippet: "Tickets on sale May 30, 2026 at 10:00 AM",
            nextSafeAction: "review_date_suggestion"
        )
        var reranked = first
        reranked.confidence = 0.71
        var changedEvidence = first
        changedEvidence.sourceSnippet = "General sale begins June 1, 2026"

        #expect(first.suggestionKey == reranked.suggestionKey)
        #expect(first.suggestionKey != changedEvidence.suggestionKey)
    }

    @Test("human date suggestion lines expose stable indices")
    @MainActor
    func humanDateSuggestionLinesExposeStableIndices() {
        let bookmarkID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let first = CiderBookmarkDateSuggestion(
            bookmarkID: bookmarkID,
            bookmarkTitle: "Tickets on sale May 30, 2026",
            sourceURL: "https://example.com/tickets",
            kind: "presale_date",
            confidence: 0.94,
            date: Date(timeIntervalSince1970: 1_780_150_400),
            sourceField: "title",
            sourceSnippet: "Tickets on sale May 30, 2026",
            nextSafeAction: "review_date_suggestion"
        )
        let second = CiderBookmarkDateSuggestion(
            bookmarkID: bookmarkID,
            bookmarkTitle: "Tickets on sale May 30, 2026",
            sourceURL: "https://example.com/tickets",
            kind: "event_date",
            confidence: 0.84,
            date: Date(timeIntervalSince1970: 1_789_171_200),
            sourceField: "notes",
            sourceSnippet: "Concert September 12, 2026",
            nextSafeAction: "review_date_suggestion"
        )
        let result = CiderBookmarkDateSuggestionResult(
            command: "bookmark.date-suggestions",
            bookmarkID: bookmarkID,
            bookmarkTitle: "Tickets on sale May 30, 2026",
            sourceURL: "https://example.com/tickets",
            suggestions: [first, second]
        )

        let lines = CiderCLI.bookmarkDateSuggestionHumanLines(result: result)

        #expect(lines.contains { $0.contains("[0] presale_date:") })
        #expect(lines.contains { $0.contains("[1] event_date:") })
        #expect(lines.contains { $0.contains("Key: \(first.suggestionKey)") })
    }
}
