import XCTest
@testable import Cider

final class CiderPanelViewOptionsPolicyTests: XCTestCase {
    func testLibraryRouteFeedsShowViewOptionsWithoutFolderSelection() {
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.files)),
            selectedNavigationDomain: .browse,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            showsLibraryRouteFeed: true
        ))
    }

    func testSearchAndTagFeedsShowViewOptions() {
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.search("cider"))),
            selectedNavigationDomain: .browse,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            showsLibraryRouteFeed: false
        ))
        XCTAssertTrue(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.tag(UUID()))),
            selectedNavigationDomain: .browse,
            hasSelectedFolder: false,
            hasSelectedTags: true,
            showsLibraryRouteFeed: false
        ))
    }

    func testHomeDashboardDoesNotShowLibraryViewOptions() {
        XCTAssertFalse(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .home),
            selectedNavigationDomain: nil,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            showsLibraryRouteFeed: false
        ))
    }

    func testStaleLibraryRoutePresentationDoesNotShowOptionsOutsideBrowse() {
        XCTAssertFalse(CiderPanelViewOptionsPolicy.showsLibraryViewOptions(
            routePresentation: WorkspaceRoutePresentation.presentation(for: .library(.files)),
            selectedNavigationDomain: .projects,
            hasSelectedFolder: false,
            hasSelectedTags: false,
            showsLibraryRouteFeed: false
        ))
    }
}
