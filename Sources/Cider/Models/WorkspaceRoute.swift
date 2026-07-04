import Foundation

enum WorkspaceRoute: Hashable, Codable {
    case home
    case review
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

enum WorkspaceVisibleItemScopePolicy {
    static func visibleItems(
        for scope: WorkspaceVisibleItemScope,
        items: [LibraryItemV2],
        folderID: UUID?,
        tagIDs: Set<UUID>,
        searchText: String
    ) -> [LibraryItemV2] {
        switch scope {
        case .none, .projectBoard:
            return []
        case .libraryFeed(let entityTypes, let onlyUnassigned):
            return items.filter { item in
                entityTypes.contains(item.entityType)
                    && (!onlyUnassigned || item.isInboxItem)
            }
        case .folder:
            guard let folderID else { return [] }
            return items.filter { $0.folderID == folderID }
        case .tag:
            guard !tagIDs.isEmpty else { return [] }
            return items.filter { !$0.labelIDs.isDisjoint(with: tagIDs) }
        case .search:
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return [] }
            return items.filter { matchesTextQuery(query, in: $0) }
        }
    }

    static func visibleItemIDs(
        for scope: WorkspaceVisibleItemScope,
        items: [LibraryItemV2],
        folderID: UUID?,
        tagIDs: Set<UUID>,
        searchText: String
    ) -> [String] {
        visibleItems(
            for: scope,
            items: items,
            folderID: folderID,
            tagIDs: tagIDs,
            searchText: searchText
        ).map(\.id)
    }

    private static func matchesTextQuery(_ query: String, in item: LibraryItemV2) -> Bool {
        let tokens = query.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return true }

        return tokens.allSatisfy { token in
            searchableFields(for: item).contains { $0.localizedStandardContains(token) }
        }
    }

    private static func searchableFields(for item: LibraryItemV2) -> [String] {
        switch item {
        case .bookmark(let bookmark):
            var fields = [bookmark.title, bookmark.urlString, bookmark.notes] + bookmark.tags
            if let ocrText = bookmark.ocrText { fields.append(ocrText) }
            return fields
        case .note(let note):
            return [note.title, note.content] + note.tags
        case .dateCard(let dateCard):
            return [dateCard.title, dateCard.details, dateCard.location]
        case .contact(let contact):
            return [contact.displayName, contact.relationshipLabel, contact.notes]
        case .todo(let todo):
            return [todo.title, todo.details] + todo.checklist.map(\.title)
        case .vaultFile(let file):
            var fields = [file.filename, file.displayTitle, file.notes] + file.tags
            if let ocrText = file.ocrText { fields.append(ocrText) }
            return fields
        }
    }
}

enum SidebarSearchSubmitPolicy {
    static func route(for rawQuery: String) -> WorkspaceRoute? {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return .library(.search(query))
    }
}

