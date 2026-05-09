import Foundation

enum ProjectWorkspaceKind: String, Codable, Hashable {
    case home
    case project
    case browseAllBoards
}

struct ProjectWorkspace: Identifiable, Codable, Hashable {
    let id: String
    var kind: ProjectWorkspaceKind
    var title: String
    var subtitle: String
    var boardIDs: [String]
    var referenceSearchTerms: [String]

    var systemImage: String {
        switch kind {
        case .home: "house"
        case .project: "shippingbox"
        case .browseAllBoards: "square.grid.2x2"
        }
    }
}

struct ProjectWorkspaceBoardAssociations: Codable, Equatable {
    var includedBoardIDsByProjectID: [String: Set<String>] = [:]
    var excludedBoardIDsByProjectID: [String: Set<String>] = [:]

    static let empty = ProjectWorkspaceBoardAssociations()

    init(
        includedBoardIDsByProjectID: [String: Set<String>] = [:],
        excludedBoardIDsByProjectID: [String: Set<String>] = [:]
    ) {
        self.includedBoardIDsByProjectID = includedBoardIDsByProjectID
        self.excludedBoardIDsByProjectID = excludedBoardIDsByProjectID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        includedBoardIDsByProjectID = try container.decodeIfPresent(
            [String: Set<String>].self,
            forKey: .includedBoardIDsByProjectID
        ) ?? [:]
        excludedBoardIDsByProjectID = try container.decodeIfPresent(
            [String: Set<String>].self,
            forKey: .excludedBoardIDsByProjectID
        ) ?? [:]
    }

    func includes(boardID: String, inProjectID projectID: String) -> Bool {
        includedBoardIDsByProjectID[projectID, default: []].contains(boardID)
    }

    func excludes(boardID: String, fromProjectID projectID: String) -> Bool {
        excludedBoardIDsByProjectID[projectID, default: []].contains(boardID)
    }

    mutating func include(boardID: String, inProjectID projectID: String) {
        includedBoardIDsByProjectID[projectID, default: []].insert(boardID)
        excludedBoardIDsByProjectID[projectID, default: []].remove(boardID)
    }

    mutating func exclude(boardID: String, fromProjectID projectID: String) {
        excludedBoardIDsByProjectID[projectID, default: []].insert(boardID)
        includedBoardIDsByProjectID[projectID, default: []].remove(boardID)
    }
}

struct ProjectWorkspaceCatalog: Equatable {
    let home: ProjectWorkspace
    let activeProjects: [ProjectWorkspace]
    let browseAllBoards: ProjectWorkspace

    var allEntries: [ProjectWorkspace] {
        [home] + activeProjects + [browseAllBoards]
    }

    func workspace(id: String?) -> ProjectWorkspace? {
        guard let id else { return home }
        return allEntries.first { $0.id == id }
    }

    static func defaultCatalog(
        boards: [KanbanBoard],
        boardAssociations: ProjectWorkspaceBoardAssociations = .empty
    ) -> ProjectWorkspaceCatalog {
        let boardIDByName = Dictionary(uniqueKeysWithValues: boards.map { (normalize($0.name), $0.id) })
        let availableBoardIDs = boards.map(\.id)
        let ciderBoardIDs = associatedBoardIDs(
            projectID: "cider",
            defaultBoardIDs: ["cider"].compactMap { boardIDByName[$0] },
            availableBoardIDs: availableBoardIDs,
            boardAssociations: boardAssociations
        )

        var activeProjects: [ProjectWorkspace] = []
        if boardIDByName["cider"] != nil {
            activeProjects.append(ProjectWorkspace(
                id: "cider",
                kind: .project,
                title: "Cider",
                subtitle: "Main Cider product workspace",
                boardIDs: ciderBoardIDs,
                referenceSearchTerms: ["cider"]
            ))
        }
        if let webBoardID = boardIDByName["cider web"] {
            activeProjects.append(ProjectWorkspace(
                id: "cider-web",
                kind: .project,
                title: "Cider Web",
                subtitle: "Cider web surface and related work",
                boardIDs: associatedBoardIDs(
                    projectID: "cider-web",
                    defaultBoardIDs: [webBoardID],
                    availableBoardIDs: availableBoardIDs,
                    boardAssociations: boardAssociations
                ),
                referenceSearchTerms: ["cider web"]
            ))
        }
        if let iosBoardID = boardIDByName["cider ios"] {
            activeProjects.append(ProjectWorkspace(
                id: "cider-ios",
                kind: .project,
                title: "Cider iOS",
                subtitle: "Cider iOS app and mobile work",
                boardIDs: associatedBoardIDs(
                    projectID: "cider-ios",
                    defaultBoardIDs: [iosBoardID],
                    availableBoardIDs: availableBoardIDs,
                    boardAssociations: boardAssociations
                ),
                referenceSearchTerms: ["cider ios", "cider mobile"]
            ))
        }

        return ProjectWorkspaceCatalog(
            home: ProjectWorkspace(
                id: "projects-home",
                kind: .home,
                title: "Projects Home",
                subtitle: "Cross-project active work, testing, blockers, and next-up cards",
                boardIDs: boards.map(\.id),
                referenceSearchTerms: []
            ),
            activeProjects: activeProjects,
            browseAllBoards: ProjectWorkspace(
                id: "browse-all-boards",
                kind: .browseAllBoards,
                title: "Browse All Boards",
                subtitle: "Every Kanban board and project artifact",
                boardIDs: boards.map(\.id),
                referenceSearchTerms: []
            )
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .localizedLowercase
    }

    private static func associatedBoardIDs(
        projectID: String,
        defaultBoardIDs: [String],
        availableBoardIDs: [String],
        boardAssociations: ProjectWorkspaceBoardAssociations
    ) -> [String] {
        var result: [String] = []
        for boardID in defaultBoardIDs where availableBoardIDs.contains(boardID) {
            guard !boardAssociations.excludes(boardID: boardID, fromProjectID: projectID) else { continue }
            if !result.contains(boardID) {
                result.append(boardID)
            }
        }

        for boardID in availableBoardIDs {
            guard boardAssociations.includes(boardID: boardID, inProjectID: projectID),
                  !boardAssociations.excludes(boardID: boardID, fromProjectID: projectID),
                  !result.contains(boardID) else {
                continue
            }
            result.append(boardID)
        }
        return result
    }
}

struct ProjectWorkspaceSidebarSection: Identifiable, Equatable {
    let id: String
    let title: String
    let entries: [ProjectWorkspace]
}

enum ProjectWorkspaceSidebarModel {
    static func sections(for catalog: ProjectWorkspaceCatalog) -> [ProjectWorkspaceSidebarSection] {
        [
            ProjectWorkspaceSidebarSection(
                id: "projects",
                title: "Projects",
                entries: [catalog.home]
            ),
            ProjectWorkspaceSidebarSection(
                id: "active-projects",
                title: "Active Projects",
                entries: catalog.activeProjects
            ),
            ProjectWorkspaceSidebarSection(
                id: "browse",
                title: "Browse",
                entries: [catalog.browseAllBoards]
            )
        ].filter { !$0.entries.isEmpty }
    }
}
