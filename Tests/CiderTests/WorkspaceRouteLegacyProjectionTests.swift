import XCTest
@testable import Cider

final class WorkspaceRouteLegacyProjectionTests: XCTestCase {
    func testLibraryRoutesProjectToLegacyShellState() {
        let folderID = UUID()
        let tagID = UUID()
        let searchTabID = UUID()

        let expectations: [(WorkspaceRoute, WorkspaceRouteLegacyNavigationState)] = [
            (
                .library(.files),
                WorkspaceRouteLegacyNavigationState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .files,
                    selectedTab: .domainDashboard(.browse)
                )
            ),
            (
                .library(.inbox),
                WorkspaceRouteLegacyNavigationState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .inbox,
                    selectedTab: .domainDashboard(.browse)
                )
            ),
            (
                .library(.folder(folderID)),
                WorkspaceRouteLegacyNavigationState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .folders,
                    selectedFolderID: folderID,
                    selectedTab: .domainDashboard(.browse)
                )
            ),
            (
                .library(.tag(tagID)),
                WorkspaceRouteLegacyNavigationState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .tags,
                    selectedTagIDs: [tagID],
                    selectedTab: .domainDashboard(.browse)
                )
            ),
            (
                .library(.search("cider")),
                WorkspaceRouteLegacyNavigationState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .all,
                    selectedTab: .search(id: searchTabID, query: "cider")
                )
            ),
        ]

        for (route, expected) in expectations {
            XCTAssertEqual(
                WorkspaceRouteLegacyProjection.state(for: route, searchTabID: searchTabID),
                expected,
                "\(route)"
            )
        }
    }
}
