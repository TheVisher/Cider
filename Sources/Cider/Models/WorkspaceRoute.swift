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
    let title: String
    let systemImage: String
    let contentKind: WorkspaceRouteContentKind
    let visibleItemScope: WorkspaceVisibleItemScope
    let showsLibraryViewOptions: Bool
    let selectedProjectLocalTabKind: ProjectWorkspaceLocalTabKind?

    init(
        sidebarDomain: WorkspaceNavigationDomain?,
        title: String,
        systemImage: String,
        contentKind: WorkspaceRouteContentKind,
        visibleItemScope: WorkspaceVisibleItemScope,
        showsLibraryViewOptions: Bool,
        selectedProjectLocalTabKind: ProjectWorkspaceLocalTabKind? = nil
    ) {
        self.sidebarDomain = sidebarDomain
        self.title = title
        self.systemImage = systemImage
        self.contentKind = contentKind
        self.visibleItemScope = visibleItemScope
        self.showsLibraryViewOptions = showsLibraryViewOptions
        self.selectedProjectLocalTabKind = selectedProjectLocalTabKind
    }

    static func presentation(for route: WorkspaceRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .home:
            return WorkspaceRoutePresentation(
                sidebarDomain: nil,
                title: "Home",
                systemImage: WorkspaceNavigationDomain.mainDashboard.systemImage,
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
                title: WorkspaceNavigationDomain.aiAssistant.title,
                systemImage: WorkspaceNavigationDomain.aiAssistant.systemImage,
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
                title: "Library",
                systemImage: WorkspaceNavigationDomain.browse.systemImage,
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
                title: "Folders",
                systemImage: "folder",
                contentKind: .folder,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .folder:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                title: "Folder",
                systemImage: "folder",
                contentKind: .folder,
                visibleItemScope: .folder,
                showsLibraryViewOptions: true
            )
        case .tags:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                title: "Tags",
                systemImage: "tag",
                contentKind: .tag,
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .tag:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                title: "Tag",
                systemImage: "tag",
                contentKind: .tag,
                visibleItemScope: .tag,
                showsLibraryViewOptions: true
            )
        case .search:
            return WorkspaceRoutePresentation(
                sidebarDomain: .browse,
                title: "Search",
                systemImage: "magnifyingglass",
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
            title: libraryFeedTitle(entityTypes: entityTypes, onlyUnassigned: onlyUnassigned),
            systemImage: libraryFeedSystemImage(entityTypes: entityTypes, onlyUnassigned: onlyUnassigned),
            contentKind: .libraryFeed(entityTypes: entityTypes, onlyUnassigned: onlyUnassigned),
            visibleItemScope: .libraryFeed(entityTypes: entityTypes, onlyUnassigned: onlyUnassigned),
            showsLibraryViewOptions: true
        )
    }

    private static func libraryFeedTitle(
        entityTypes: Set<LibraryEntityType>,
        onlyUnassigned: Bool
    ) -> String {
        if onlyUnassigned { return "Inbox" }
        if entityTypes == [.bookmark] { return "Bookmarks" }
        if entityTypes == [.note] { return "Notes" }
        if entityTypes == [.vaultFile] { return "Files" }
        return "All"
    }

    private static func libraryFeedSystemImage(
        entityTypes: Set<LibraryEntityType>,
        onlyUnassigned: Bool
    ) -> String {
        if onlyUnassigned { return "tray" }
        if entityTypes == [.bookmark] { return "bookmark" }
        if entityTypes == [.note] { return "note.text" }
        if entityTypes == [.vaultFile] { return "doc.text" }
        return "square.grid.2x2"
    }

    private static func projectPresentation(for route: ProjectRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .home:
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                title: WorkspaceNavigationDomain.projects.title,
                systemImage: WorkspaceNavigationDomain.projects.systemImage,
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
                title: "Overview",
                systemImage: "rectangle.3.group",
                contentKind: .projectOverview(projectID: projectID),
                visibleItemScope: .none,
                showsLibraryViewOptions: false,
                selectedProjectLocalTabKind: .overview
            )
        case .inbox:
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                title: "Inbox",
                systemImage: "tray",
                contentKind: .projectInbox(projectID: projectID),
                visibleItemScope: .none,
                showsLibraryViewOptions: false,
                selectedProjectLocalTabKind: .inbox
            )
        case .board(let boardID, let milestoneCardID):
            return WorkspaceRoutePresentation(
                sidebarDomain: .projects,
                title: "Board",
                systemImage: "rectangle.split.3x1",
                contentKind: .projectBoard(boardID: boardID, milestoneCardID: milestoneCardID),
                visibleItemScope: .projectBoard(boardID: boardID),
                showsLibraryViewOptions: false,
                selectedProjectLocalTabKind: .board(boardID)
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
            title: surface.tabName,
            systemImage: surface.systemImage,
            contentKind: .projectSurface(projectID: projectID, surface: surface),
            visibleItemScope: .none,
            showsLibraryViewOptions: false,
            selectedProjectLocalTabKind: .surface(surface)
        )
    }

    private static func spacePresentation(for route: SpaceRoute) -> WorkspaceRoutePresentation {
        switch route {
        case .overview(let spaceID):
            return WorkspaceRoutePresentation(
                sidebarDomain: .spaces,
                title: "Space",
                systemImage: WorkspaceNavigationDomain.spaces.systemImage,
                contentKind: .spacesOverview(spaceID: spaceID),
                visibleItemScope: .none,
                showsLibraryViewOptions: false
            )
        case .manager:
            return WorkspaceRoutePresentation(
                sidebarDomain: .spaces,
                title: "Spaces",
                systemImage: WorkspaceNavigationDomain.spaces.systemImage,
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
