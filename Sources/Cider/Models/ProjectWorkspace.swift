import Foundation

enum ProjectWorkspaceKind: String, Codable, Hashable {
    case home
    case project
    case browseAllBoards
}

enum ProjectWorkspaceSurface: String, CaseIterable, Codable, Hashable, Identifiable {
    case boards
    case notes
    case decisions
    case assets
    case qaAudits
    case plansHandoffs

    var id: String { rawValue.kebabCasedProjectSurfaceID }

    var title: String {
        switch self {
        case .boards: "Boards"
        case .notes: "Notes"
        case .decisions: "Decisions"
        case .assets: "Assets"
        case .qaAudits: "QA/Audits"
        case .plansHandoffs: "Plans/Handoffs"
        }
    }

    var tabName: String { title }

    var systemImage: String {
        switch self {
        case .boards: "rectangle.split.3x1"
        case .notes: "note.text"
        case .decisions: "checkmark.seal"
        case .assets: "photo.on.rectangle"
        case .qaAudits: "checklist.checked"
        case .plansHandoffs: "doc.text.magnifyingglass"
        }
    }

    var placeholderSubtitle: String {
        switch self {
        case .boards:
            "Kanban boards linked to this project workspace."
        case .notes:
            "Full project discussions, notes, and captured context will collect here."
        case .decisions:
            "Durable project decisions and their evidence will collect here."
        case .assets:
            "Screenshots, files, references, and design inspiration will collect here."
        case .qaAudits:
            "QA evidence, audit results, and verification trails will collect here."
        case .plansHandoffs:
            "Implementation plans, agent handoffs, and commit traces will collect here."
        }
    }
}

private extension String {
    var kebabCasedProjectSurfaceID: String {
        replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1-$2", options: .regularExpression)
            .localizedLowercase
    }
}

struct ProjectWorkspace: Identifiable, Codable, Hashable {
    let id: String
    var kind: ProjectWorkspaceKind
    var title: String
    var subtitle: String
    var boardIDs: [String]
    var referenceSearchTerms: [String]

    var surfaces: [ProjectWorkspaceSurface] {
        kind == .project ? ProjectWorkspaceSurface.allCases : []
    }

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
        let boardIDByName = boardIDByNormalizedName(boards)
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
                title: "Projects",
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

    private static func boardIDByNormalizedName(_ boards: [KanbanBoard]) -> [String: String] {
        boards.reduce(into: [:]) { result, board in
            let name = normalize(board.name)
            guard !name.isEmpty, result[name] == nil else { return }
            result[name] = board.id
        }
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

enum ProjectWorkspaceSidebarDestinationKind: Hashable {
    case overview
    case inbox
    case boardsGroup
    case board(String)
    case surface(ProjectWorkspaceSurface)
}

struct ProjectWorkspaceSidebarDestination: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let kind: ProjectWorkspaceSidebarDestinationKind
    let isSelectable: Bool
    var badge: String? = nil
}

enum ProjectWorkspaceSidebarTree {
    static func destinations(
        for workspace: ProjectWorkspace,
        boards: [KanbanBoard]
    ) -> [ProjectWorkspaceSidebarDestination] {
        guard workspace.kind == .project else { return [] }

        let boardsByID = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0) })
        let inboxCount = ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: boards)
        let boardDestinations = workspace.boardIDs.compactMap { boardID -> ProjectWorkspaceSidebarDestination? in
            guard let board = boardsByID[boardID] else { return nil }
            return ProjectWorkspaceSidebarDestination(
                id: "board-\(board.id)",
                title: board.name,
                systemImage: "square.split.2x1",
                kind: .board(board.id),
                isSelectable: true
            )
        }

        let surfaceDestinations = workspace.surfaces
            .filter { $0 != .boards }
            .map { surface in
                ProjectWorkspaceSidebarDestination(
                    id: "surface-\(surface.id)",
                    title: surface.title,
                    systemImage: surface.systemImage,
                    kind: .surface(surface),
                    isSelectable: true
                )
            }

        return [
            ProjectWorkspaceSidebarDestination(
                id: "overview",
                title: "Overview",
                systemImage: "rectangle.3.group",
                kind: .overview,
                isSelectable: true
            ),
            ProjectWorkspaceSidebarDestination(
                id: "inbox",
                title: "Inbox",
                systemImage: inboxCount > 0 ? "tray.full" : "tray",
                kind: .inbox,
                isSelectable: true,
                badge: inboxCount > 0 ? "\(inboxCount)" : nil
            ),
            ProjectWorkspaceSidebarDestination(
                id: "boards",
                title: "Boards",
                systemImage: ProjectWorkspaceSurface.boards.systemImage,
                kind: .boardsGroup,
                isSelectable: false
            )
        ] + boardDestinations + surfaceDestinations
    }
}

