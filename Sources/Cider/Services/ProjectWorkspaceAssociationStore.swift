import Foundation

@MainActor
final class ProjectWorkspaceAssociationStore: ObservableObject {
    static let shared = ProjectWorkspaceAssociationStore()

    @Published private(set) var associations: ProjectWorkspaceBoardAssociations

    private let defaults: UserDefaults
    private let storageKey = "cider.projectWorkspace.boardAssociations"
    private let legacyExclusionsStorageKey = "cider.projectWorkspace.boardExclusions"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode(ProjectWorkspaceBoardAssociations.self, from: data) {
            associations = decoded
        } else if let data = defaults.data(forKey: legacyExclusionsStorageKey),
                  let decoded = try? JSONDecoder().decode(ProjectWorkspaceBoardAssociations.self, from: data) {
            associations = decoded
        } else {
            associations = .empty
        }
    }

    func include(boardID: String, inProjectID projectID: String) {
        guard !associations.includes(boardID: boardID, inProjectID: projectID)
                || associations.excludes(boardID: boardID, fromProjectID: projectID) else { return }
        associations.include(boardID: boardID, inProjectID: projectID)
        save()
    }

    func exclude(boardID: String, fromProjectID projectID: String) {
        guard !associations.excludes(boardID: boardID, fromProjectID: projectID)
                || associations.includes(boardID: boardID, inProjectID: projectID) else { return }
        associations.exclude(boardID: boardID, fromProjectID: projectID)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(associations) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
