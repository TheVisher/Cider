import XCTest
@testable import Cider

final class ProjectBoardRegistrationServiceTests: XCTestCase {
    @MainActor
    func testRegisterBoardForProjectCreatesProjectAssociationWithoutRetiredViewSideEffect() throws {
        let suiteName = "ProjectBoardRegistrationServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let associationStore = ProjectWorkspaceAssociationStore(defaults: defaults)
        let board = KanbanBoard(id: "roadmap-v1", name: "Second-Brain Roadmap v1")

        let first = ProjectBoardRegistrationService.register(
            board: board,
            projectID: "Cider",
            associationStore: associationStore
        )
        let second = ProjectBoardRegistrationService.register(
            board: board,
            projectID: "cider",
            associationStore: associationStore
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertTrue(associationStore.associations.includes(boardID: board.id, inProjectID: "cider"))

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(
            boards: [
                KanbanBoard(id: "2afee0", name: "Cider"),
                board
            ],
            boardAssociations: associationStore.associations
        )

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, ["2afee0", board.id])
    }
}
