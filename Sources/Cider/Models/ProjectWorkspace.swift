import Foundation

enum ProjectWorkspaceKind: String, Codable, Hashable {
    case home
    case project
    case browseAllBoards
}

enum ProjectWorkspaceSurface: String, CaseIterable, Codable, Hashable, Identifiable {
    case boards
    case milestones
    case notes
    case decisions
    case assets
    case qaAudits
    case plansHandoffs

    var id: String { rawValue.kebabCasedProjectSurfaceID }

    var title: String {
        switch self {
        case .boards: "Boards"
        case .milestones: "Milestones"
        case .notes: "Docs"
        case .decisions: "Decisions"
        case .assets: "Assets"
        case .qaAudits: "QA"
        case .plansHandoffs: "Plans"
        }
    }

    var tabName: String { title }

    var systemImage: String {
        switch self {
        case .boards: "rectangle.split.3x1"
        case .milestones: "diamond"
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
        case .milestones:
            "Milestone goals and their child-card progress collect here."
        case .notes:
            "Full project discussions, notes, and captured context will collect here."
        case .decisions:
            "Durable project decisions and their evidence will collect here."
        case .assets:
            "Screenshots, files, references, and design inspiration will collect here."
        case .qaAudits:
            "Project audit results and QA reports collect here before they become cleanup milestones and cards."
        case .plansHandoffs:
            "Draft feature plans collect here while ideas are shaped before milestone and card extraction."
        }
    }

    var usesProjectArtifactList: Bool {
        switch self {
        case .notes, .decisions, .qaAudits, .plansHandoffs:
            true
        case .boards, .milestones, .assets:
            false
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
        let localTabs = ProjectWorkspaceLocalTabs.tabs(
            for: workspace,
            boards: boards,
            selectedKind: nil
        )

        return localTabs.map { tab in
            ProjectWorkspaceSidebarDestination(
                id: tab.id,
                title: tab.title,
                systemImage: tab.systemImage,
                kind: ProjectWorkspaceSidebarDestinationKind(kind: tab.kind),
                isSelectable: true,
                badge: tab.badge
            )
        }
    }
}

enum ProjectWorkspaceRoutePolicy {
    static func route(for workspace: ProjectWorkspace) -> WorkspaceRoute {
        switch workspace.kind {
        case .home:
            return .projects(.home)
        case .project:
            guard let primaryBoardID = workspace.boardIDs.first else {
                return .projects(.workspace(projectID: workspace.id, section: .overview))
            }
            return .projects(.workspace(
                projectID: workspace.id,
                section: .board(boardID: primaryBoardID, milestoneCardID: nil)
            ))
        case .browseAllBoards:
            return .projects(.browseAllBoards(section: .overview))
        }
    }

    static func route(
        for destination: ProjectWorkspaceSidebarDestination,
        in workspace: ProjectWorkspace
    ) -> WorkspaceRoute {
        switch destination.kind {
        case .overview:
            return route(for: .overview, in: workspace)
        case .inbox:
            return route(for: .inbox, in: workspace)
        case .boardsGroup:
            return route(for: workspace)
        case .board(let boardID):
            return route(forBoardID: boardID, milestoneCardID: nil, in: workspace)
        case .surface(let surface):
            return route(for: .surface(surface), in: workspace)
        }
    }

    static func route(
        for localTab: ProjectWorkspaceLocalTabKind,
        in workspace: ProjectWorkspace
    ) -> WorkspaceRoute {
        switch localTab {
        case .overview:
            return projectRoute(for: workspace, section: .overview)
        case .inbox:
            return projectRoute(for: workspace, section: .inbox)
        case .board(let boardID):
            return route(forBoardID: boardID, milestoneCardID: nil, in: workspace)
        case .surface(let surface):
            return projectRoute(for: workspace, section: section(for: surface))
        }
    }

    static func route(
        forBoardID boardID: String,
        milestoneCardID: String?,
        in workspace: ProjectWorkspace?
    ) -> WorkspaceRoute {
        projectRoute(
            for: workspace,
            section: .board(boardID: boardID, milestoneCardID: milestoneCardID)
        )
    }

    private static func projectRoute(
        for workspace: ProjectWorkspace?,
        section: ProjectSectionRoute
    ) -> WorkspaceRoute {
        guard let workspace, workspace.kind != .browseAllBoards else {
            return .projects(.browseAllBoards(section: section))
        }
        guard workspace.kind == .project else {
            return .projects(.home)
        }
        return .projects(.workspace(projectID: workspace.id, section: section))
    }

    private static func section(for surface: ProjectWorkspaceSurface) -> ProjectSectionRoute {
        switch surface {
        case .boards:
            return .overview
        case .milestones:
            return .milestones
        case .notes:
            return .docs
        case .decisions:
            return .decisions
        case .assets:
            return .assets
        case .qaAudits:
            return .qa
        case .plansHandoffs:
            return .plans
        }
    }
}

private extension ProjectWorkspaceSidebarDestinationKind {
    init(kind: ProjectWorkspaceLocalTabKind) {
        switch kind {
        case .overview:
            self = .overview
        case .inbox:
            self = .inbox
        case .board(let boardID):
            self = .board(boardID)
        case .surface(let surface):
            self = .surface(surface)
        }
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
        case .milestones: "Milestones"
        case .notes: "Docs"
        case .decisions: "Decisions"
        case .assets: "Assets"
        case .qaAudits: "QA"
        case .plansHandoffs: "Plans"
        }
    }
}
