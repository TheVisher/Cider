import Foundation

@MainActor
enum ProjectBoardRegistrationService {
    @discardableResult
    static func register(
        board: KanbanBoard,
        projectID: String?,
        associationStore: ProjectWorkspaceAssociationStore = .shared
    ) -> KanbanBoard {
        if let normalizedProjectID = normalizedProjectID(projectID) {
            associationStore.include(boardID: board.id, inProjectID: normalizedProjectID)
        }
        return board
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
