import Foundation

@MainActor
enum ProjectBoardRegistrationService {
    @discardableResult
    static func register(
        board: KanbanBoard,
        projectID: String?,
        savedViewStorage: SavedViewStorage = .shared,
        associationStore: ProjectWorkspaceAssociationStore = .shared
    ) -> SavedView {
        let savedView = savedViewStorage.ensureKanbanView(name: board.name, boardID: board.id)
        if let normalizedProjectID = normalizedProjectID(projectID) {
            associationStore.include(boardID: board.id, inProjectID: normalizedProjectID)
        }
        return savedView
    }

    static func normalizedProjectID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "_", with: "-")
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .localizedLowercase
    }
}
