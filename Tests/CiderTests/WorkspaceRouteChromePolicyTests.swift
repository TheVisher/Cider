import XCTest
@testable import Cider

final class WorkspaceRouteChromePolicyTests: XCTestCase {
    func testRouteChromeMatchesRepresentativeRoutes() {
        let folderID = UUID()
        let tagID = UUID()
        let expectations: [(WorkspaceRoute, WorkspaceRouteChrome)] = [
            (
                .home,
                WorkspaceRouteChrome(
                    title: "Home",
                    subtitle: "Command center and active work",
                    systemImage: "house",
                    showsLibraryViewOptions: false
                )
            ),
            (
                .library(.files),
                WorkspaceRouteChrome(
                    title: "Files",
                    subtitle: "Library / Files",
                    systemImage: "doc.text",
                    showsLibraryViewOptions: true
                )
            ),
            (
                .library(.folder(folderID)),
                WorkspaceRouteChrome(
                    title: "Folder",
                    subtitle: "Library / Folder",
                    systemImage: "folder",
                    showsLibraryViewOptions: true
                )
            ),
            (
                .library(.tag(tagID)),
                WorkspaceRouteChrome(
                    title: "Tag",
                    subtitle: "Library / Tag",
                    systemImage: "tag",
                    showsLibraryViewOptions: true
                )
            ),
            (
                .library(.search("cider")),
                WorkspaceRouteChrome(
                    title: "Search",
                    subtitle: "Library / Search",
                    systemImage: "magnifyingglass",
                    showsLibraryViewOptions: true
                )
            ),
            (
                .projects(.workspace(projectID: "cider", section: .board(boardID: "2afee0", milestoneCardID: nil))),
                WorkspaceRouteChrome(
                    title: "Board",
                    subtitle: "Projects / Board",
                    systemImage: "rectangle.split.3x1",
                    showsLibraryViewOptions: false
                )
            ),
            (
                .projects(.workspace(projectID: "cider", section: .qa)),
                WorkspaceRouteChrome(
                    title: "QA",
                    subtitle: "Projects / QA",
                    systemImage: "checklist.checked",
                    showsLibraryViewOptions: false
                )
            ),
            (
                .spaces(.manager),
                WorkspaceRouteChrome(
                    title: "Spaces",
                    subtitle: "Create, pin, and manage Spaces",
                    systemImage: "square.grid.2x2",
                    showsLibraryViewOptions: false
                )
            ),
            (
                .ai,
                WorkspaceRouteChrome(
                    title: "AI Assistant",
                    subtitle: "Ask questions and run agent workflows",
                    systemImage: "sparkles",
                    showsLibraryViewOptions: false
                )
            ),
        ]

        for (route, expected) in expectations {
            XCTAssertEqual(WorkspaceRouteChromePolicy.chrome(for: route), expected, "\(route)")
        }
    }
}
