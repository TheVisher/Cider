import XCTest
@testable import Cider

final class ProjectWorkspaceModelTests: XCTestCase {
    func testDefaultCatalogBuildsCiderProjectFamilyFromKnownBoards() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web"),
            KanbanBoard(id: "2d3f69", name: "Cider iOS"),
            KanbanBoard(id: "d4e5f6", name: "Cider Bugs")
        ]

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: boards)

        XCTAssertEqual(catalog.home.id, "projects-home")
        XCTAssertEqual(catalog.activeProjects.map(\.id), ["cider", "cider-web", "cider-ios"])
        XCTAssertEqual(catalog.activeProjects.first?.title, "Cider")
        XCTAssertEqual(catalog.activeProjects.first?.boardIDs, ["2afee0", "08c899", "2d3f69"])
        XCTAssertEqual(catalog.activeProjects.first?.referenceSearchTerms, ["cider"])
        XCTAssertEqual(catalog.browseAllBoards.id, "browse-all-boards")
    }

    func testDefaultCatalogOmitsActiveProjectEntriesWithoutMatchingBoards() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "personal", name: "Personal Admin")
        ])

        XCTAssertTrue(catalog.activeProjects.isEmpty)
        XCTAssertEqual(catalog.browseAllBoards.title, "Browse All Boards")
    }

    func testCatalogFindsProjectByIDAcrossHomeActiveAndBrowseEntries() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "2afee0", name: "Cider")
        ])

        XCTAssertEqual(catalog.workspace(id: "projects-home")?.kind, .home)
        XCTAssertEqual(catalog.workspace(id: "cider")?.kind, .project)
        XCTAssertEqual(catalog.workspace(id: "browse-all-boards")?.kind, .browseAllBoards)
        XCTAssertNil(catalog.workspace(id: "missing"))
    }

    func testSidebarSectionsSeparateHomeActiveProjectsAndBrowseEscapeHatch() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web")
        ])

        let sections = ProjectWorkspaceSidebarModel.sections(for: catalog)

        XCTAssertEqual(sections.map(\.title), ["Projects", "Active Projects", "Browse"])
        XCTAssertEqual(sections[0].entries.map(\.id), ["projects-home"])
        XCTAssertEqual(sections[1].entries.map(\.id), ["cider", "cider-web"])
        XCTAssertEqual(sections[2].entries.map(\.id), ["browse-all-boards"])
    }
}
