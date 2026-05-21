import XCTest
@testable import Cider

final class LibraryFeedPresentationPolicyTests: XCTestCase {
    func testLibraryFeedsDoNotShowComingUpStrip() {
        for surface in LibraryFeedSurface.allCases {
            XCTAssertFalse(
                LibraryFeedPresentationPolicy.showsComingUpSection(on: surface),
                "\(surface) should leave upcoming items to the Home dashboard"
            )
        }
    }
}