enum WorkspaceRouteContentKind: Equatable {
    case home
    case reviewQueue
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
        case .review:
            return WorkspaceRoutePresentation(
                sidebarDomain: .review,
                title: WorkspaceNavigationDomain.review.title,
                systemImage: WorkspaceNavigationDomain.review.systemImage,
                contentKind: .reviewQueue,
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

struct WorkspaceRouteChrome: Equatable {
    let title: String
    let subtitle: String?
    let systemImage: String
    let showsLibraryViewOptions: Bool
}

enum WorkspaceRouteChromePolicy {
    static func chrome(for route: WorkspaceRoute) -> WorkspaceRouteChrome {
        let presentation = WorkspaceRoutePresentation.presentation(for: route)
        return WorkspaceRouteChrome(
            title: presentation.title,
            subtitle: subtitle(for: route, presentation: presentation),
            systemImage: presentation.systemImage,
            showsLibraryViewOptions: presentation.showsLibraryViewOptions
        )
    }

    private static func subtitle(
        for route: WorkspaceRoute,
        presentation: WorkspaceRoutePresentation
    ) -> String? {
        switch route {
        case .home:
            return "Command center and active work"
        case .review:
            return WorkspaceNavigationDomain.review.subtitle
        case .library:
            return "Library / \(presentation.title)"
        case .projects:
            return "Projects / \(presentation.title)"
        case .spaces(.manager):
            return "Create, pin, and manage Spaces"
        case .spaces:
            return "Space"
        case .ai:
            return WorkspaceNavigationDomain.aiAssistant.subtitle
        }
    }
}

struct WorkspaceRouteIntent: Equatable {
    let route: WorkspaceRoute
    let detail: WorkspaceRouteIntentDetail?
}

enum WorkspaceRouteIntentDetail: Equatable {
    case kanbanCard(boardID: String, cardID: String)
}

enum WorkspaceRouteIntentPolicy {
    static func intent(
        forExternalTargetType targetType: String,
        targetID: String,
        boardID: String?
    ) -> WorkspaceRouteIntent {
        switch targetType {
        case "card":
            let routeBoardID = boardID ?? targetID
            return WorkspaceRouteIntent(
                route: browseAllBoardsRoute(boardID: routeBoardID),
                detail: .kanbanCard(boardID: routeBoardID, cardID: targetID)
            )
        case "board":
            return WorkspaceRouteIntent(route: browseAllBoardsRoute(boardID: targetID), detail: nil)
        default:
            return WorkspaceRouteIntent(route: .home, detail: nil)
        }
    }

    static func intent(forDashboardTarget target: HomeOverviewActionTarget) -> WorkspaceRouteIntent {
        switch target {
        case .inbox:
            return WorkspaceRouteIntent(route: .library(.inbox), detail: nil)
        case .review:
            return WorkspaceRouteIntent(route: .review, detail: nil)
        }
    }

    static func intent(
        forQuickAction action: QuickAction,
        selectedProjectID: String?,
        createdBoardID: String?
    ) -> WorkspaceRouteIntent? {
        switch action {
        case .newLibraryView:
            return WorkspaceRouteIntent(route: .library(.overview), detail: nil)
        case .newTag:
            return WorkspaceRouteIntent(route: .library(.tags), detail: nil)
        case .newKanban:
            guard let createdBoardID else { return nil }
            return WorkspaceRouteIntent(
                route: projectBoardRoute(projectID: selectedProjectID, boardID: createdBoardID),
                detail: nil
            )
        case .newBookmark, .newNote, .newEvent, .newContact, .newTodo, .newFolder, .openSettings:
            return nil
        }
    }

    static func intent(forLibraryEntityTypes entityTypes: Set<LibraryEntityType>) -> WorkspaceRouteIntent {
        if entityTypes == [.bookmark] {
            return WorkspaceRouteIntent(route: .library(.bookmarks), detail: nil)
        }
        if entityTypes == [.note] {
            return WorkspaceRouteIntent(route: .library(.notes), detail: nil)
        }
        if entityTypes == [.vaultFile] {
            return WorkspaceRouteIntent(route: .library(.files), detail: nil)
        }
        return WorkspaceRouteIntent(route: .library(.all), detail: nil)
    }

    static func projectBoardRoute(projectID: String?, boardID: String) -> WorkspaceRoute {
        if let projectID, projectID != "browse-all-boards" {
            return .projects(.workspace(projectID: projectID, section: .board(boardID: boardID, milestoneCardID: nil)))
        }
        return browseAllBoardsRoute(boardID: boardID)
    }

    private static func browseAllBoardsRoute(boardID: String) -> WorkspaceRoute {
        .projects(.browseAllBoards(section: .board(boardID: boardID, milestoneCardID: nil)))
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

struct WorkspaceRouterCompatibilityState: Equatable {
    var legacyTab: CiderTab?
    var selectedNavigationDomain: WorkspaceNavigationDomain?
    var selectedDomainRouteKind: WorkspaceDomainRouteKind
    var selectedFolderID: UUID?
    var selectedTagIDs: Set<UUID>
    var selectedProjectWorkspaceID: String?

    init(
        legacyTab: CiderTab? = nil,
        selectedNavigationDomain: WorkspaceNavigationDomain? = nil,
        selectedDomainRouteKind: WorkspaceDomainRouteKind = .overview,
        selectedFolderID: UUID? = nil,
        selectedTagIDs: Set<UUID> = [],
        selectedProjectWorkspaceID: String? = nil
    ) {
        self.legacyTab = legacyTab
        self.selectedNavigationDomain = selectedNavigationDomain
        self.selectedDomainRouteKind = selectedDomainRouteKind
        self.selectedFolderID = selectedFolderID
        self.selectedTagIDs = selectedTagIDs
        self.selectedProjectWorkspaceID = selectedProjectWorkspaceID
    }
}

struct WorkspaceRouteSidebarState: Equatable {
    var selectedNavigationDomain: WorkspaceNavigationDomain?
    var selectedDomainRouteKind: WorkspaceDomainRouteKind
    var selectedFolderID: UUID?
    var selectedTagIDs: Set<UUID>
    var selectedProjectWorkspaceID: String?

    init(
        selectedNavigationDomain: WorkspaceNavigationDomain? = nil,
        selectedDomainRouteKind: WorkspaceDomainRouteKind = .overview,
        selectedFolderID: UUID? = nil,
        selectedTagIDs: Set<UUID> = [],
        selectedProjectWorkspaceID: String? = nil
    ) {
        self.selectedNavigationDomain = selectedNavigationDomain
        self.selectedDomainRouteKind = selectedDomainRouteKind
        self.selectedFolderID = selectedFolderID
        self.selectedTagIDs = selectedTagIDs
        self.selectedProjectWorkspaceID = selectedProjectWorkspaceID
    }
}

enum WorkspaceRouteSidebarProjection {
    static func state(
        for route: WorkspaceRoute
    ) -> WorkspaceRouteSidebarState {
        switch route {
        case .home:
            return WorkspaceRouteSidebarState(selectedNavigationDomain: nil)
        case .review:
            return WorkspaceRouteSidebarState(selectedNavigationDomain: .review)
        case .library(let libraryRoute):
            return libraryState(for: libraryRoute)
        case .projects(let projectRoute):
            return projectState(for: projectRoute)
        case .spaces(let spaceRoute):
            return spaceState(for: spaceRoute)
        case .ai:
            return WorkspaceRouteSidebarState(selectedNavigationDomain: .aiAssistant)
        }
    }

    private static func libraryState(
        for route: LibraryRoute
    ) -> WorkspaceRouteSidebarState {
        switch route {
        case .overview:
            return libraryState(routeKind: .overview)
        case .inbox:
            return libraryState(routeKind: .inbox)
        case .all:
            return libraryState(routeKind: .all)
        case .bookmarks:
            return libraryState(routeKind: .bookmarks)
        case .notes:
            return libraryState(routeKind: .notes)
        case .files:
            return libraryState(routeKind: .files)
        case .folders:
            return libraryState(routeKind: .folders)
        case .folder(let folderID):
            return libraryState(routeKind: .folders, selectedFolderID: folderID)
        case .tags:
            return libraryState(routeKind: .tags)
        case .tag(let tagID):
            return libraryState(routeKind: .tags, selectedTagIDs: [tagID])
        case .search:
            return libraryState(routeKind: .all)
        }
    }

    private static func libraryState(
        routeKind: WorkspaceDomainRouteKind,
        selectedFolderID: UUID? = nil,
        selectedTagIDs: Set<UUID> = []
    ) -> WorkspaceRouteSidebarState {
        WorkspaceRouteSidebarState(
            selectedNavigationDomain: .browse,
            selectedDomainRouteKind: routeKind,
            selectedFolderID: selectedFolderID,
            selectedTagIDs: selectedTagIDs
        )
    }

    private static func projectState(for route: ProjectRoute) -> WorkspaceRouteSidebarState {
        switch route {
        case .home:
            return WorkspaceRouteSidebarState(selectedNavigationDomain: .projects)
        case .workspace(let projectID, let section):
            return projectWorkspaceState(projectID: projectID, section: section)
        case .browseAllBoards(let section):
            return projectWorkspaceState(projectID: "browse-all-boards", section: section)
        }
    }

    private static func projectWorkspaceState(
        projectID: String,
        section: ProjectSectionRoute
    ) -> WorkspaceRouteSidebarState {
        WorkspaceRouteSidebarState(
            selectedNavigationDomain: .projects,
            selectedProjectWorkspaceID: projectID
        )
    }

    private static func spaceState(for route: SpaceRoute) -> WorkspaceRouteSidebarState {
        switch route {
        case .overview:
            return WorkspaceRouteSidebarState(selectedNavigationDomain: .spaces)
        case .manager:
            return WorkspaceRouteSidebarState(selectedNavigationDomain: .spaces)
        }
    }
}

enum WorkspaceRouterCompatibility {
    static func route(from state: WorkspaceRouterCompatibilityState) -> WorkspaceRoute {
        if isGlobalHomeSelection(state) {
            return .home
        }
        if let tagID = state.selectedTagIDs.first {
            return .library(.tag(tagID))
        }
        if let folderID = state.selectedFolderID {
            return .library(.folder(folderID))
        }
        if case .domainDashboard(let domain) = state.legacyTab {
            return route(
                for: domain,
                routeKind: state.selectedDomainRouteKind,
                selectedProjectWorkspaceID: state.selectedProjectWorkspaceID
            )
        }
        if let tabRoute = state.legacyTab.flatMap(route(from:)) {
            return tabRoute
        }
        return route(
            for: state.selectedNavigationDomain,
            routeKind: state.selectedDomainRouteKind,
            selectedProjectWorkspaceID: state.selectedProjectWorkspaceID
        )
    }

    private static func isGlobalHomeSelection(_ state: WorkspaceRouterCompatibilityState) -> Bool {
        if case .domainDashboard(.mainDashboard) = state.legacyTab {
            return true
        }
        return state.legacyTab == nil && state.selectedNavigationDomain == nil
    }

    private static func route(from tab: CiderTab) -> WorkspaceRoute? {
        switch tab {
        case .search(_, let query):
            return .library(.search(query))
        case .tag:
            return .library(.tags)
        case .domainDashboard(let domain):
            return route(for: domain, routeKind: .overview, selectedProjectWorkspaceID: nil)
        case .projectOverview(let projectID, _):
            return projectRoute(projectID: projectID, section: .overview)
        case .projectInbox(let projectID, _):
            return projectRoute(projectID: projectID, section: .inbox)
        case .projectBoard(let projectID, let boardID, _):
            return projectRoute(projectID: projectID, section: .board(boardID: boardID, milestoneCardID: nil))
        case .projectSurface(let projectID, let surface, _):
            return projectRoute(projectID: projectID, section: section(for: surface))
        case .projectReferences(let projectID, _):
            return projectRoute(projectID: projectID, section: .assets)
        case .spaceOverview(let spaceID, _):
            return .spaces(.overview(spaceID: spaceID))
        case .spacesManager:
            return .spaces(.manager)
        case .aiAssistant:
            return .ai
        }
    }

    private static func route(
        for domain: WorkspaceNavigationDomain?,
        routeKind: WorkspaceDomainRouteKind,
        selectedProjectWorkspaceID: String?
    ) -> WorkspaceRoute {
        guard let domain else { return .home }
        switch domain {
        case .mainDashboard:
            return .home
        case .browse:
            return .library(libraryRoute(for: routeKind))
        case .projects:
            return projectRoute(projectID: selectedProjectWorkspaceID, section: .overview)
        case .spaces:
            return .spaces(.manager)
        case .review:
            return .review
        case .aiAssistant:
            return .ai
        case .bookmarks:
            return .library(.bookmarks)
        case .notes:
            return .library(.notes)
        case .files:
            return .library(.files)
        case .tasksEvents, .people, .media:
            return .library(.overview)
        }
    }

    private static func libraryRoute(for routeKind: WorkspaceDomainRouteKind) -> LibraryRoute {
        switch routeKind {
        case .overview, .recent, .chats:
            return .overview
        case .inbox:
            return .inbox
        case .all:
            return .all
        case .bookmarks:
            return .bookmarks
        case .notes:
            return .notes
        case .files:
            return .files
        case .folders:
            return .folders
        case .tags:
            return .tags
        }
    }

    private static func projectRoute(
        projectID: String?,
        section: ProjectSectionRoute
    ) -> WorkspaceRoute {
        guard let projectID else { return .projects(.home) }
        if projectID == "browse-all-boards" {
            return .projects(.browseAllBoards(section: section))
        }
        return .projects(.workspace(projectID: projectID, section: section))
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

struct WorkspaceRouter: Equatable {
    private(set) var currentRoute: WorkspaceRoute
    private(set) var companionState: WorkspaceRouteCompanionState

    var presentation: WorkspaceRoutePresentation {
        WorkspaceRoutePresentation.presentation(for: currentRoute)
    }

    init(
        currentRoute: WorkspaceRoute = .home,
        companionState: WorkspaceRouteCompanionState = WorkspaceRouteCompanionState()
    ) {
        self.currentRoute = currentRoute
        self.companionState = companionState
    }

    mutating func navigate(to route: WorkspaceRoute) {
        companionState = WorkspaceRouteTransitionPolicy.state(
            afterNavigatingFrom: currentRoute,
            to: route,
            current: companionState
        )
        currentRoute = route
    }
}
