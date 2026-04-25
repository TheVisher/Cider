import XCTest
@testable import Cider

final class QuickActionTests: XCTestCase {

    // MARK: - Identity & Enumeration

    func testAllCasesCount() {
        XCTAssertEqual(QuickAction.allCases.count, 10)
    }

    func testIDsAreUnique() {
        let ids = QuickAction.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "QuickAction IDs must be unique")
    }

    func testIDUsesRawValue() {
        // Stable identity — not the human-readable title
        XCTAssertEqual(QuickAction.newBookmark.id, "newBookmark")
        XCTAssertEqual(QuickAction.openSettings.id, "openSettings")
    }

    // MARK: - Display Properties

    func testEveryActionHasTitle() {
        for action in QuickAction.allCases {
            XCTAssertFalse(action.title.isEmpty, "\(action) has empty title")
        }
    }

    func testEveryActionHasIcon() {
        for action in QuickAction.allCases {
            XCTAssertFalse(action.icon.isEmpty, "\(action) has empty icon")
        }
    }

    func testEveryActionHasKeywords() {
        for action in QuickAction.allCases {
            XCTAssertFalse(action.keywords.isEmpty, "\(action) has no keywords")
        }
    }

    // MARK: - Matching: Empty Query

    func testEmptyQueryMatchesAll() {
        for action in QuickAction.allCases {
            XCTAssertTrue(action.matches(query: ""), "\(action) should match empty query")
        }
    }

    func testWhitespaceOnlyQueryMatchesAll() {
        for action in QuickAction.allCases {
            XCTAssertTrue(action.matches(query: "   "), "\(action) should match whitespace-only query")
        }
    }

    // MARK: - Matching: Title

    func testMatchesTitleSubstring() {
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "book"))
        XCTAssertTrue(QuickAction.newNote.matches(query: "note"))
        XCTAssertTrue(QuickAction.openSettings.matches(query: "settings"))
    }

    func testMatchesTitleCaseInsensitive() {
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "BOOKMARK"))
        XCTAssertTrue(QuickAction.newNote.matches(query: "Note"))
    }

    func testMatchesFullTitle() {
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "New Bookmark"))
    }

    func testMultipleTokensAllMustMatch() {
        // "new" matches title, "book" matches title → both match
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "new book"))
        // "new" matches title, "settings" does not match title or keywords
        XCTAssertFalse(QuickAction.newBookmark.matches(query: "new settings"))
    }

    // MARK: - Matching: Keywords

    func testMatchesKeyword() {
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "capture"))
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "url"))
        XCTAssertTrue(QuickAction.newEvent.matches(query: "calendar"))
        XCTAssertTrue(QuickAction.openSettings.matches(query: "set"))
        XCTAssertTrue(QuickAction.openSettings.matches(query: "config"))
    }

    func testKeywordMatchIsCaseInsensitive() {
        XCTAssertTrue(QuickAction.newBookmark.matches(query: "CAPTURE"))
        XCTAssertTrue(QuickAction.openSettings.matches(query: "CONFIG"))
    }

    // MARK: - Matching: Non-matches

    func testNonMatchingQuery() {
        XCTAssertFalse(QuickAction.newBookmark.matches(query: "zebra"))
        XCTAssertFalse(QuickAction.openSettings.matches(query: "bookmark"))
    }

    // MARK: - Filtering: Practical Scenarios

    func testFilterNewShowsCreationActions() {
        let matches = QuickAction.allCases.filter { $0.matches(query: "new") }
        // All 9 creation actions should match; "Open Settings" should not.
        XCTAssertEqual(matches.count, 9)
        XCTAssertFalse(matches.contains(.openSettings))
    }

    func testFilterSetShowsOnlySettings() {
        let matches = QuickAction.allCases.filter { $0.matches(query: "set") }
        XCTAssertEqual(matches, [.openSettings])
    }

    func testFilterBookmarkShowsBookmarkAction() {
        let matches = QuickAction.allCases.filter { $0.matches(query: "bookmark") }
        XCTAssertTrue(matches.contains(.newBookmark))
        XCTAssertFalse(matches.contains(.newNote))
    }

    func testFilterAddMatchesAllCreationActions() {
        // "add" is a keyword on all creation actions
        let matches = QuickAction.allCases.filter { $0.matches(query: "add") }
        XCTAssertEqual(matches.count, 9)
        XCTAssertFalse(matches.contains(.openSettings))
    }

    func testGarbageQueryMatchesNothing() {
        let matches = QuickAction.allCases.filter { $0.matches(query: "xyzzy123") }
        XCTAssertTrue(matches.isEmpty)
    }
}
