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
        XCTAssertEqual(catalog.activeProjects.first?.boardIDs, ["2afee0"])
        XCTAssertEqual(catalog.activeProjects.first?.referenceSearchTerms, ["cider"])
        XCTAssertEqual(catalog.browseAllBoards.id, "browse-all-boards")
    }

    func testDefaultCatalogKeepsChildProjectBoardsOutOfCiderParentWorkspace() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web"),
            KanbanBoard(id: "2d3f69", name: "Cider iOS")
        ]

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: boards)

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, ["2afee0"])
        XCTAssertEqual(catalog.workspace(id: "cider-web")?.boardIDs, ["08c899"])
        XCTAssertEqual(catalog.workspace(id: "cider-ios")?.boardIDs, ["2d3f69"])
    }

    func testDefaultCatalogAppliesPersistedProjectBoardExclusions() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web")
        ]
        let exclusions = ProjectWorkspaceBoardAssociations(
            excludedBoardIDsByProjectID: ["cider": ["2afee0"]]
        )

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(
            boards: boards,
            boardAssociations: exclusions
        )

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, [])
        XCTAssertEqual(catalog.workspace(id: "cider-web")?.boardIDs, ["08c899"])
    }

    func testDefaultCatalogAppliesPersistedProjectBoardInclusions() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web"),
            KanbanBoard(id: "2d3f69", name: "Cider iOS")
        ]
        let associations = ProjectWorkspaceBoardAssociations(
            includedBoardIDsByProjectID: ["cider": ["08c899", "2d3f69"]]
        )

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(
            boards: boards,
            boardAssociations: associations
        )

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, ["2afee0", "08c899", "2d3f69"])
        XCTAssertEqual(catalog.workspace(id: "cider-web")?.boardIDs, ["08c899"])
        XCTAssertEqual(catalog.workspace(id: "cider-ios")?.boardIDs, ["2d3f69"])
    }

    func testProjectBoardAssociationsCanReincludeAnExcludedBoard() {
        var associations = ProjectWorkspaceBoardAssociations()

        associations.exclude(boardID: "08c899", fromProjectID: "cider")
        associations.include(boardID: "08c899", inProjectID: "cider")

        XCTAssertTrue(associations.includes(boardID: "08c899", inProjectID: "cider"))
        XCTAssertFalse(associations.excludes(boardID: "08c899", fromProjectID: "cider"))
    }

    @MainActor
    func testAssociationStorePersistsProjectBoardExclusions() {
        let suiteName = "ProjectWorkspaceAssociationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ProjectWorkspaceAssociationStore(defaults: defaults)
        store.exclude(boardID: "08c899", fromProjectID: "cider")

        let reloadedStore = ProjectWorkspaceAssociationStore(defaults: defaults)

        XCTAssertTrue(reloadedStore.associations.excludes(boardID: "08c899", fromProjectID: "cider"))
        XCTAssertFalse(reloadedStore.associations.excludes(boardID: "2d3f69", fromProjectID: "cider"))
    }

    @MainActor
    func testAssociationStorePersistsProjectBoardInclusions() {
        let suiteName = "ProjectWorkspaceAssociationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ProjectWorkspaceAssociationStore(defaults: defaults)
        store.include(boardID: "08c899", inProjectID: "cider")

        let reloadedStore = ProjectWorkspaceAssociationStore(defaults: defaults)

        XCTAssertTrue(reloadedStore.associations.includes(boardID: "08c899", inProjectID: "cider"))
        XCTAssertFalse(reloadedStore.associations.includes(boardID: "2d3f69", inProjectID: "cider"))
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
