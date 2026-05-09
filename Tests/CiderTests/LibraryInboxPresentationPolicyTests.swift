import XCTest
@testable import Cider

final class LibraryInboxPresentationPolicyTests: XCTestCase {
    func testInboxTriageFeedIsBounded() {
        let items = (0..<(LibraryInboxPresentationPolicy.maxVisibleItems + 10)).map { index in
            LibraryItemV2.note(Note(title: "Note \(index)", relativePath: "Inbox/Notes/Note \(index).md"))
        }

        XCTAssertEqual(
            LibraryInboxPresentationPolicy.visibleItems(items).count,
            LibraryInboxPresentationPolicy.maxVisibleItems
        )
    }

    func testInboxUsesListPresentationForTriage() {
        XCTAssertEqual(LibraryInboxPresentationPolicy.preferredDisplayMode, .list)
    }
}
