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
    }
}
