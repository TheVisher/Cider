import XCTest
@testable import Cider

final class WorkspaceRouteChromePolicyTests: XCTestCase {
    func testProjectCiderDocsRouteChromeMatchesSelectedDocsTab() {
        let route = WorkspaceRoute.projects(.workspace(projectID: "cider", section: .docs))
        let presentation = WorkspaceRoutePresentation.presentation(for: route)
        let chrome = WorkspaceRouteChromePolicy.chrome(for: route)

        XCTAssertEqual(presentation.title, "Docs")
        XCTAssertEqual(presentation.selectedProjectLocalTabKind, .surface(.notes))
        XCTAssertEqual(chrome.title, "Docs")
        XCTAssertEqual(chrome.subtitle, "Projects / Docs")
    }

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
                .library(.overview),
                WorkspaceRouteChrome(
                    title: "Library",
                    subtitle: "Complete collection",
                    systemImage: "books.vertical",
                    showsLibraryViewOptions: true
                )
            ),
            (
                .library(.all),
                WorkspaceRouteChrome(
                    title: "Library",
                    subtitle: "Complete collection",
                    systemImage: "books.vertical",
                    showsLibraryViewOptions: true
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
                .review,
                WorkspaceRouteChrome(
                    title: "Review",
                    subtitle: "Trust boundary and review queue",
                    systemImage: "checklist.checked",
                    showsLibraryViewOptions: false
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
                .rooms,
                WorkspaceRouteChrome(
                    title: "Rooms",
                    subtitle: "Durable agent threads and activity",
                    systemImage: "bubble.left.and.bubble.right",
                    showsLibraryViewOptions: false
                )
            ),
            (
                .ai,
                WorkspaceRouteChrome(
                    title: "Main Brain",
                    subtitle: "Talk with Hermes over your Cider context",
                    systemImage: "sparkles",
                    showsLibraryViewOptions: false
                )
            ),
            (
                .journal,
                WorkspaceRouteChrome(
                    title: "Journal",
                    subtitle: "Daily journal entries and narrative",
                    systemImage: "book.closed",
                    showsLibraryViewOptions: false
                )
            ),
        ]

        for (route, expected) in expectations {
            XCTAssertEqual(WorkspaceRouteChromePolicy.chrome(for: route), expected, "\(route)")
        }
    }
}