enum ProjectWorkspaceLocalTabKind: Hashable {
    case overview
    case inbox
    case board(String)
    case surface(ProjectWorkspaceSurface)
}

struct ProjectWorkspaceLocalTab: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    let kind: ProjectWorkspaceLocalTabKind
    let isSelected: Bool
    var badge: String? = nil
}

enum ProjectWorkspaceLocalTabs {
    static func tabs(
        for workspace: ProjectWorkspace,
        boards: [KanbanBoard],
        selectedKind: ProjectWorkspaceLocalTabKind?
    ) -> [ProjectWorkspaceLocalTab] {
        guard workspace.kind == .project else { return [] }

        let boardsByID = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, $0) })
        let inboxCount = ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: boards)
        let boardTabs = projectBoardTabs(
            for: workspace,
            boardsByID: boardsByID,
            selectedKind: selectedKind
        )

        return [
            ProjectWorkspaceLocalTab(
                id: "overview",
                title: "Overview",
                systemImage: "rectangle.3.group",
                kind: .overview,
                isSelected: selectedKind == .overview
            ),
            ProjectWorkspaceLocalTab(
                id: "inbox",
                title: "Inbox",
                systemImage: inboxCount > 0 ? "tray.full" : "tray",
                kind: .inbox,
                isSelected: selectedKind == .inbox,
                badge: inboxCount > 0 ? "\(inboxCount)" : nil
            ),
        ] + boardTabs + surfaceTabs(for: workspace, selectedKind: selectedKind)
    }

    private static func projectBoardTabs(
        for workspace: ProjectWorkspace,
        boardsByID: [String: KanbanBoard],
        selectedKind: ProjectWorkspaceLocalTabKind?
    ) -> [ProjectWorkspaceLocalTab] {
        guard let primaryBoardID = workspace.boardIDs.first else { return [] }

        var visibleBoardIDs = [primaryBoardID]
        if case let .board(selectedBoardID) = selectedKind,
           selectedBoardID != primaryBoardID,
           workspace.boardIDs.contains(selectedBoardID) {
            visibleBoardIDs.append(selectedBoardID)
        }

        return visibleBoardIDs.compactMap { boardID -> ProjectWorkspaceLocalTab? in
            guard let board = boardsByID[boardID] else { return nil }
            let kind = ProjectWorkspaceLocalTabKind.board(boardID)
            return ProjectWorkspaceLocalTab(
                id: "board-\(boardID)",
                title: boardID == primaryBoardID ? "Board" : board.name,
                systemImage: "rectangle.split.3x1",
                kind: kind,
                isSelected: selectedKind == kind,
                badge: "\(board.allCards.count)"
            )
        }
    }

    private static func surfaceTabs(
        for workspace: ProjectWorkspace,
        selectedKind: ProjectWorkspaceLocalTabKind?
    ) -> [ProjectWorkspaceLocalTab] {
        workspace.surfaces.compactMap { surface in
            guard surface != .boards else { return nil }
            let kind = ProjectWorkspaceLocalTabKind.surface(surface)
            return ProjectWorkspaceLocalTab(
                id: "surface-\(surface.id)",
                title: localTitle(for: surface),
                systemImage: surface.systemImage,
                kind: kind,
                isSelected: selectedKind == kind
            )
        }
    }

    private static func localTitle(for surface: ProjectWorkspaceSurface) -> String {
        switch surface {
        case .boards: "Board"
        case .notes: "Docs"
        case .decisions: "Decisions"
        case .assets: "Assets"
        case .qaAudits: "QA"
        case .plansHandoffs: "Plans"
        }
    }
}
