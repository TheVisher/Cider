import Foundation
import XCTest
@testable import Cider

final class ProjectUpdatesPresentationTests: XCTestCase {
    private let workspace = ProjectWorkspace(
        id: "cider",
        kind: .project,
        title: "Cider",
        subtitle: "Main Cider product workspace",
        boardIDs: ["2afee0"],
        referenceSearchTerms: ["cider"]
    )

    func testProjectActivityInboxIsPresentedAsUpdatesInLocalNavigation() {
        let tabs = ProjectWorkspaceLocalTabs.tabs(
            for: workspace,
            boards: [KanbanBoard(id: "2afee0", name: "Cider")],
            selectedKind: .inbox
        )
        let updates = tabs.first(where: { $0.kind == .inbox })

        XCTAssertEqual(updates?.id, "inbox")
        XCTAssertEqual(updates?.title, "Updates")
        XCTAssertTrue(updates?.isSelected == true)

        let destinations = ProjectWorkspaceSidebarTree.destinations(
            for: workspace,
            boards: [KanbanBoard(id: "2afee0", name: "Cider")]
        )
        XCTAssertEqual(destinations.first(where: { $0.kind == .inbox })?.title, "Updates")
    }

    func testProjectInboxRoutePresentsUpdatesWithoutChangingCanonicalContent() {
        let route = WorkspaceRoute.projects(.workspace(projectID: "cider", section: .inbox))
        let presentation = WorkspaceRoutePresentation.presentation(for: route)
        let chrome = WorkspaceRouteChromePolicy.chrome(for: route)

        XCTAssertEqual(presentation.title, "Updates")
        XCTAssertEqual(presentation.contentKind, .projectInbox(projectID: "cider"))
        XCTAssertEqual(presentation.selectedProjectLocalTabKind, .inbox)
        XCTAssertEqual(chrome.title, "Updates")
        XCTAssertEqual(chrome.subtitle, "Projects / Updates")
    }

    func testProjectInboxRouteSerializationAndLegacyDeepLinksRemainCompatible() throws {
        let route = WorkspaceRoute.projects(.workspace(projectID: "cider", section: .inbox))
        let data = try JSONEncoder().encode(route)
        let encoded = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(encoded.contains("inbox"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("updates"))
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceRoute.self, from: data), route)

        for legacyName in ["Inbox", "Updates"] {
            XCTAssertEqual(
                WorkspaceRouterCompatibility.route(
                    from: WorkspaceRouterCompatibilityState(
                        legacyTab: .projectInbox(projectID: "cider", name: legacyName)
                    )
                ),
                route
            )
        }
    }
}
