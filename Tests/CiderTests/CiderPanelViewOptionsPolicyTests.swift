import XCTest
@testable import Cider

final class CiderPanelViewOptionsPolicyTests: XCTestCase {
    func testLibraryRouteFeedsShowViewOptionsWithoutFolderSelection() {
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .domainDashboard(.browse),
            showsLibraryRouteFeed: true
        ))
    }

    func testSearchAndTagFeedsShowViewOptions() {
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .search(id: UUID(), query: "cider"),
            showsLibraryRouteFeed: false
        ))
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            hasSelectedFolder: false,
            hasSelectedTags: true,
            selectedTab: .domainDashboard(.browse),
            showsLibraryRouteFeed: false
        ))
    }

    func testHomeDashboardDoesNotShowLibraryViewOptions() {
        XCTAssertFalse(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .domainDashboard(.mainDashboard),
            showsLibraryRouteFeed: false
        ))
    }
}
