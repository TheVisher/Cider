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

    static func defaultCatalog(boards: [KanbanBoard]) -> ProjectWorkspaceCatalog {
        let boardIDByName = Dictionary(uniqueKeysWithValues: boards.map { (normalize($0.name), $0.id) })
        let ciderBoardIDs = ["cider", "cider web", "cider ios"].compactMap { boardIDByName[$0] }

        var activeProjects: [ProjectWorkspace] = []
        if !ciderBoardIDs.isEmpty {
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
                boardIDs: [webBoardID],
                referenceSearchTerms: ["cider web"]
            ))
        }
        if let iosBoardID = boardIDByName["cider ios"] {
            activeProjects.append(ProjectWorkspace(
                id: "cider-ios",
                kind: .project,
                title: "Cider iOS",
                subtitle: "Cider iOS app and mobile work",
                boardIDs: [iosBoardID],
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
