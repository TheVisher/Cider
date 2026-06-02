import Foundation

enum WorkspaceRoute: Hashable, Codable {
    case home
    case library(LibraryRoute)
    case projects(ProjectRoute)
    case spaces(SpaceRoute)
    case ai
}

enum LibraryRoute: Hashable, Codable {
    case overview
    case inbox
    case all
    case bookmarks
    case notes
    case files
    case folders
    case folder(UUID)
    case tags
    case tag(UUID)
    case search(String)
}

enum ProjectRoute: Hashable, Codable {
    case home
    case workspace(projectID: String, section: ProjectSectionRoute)
    case browseAllBoards(section: ProjectSectionRoute)
}

enum ProjectSectionRoute: Hashable, Codable {
    case overview
    case inbox
    case board(boardID: String, milestoneCardID: String?)
    case milestones
    case docs
    case decisions
    case assets
    case qa
    case plans
}

enum SpaceRoute: Hashable, Codable {
    case overview(spaceID: String)
    case manager
}

enum WorkspaceVisibleItemScope: Equatable {
    case none
    case libraryFeed(entityTypes: Set<LibraryEntityType>, onlyUnassigned: Bool)
    case folder
    case tag
    case search
    case projectBoard(boardID: String)
}

enum WorkspaceRouteContentKind: Equatable {
    case home
    case libraryDashboard
    case libraryFeed(entityTypes: Set<LibraryEntityType>, onlyUnassigned: Bool)
    case folder
    case tag
    case search
    case projectsHome
    case projectOverview(projectID: String)
    case projectInbox(projectID: String)
    case projectBoard(boardID: String, milestoneCardID: String?)
    case projectSurface(projectID: String, surface: ProjectWorkspaceSurface)
    case spacesOverview(spaceID: String)
    case spacesManager
    case aiAssistant
}

struct WorkspaceRoutePresentation: Equatable {
    let sidebarDomain: WorkspaceNavigationDomain?
    let contentKind: WorkspaceRouteContentKind
    let visibleItemScope: WorkspaceVisibleItemScope
    let showsLibraryViewOptions: Bool

    static func presentation(for route: WorkspaceRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .home:
            return WorkspaceRoutePresentation(
                sidebarDomain: nil,
                contentKind: .home,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .library(let libraryRoute):
            return libraryPresentation(for: libraryRoute)
        case .projects(let projectRoute):
            return projectPresentation(for: projectRoute)
        case .spaces(let spaceRoute):
            return spacePresentation(for: spaceRoute)
        case .ai:
            return WorkspaceRoutePresentation(
                sidebarDomain: .aiAssistant,
                contentKind: .aiAssistant,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        }
    }

    private static func libraryPresentation(for route: LibraryRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .overview:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                contentKind: .libraryDashboard,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .inbox:
            return libraryFeedPresentation(entityTypes: LibraryEntityType.activeCases, onlyUnassigned: true)
        case .all:
            return libraryFeedPresentation(entityTypes: LibraryEntityType.activeCases, onlyUnassigned: false)
        case .bookmarks:
            return libraryFeedPresentation(entityTypes: [.bookmark], onlyUnassigned: false)
        case .notes:
            return libraryFeedPresentation(entityTypes: [.note], onlyUnassigned: false)
        case .files:
            return libraryFeedPresentation(entityTypes: [.vaultFile], onlyUnassigned: false)
        case .folders:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                contentKind: .folder,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .folder:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                contentKind: .folder,
                visibleItemScope: .folder,
                showsLibraryViewOptions: true
            )
        case .tags:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                contentKind: .tag,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .tag:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                contentKind: .tag,
                visibleItemScope: .tag,
                showsLibraryViewOptions: true
            )
        case .search:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                contentKind: .search,
                visibleItemScope: .search,
                showsLibraryViewOptions: true
            )
        }
    }

    private static func libraryFeedPresentation(
        entityTypes: Set<LibraryEntityType>,
        onlyUnassigned: Bool
    ) -> WorkspaceRoutePresentation {
        WorkspaceRoutePresentation(
            sidebarDomain: .browse,
            contentKind: .libraryFeed(entityTypes: entityTypes, onlyUnassigned: onlyUnassigned),
            visibleItemScope: .libraryFeed(entityTypes: entityTypes, onlyUnassigned: onlyUnassigned),
            showsLibraryViewOptions: true
        )
    }

    private static func projectPresentation(for route: ProjectRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .home:
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                contentKind: .projectsHome,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .workspace(let projectID, let section):
            return projectSectionPresentation(projectID: projectID, section: section)
        case .browseAllBoards(let section):
            return projectSectionPresentation(projectID: "browse-all-boards", section: section)
        }
    }

    private static func projectSectionPresentation(
        projectID: String,
        section: ProjectSectionRoute
    ) -> WorkspaceRoutePresentation {
        switch section {
        case .overview:
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                contentKind: .projectOverview(projectID: projectID),
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .inbox:
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                contentKind: .projectInbox(projectID: projectID),
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .board(let boardID, let milestoneCardID):
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                contentKind: .projectBoard(boardID: boardID, milestoneCardID: milestoneCardID),
                visibleItemScope: .projectBoard(boardID: boardID),
                showsLibraryViewOptions: false
            )
        case .milestones:
            return projectSurfacePresentation(projectID: projectID, surface: .milestones)
        case .docs:
            return projectSurfacePresentation(projectID: projectID, surface: .notes)
        case .decisions:
            return projectSurfacePresentation(projectID: projectID, surface: .decisions)
        case .assets:
            return projectSurfacePresentation(projectID: projectID, surface: .assets)
        case .qa:
            return projectSurfacePresentation(projectID: projectID, surface: .qaAudits)
        case .plans:
            return projectSurfacePresentation(projectID: projectID, surface: .plansHandoffs)
        }
    }

    private static func projectSurfacePresentation(
        projectID: String,
        surface: ProjectWorkspaceSurface
    ) -> WorkspaceRoutePresentation {
        WorkspaceRoutePresentation(
            sidebarDomain: .projects,
            contentKind: .projectSurface(projectID: projectID, surface: surface),
            visibleItemScope: .none,
            showsLibraryViewOptions: false
        )
    }

    private static func spacePresentation(for route: SpaceRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .overview(let spaceID):
            return WorkspaceRoutePresentation(
                sidebarDomain: .spaces,
                contentKind: .spacesOverview(spaceID: spaceID),
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .manager:
            return WorkspaceRoutePresentation(
                sidebarDomain: .spaces,
                contentKind: .spacesManager,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        }
    }
}

