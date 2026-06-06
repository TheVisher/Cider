import XCTest
@testable import Cider

final class SidebarSearchSubmitPolicyTests: XCTestCase {
    func testNonEmptySidebarSearchSubmitsToLibrarySearchRoute() {
        XCTAssertEqual(
            SidebarSearchSubmitPolicy.route(for: "  CID-447 ghost  "),
            .library(.search("CID-447 ghost"))
        )
    }

    func testEmptySidebarSearchKeepsPaletteFallback() {
        XCTAssertNil(SidebarSearchSubmitPolicy.route(for: "   "))
    }
}
