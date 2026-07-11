import XCTest
@testable import Cider

final class WorkspaceRouteSidebarProjectionTests: XCTestCase {
    func testRoomsUsesHiddenAICompatibilitySelectionWithoutBecomingMainBrain() {
        let rooms = WorkspaceRouteSidebarProjection.state(for: .rooms)

        XCTAssertEqual(rooms.selectedNavigationDomain, .aiAssistant)
        XCTAssertEqual(WorkspaceRoutePresentation.presentation(for: .rooms).contentKind, .agentRooms)
        XCTAssertNotEqual(WorkspaceRoutePresentation.presentation(for: .rooms).contentKind, .aiAssistant)
    }

    func testLibraryRoutesProjectToSidebarState() {
        let folderID = UUID()
        let tagID = UUID()

        let expectations: [(WorkspaceRoute, WorkspaceRouteSidebarState)] = [
            (
                .library(.files),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .files
                )
            ),
            (
                .library(.inbox),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .inbox
                )
            ),
            (
                .library(.folder(folderID)),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .folders,
                    selectedFolderID: folderID
                )
            ),
            (
                .library(.tag(tagID)),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .tags,
                    selectedTagIDs: [tagID]
                )
            ),
            (
                .library(.search("cider")),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .all
                )
            ),
            (
                .spaces(.manager),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .spaces
                )
            ),
            (
                .spaces(.overview(spaceID: "media-space")),
                WorkspaceRouteSidebarState(
                    selectedNavigationDomain: .browse,
                    selectedDomainRouteKind: .spaces
                )
            ),
        ]

        for (route, expected) in expectations {
            XCTAssertEqual(
                WorkspaceRouteSidebarProjection.state(for: route),
                expected,
                "\(route)"
            )
        }
    }
}
