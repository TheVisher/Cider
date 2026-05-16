import XCTest
@testable import Cider

final class ProjectBoardRegistrationServiceTests: XCTestCase {
    @MainActor
    func testRegisterBoardForProjectCreatesOneKanbanViewAndProjectAssociation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cider-project-board-registration-\(UUID().uuidString)", isDirectory: true)
        let savedViewURL = tempDir.appendingPathComponent("_cider_saved_views.json")
        let suiteName = "ProjectBoardRegistrationServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            defaults.removePersistentDomain(forName: suiteName)
        }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let savedViewStorage = SavedViewStorage(storageFileURL: savedViewURL)
        let associationStore = ProjectWorkspaceAssociationStore(defaults: defaults)
        let board = KanbanBoard(id: "roadmap-v1", name: "Second-Brain Roadmap v1")

        let first = ProjectBoardRegistrationService.register(
            board: board,
            projectID: "Cider",
            savedViewStorage: savedViewStorage,
            associationStore: associationStore
        )
        let second = ProjectBoardRegistrationService.register(
            board: board,
            projectID: "cider",
            savedViewStorage: savedViewStorage,
            associationStore: associationStore
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(savedViewStorage.savedViews.count, 1)
        XCTAssertEqual(savedViewStorage.tabOrder, [first.id])
        XCTAssertEqual(savedViewStorage.savedViews.first?.name, board.name)
        XCTAssertEqual(savedViewStorage.savedViews.first?.kind, .kanban(boardID: board.id))
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
