import XCTest
@testable import Cider

final class WorkspaceNavigationDomainTests: XCTestCase {
    func testDomainMetadataIncludesRequiredShellDestinations() {
        let domains = WorkspaceNavigationDomain.allCases

        XCTAssertTrue(domains.contains(.mainDashboard))
        XCTAssertTrue(domains.contains(.media))
        XCTAssertTrue(domains.contains(.bookmarks))
        XCTAssertTrue(domains.contains(.projects))
        XCTAssertTrue(domains.contains(.browse))
        XCTAssertEqual(WorkspaceNavigationDomain.projects.systemImage, "square.split.2x1")
    }

    func testNavigationStateBuildsBreadcrumbAndCanReturnToGlobalDomains() {
        var state = WorkspaceNavigationState()

        XCTAssertTrue(state.isShowingGlobalDomains)
        XCTAssertEqual(state.breadcrumbPath, ["Cider"])

        state.select(.media)

        XCTAssertFalse(state.isShowingGlobalDomains)
        XCTAssertEqual(state.selectedDomain, .media)
        XCTAssertEqual(state.breadcrumbPath, ["Cider", "Media"])

        state.goBackToGlobalDomains()

        XCTAssertNil(state.selectedDomain)
        XCTAssertEqual(state.breadcrumbPath, ["Cider"])
    }
}
