import XCTest
@testable import Cider

final class CiderPanelViewOptionsPolicyTests: XCTestCase {
    func testLibraryRouteFeedsShowViewOptionsWithoutFolderSelection() {
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.files)),
            selectedNavigationDomain: .browse,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .domainDashboard(.browse),
            showsLibraryRouteFeed: true
        ))
    }

    func testSearchAndTagFeedsShowViewOptions() {
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.search("cider"))),
            selectedNavigationDomain: .browse,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .search(id: UUID(), query: "cider"),
            showsLibraryRouteFeed: false
        ))
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.tag(UUID()))),
            selectedNavigationDomain: .browse,
            hasSelectedFolder: false,
            hasSelectedTags: true,
            selectedTab: .domainDashboard(.browse),
            showsLibraryRouteFeed: false
        ))
    }

    func testHomeDashboardDoesNotShowLibraryViewOptions() {
        XCTAssertFalse(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .home),
            selectedNavigationDomain: nil,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .domainDashboard(.mainDashboard),
            showsLibraryRouteFeed: false
        ))
    }

    func testStaleLibraryRoutePresentationDoesNotShowOptionsOutsideBrowse() {
        XCTAssertFalse(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.files)),
            selectedNavigationDomain: .projects,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            selectedTab: .domainDashboard(.projects),
            showsLibraryRouteFeed: false
        ))
    }
}