struct WorkspaceRouteCompanionState: Equatable {
    var selectedFolderID: UUID?
    var selectedTagIDs: Set<UUID>
    var selectedItemIDs: Set<String>
    var focusedItemID: String?
    var selectionAnchorID: String?
    var sidebarSearchText: String
    var debouncedSearchText: String
    var hasOpenDetail: Bool
    var hasAIAssistantContext: Bool
    var displayMode: LibraryDisplayMode
    var cardSizeScale: Double
    var projectBoardInspectorVisible: Bool

    init(
        selectedFolderID: UUID? = nil,
        selectedTagIDs: Set<UUID> = [],
        selectedItemIDs: Set<String> = [],
        focusedItemID: String? = nil,
        selectionAnchorID: String? = nil,
        sidebarSearchText: String = "",
        debouncedSearchText: String = "",
        hasOpenDetail: Bool = false,
        hasAIAssistantContext: Bool = false,
        displayMode: LibraryDisplayMode = .masonry,
        cardSizeScale: Double = 1,
        projectBoardInspectorVisible: Bool = false
    ) {
        self.selectedFolderID = selectedFolderID
        self.selectedTagIDs = selectedTagIDs
        self.selectedItemIDs = selectedItemIDs
        self.focusedItemID = focusedItemID
        self.selectionAnchorID = selectionAnchorID
        self.sidebarSearchText = sidebarSearchText
        self.debouncedSearchText = debouncedSearchText
        self.hasOpenDetail = hasOpenDetail
        self.hasAIAssistantContext = hasAIAssistantContext
        self.displayMode = displayMode
        self.cardSizeScale = cardSizeScale
        self.projectBoardInspectorVisible = projectBoardInspectorVisible
    }
}

enum WorkspaceRouteTransitionPolicy {
    static func state(
        afterNavigatingFrom oldRoute: WorkspaceRoute,
        to newRoute: WorkspaceRoute,
        current: WorkspaceRouteCompanionState
    ) -> WorkspaceRouteCompanionState {
        guard oldRoute != newRoute else { return current }

        return WorkspaceRouteCompanionState(
            selectedFolderID: nil,
            selectedTagIDs: [],
            selectedItemIDs: [],
            focusedItemID: nil,
            selectionAnchorID: nil,
            sidebarSearchText: "",
            debouncedSearchText: "",
            hasOpenDetail: false,
            hasAIAssistantContext: false,
            displayMode: current.displayMode,
            cardSizeScale: current.cardSizeScale,
            projectBoardInspectorVisible: current.projectBoardInspectorVisible
        )
    }
}
