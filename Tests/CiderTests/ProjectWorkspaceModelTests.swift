import XCTest
@testable import Cider

final class ProjectWorkspaceModelTests: XCTestCase {
    func testOpeningProjectDefaultsToPrimaryBoardAndFallsBackToOverviewWithoutOne() {
        let project = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0", "a1b2c3"],
            referenceSearchTerms: ["cider"]
        )
        let projectWithoutBoard = ProjectWorkspace(
            id: "empty",
            kind: .project,
            title: "Empty",
            subtitle: "Project without a board yet",
            boardIDs: [],
            referenceSearchTerms: []
        )

        XCTAssertEqual(
            ProjectWorkspaceRoutePolicy.route(for: project),
            .projects(.workspace(
                projectID: "cider",
                section: .board(boardID: "2afee0", milestoneCardID: nil)
            ))
        )
        XCTAssertEqual(
            ProjectWorkspaceRoutePolicy.route(for: projectWithoutBoard),
            .projects(.workspace(projectID: "empty", section: .overview))
        )
    }

    func testDefaultCatalogBuildsCiderProjectFamilyFromKnownBoards() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web"),
            KanbanBoard(id: "2d3f69", name: "Cider iOS"),
            KanbanBoard(id: "d4e5f6", name: "Cider Bugs")
        ]

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: boards)

        XCTAssertEqual(catalog.home.id, "projects-home")
        XCTAssertEqual(catalog.activeProjects.map(\.id), ["cider", "cider-web", "cider-ios"])
        XCTAssertEqual(catalog.activeProjects.first?.title, "Cider")
        XCTAssertEqual(catalog.activeProjects.first?.boardIDs, ["2afee0"])
        XCTAssertEqual(catalog.activeProjects.first?.referenceSearchTerms, ["cider"])
        XCTAssertEqual(catalog.browseAllBoards.id, "browse-all-boards")
    }

    func testDefaultCatalogKeepsChildProjectBoardsOutOfCiderParentWorkspace() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web"),
            KanbanBoard(id: "2d3f69", name: "Cider iOS")
        ]

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: boards)

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, ["2afee0"])
        XCTAssertEqual(catalog.workspace(id: "cider-web")?.boardIDs, ["08c899"])
        XCTAssertEqual(catalog.workspace(id: "cider-ios")?.boardIDs, ["2d3f69"])
    }

    func testDefaultCatalogToleratesDuplicateNormalizedBoardNames() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "smoke-one", name: "Merge Smoke"),
            KanbanBoard(id: "smoke-two", name: "Merge-Smoke")
        ]

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: boards)

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, ["2afee0"])
        XCTAssertEqual(catalog.home.boardIDs, ["2afee0", "smoke-one", "smoke-two"])
        XCTAssertEqual(catalog.browseAllBoards.boardIDs, ["2afee0", "smoke-one", "smoke-two"])
    }

    func testDefaultCatalogAppliesPersistedProjectBoardExclusions() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web")
        ]
        let exclusions = ProjectWorkspaceBoardAssociations(
            excludedBoardIDsByProjectID: ["cider": ["2afee0"]]
        )

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(
            boards: boards,
            boardAssociations: exclusions
        )

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, [])
        XCTAssertEqual(catalog.workspace(id: "cider-web")?.boardIDs, ["08c899"])
    }

    func testDefaultCatalogAppliesPersistedProjectBoardInclusions() {
        let boards = [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web"),
            KanbanBoard(id: "2d3f69", name: "Cider iOS")
        ]
        let associations = ProjectWorkspaceBoardAssociations(
            includedBoardIDsByProjectID: ["cider": ["08c899", "2d3f69"]]
        )

        let catalog = ProjectWorkspaceCatalog.defaultCatalog(
            boards: boards,
            boardAssociations: associations
        )

        XCTAssertEqual(catalog.workspace(id: "cider")?.boardIDs, ["2afee0", "08c899", "2d3f69"])
        XCTAssertEqual(catalog.workspace(id: "cider-web")?.boardIDs, ["08c899"])
        XCTAssertEqual(catalog.workspace(id: "cider-ios")?.boardIDs, ["2d3f69"])
    }

    func testProjectBoardAssociationsCanReincludeAnExcludedBoard() {
        var associations = ProjectWorkspaceBoardAssociations()

        associations.exclude(boardID: "08c899", fromProjectID: "cider")
        associations.include(boardID: "08c899", inProjectID: "cider")

        XCTAssertTrue(associations.includes(boardID: "08c899", inProjectID: "cider"))
        XCTAssertFalse(associations.excludes(boardID: "08c899", fromProjectID: "cider"))
    }

    @MainActor
    func testAssociationStorePersistsProjectBoardExclusions() {
        let suiteName = "ProjectWorkspaceAssociationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ProjectWorkspaceAssociationStore(defaults: defaults)
        store.exclude(boardID: "08c899", fromProjectID: "cider")

        let reloadedStore = ProjectWorkspaceAssociationStore(defaults: defaults)

        XCTAssertTrue(reloadedStore.associations.excludes(boardID: "08c899", fromProjectID: "cider"))
        XCTAssertFalse(reloadedStore.associations.excludes(boardID: "2d3f69", fromProjectID: "cider"))
    }

    @MainActor
    func testAssociationStorePersistsProjectBoardInclusions() {
        let suiteName = "ProjectWorkspaceAssociationStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = ProjectWorkspaceAssociationStore(defaults: defaults)
        store.include(boardID: "08c899", inProjectID: "cider")

        let reloadedStore = ProjectWorkspaceAssociationStore(defaults: defaults)

        XCTAssertTrue(reloadedStore.associations.includes(boardID: "08c899", inProjectID: "cider"))
        XCTAssertFalse(reloadedStore.associations.includes(boardID: "2d3f69", inProjectID: "cider"))
    }

    func testDefaultCatalogOmitsActiveProjectEntriesWithoutMatchingBoards() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "personal", name: "Personal Admin")
        ])

        XCTAssertTrue(catalog.activeProjects.isEmpty)
        XCTAssertEqual(catalog.browseAllBoards.title, "Browse All Boards")
    }

    func testCatalogFindsProjectByIDAcrossHomeActiveAndBrowseEntries() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "2afee0", name: "Cider")
        ])

        XCTAssertEqual(catalog.workspace(id: "projects-home")?.kind, .home)
        XCTAssertEqual(catalog.workspace(id: "cider")?.kind, .project)
        XCTAssertEqual(catalog.workspace(id: "browse-all-boards")?.kind, .browseAllBoards)
        XCTAssertNil(catalog.workspace(id: "missing"))
    }

    func testSidebarSectionsSeparateHomeActiveProjectsAndBrowseEscapeHatch() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "2afee0", name: "Cider"),
            KanbanBoard(id: "08c899", name: "Cider Web")
        ])

        let sections = ProjectWorkspaceSidebarModel.sections(for: catalog)

        XCTAssertEqual(sections.map(\.title), ["Projects", "Active Projects", "Browse"])
        XCTAssertEqual(sections[0].entries.map(\.id), ["projects-home"])
        XCTAssertEqual(sections[1].entries.map(\.id), ["cider", "cider-web"])
        XCTAssertEqual(sections[2].entries.map(\.id), ["browse-all-boards"])
    }

    func testProjectWorkspaceExposesMVPContainerSurfaces() {
        let catalog = ProjectWorkspaceCatalog.defaultCatalog(boards: [
            KanbanBoard(id: "2afee0", name: "Cider")
        ])
        let cider = catalog.workspace(id: "cider")!

        XCTAssertEqual(cider.surfaces.map(\.id), [
            "boards",
            "milestones",
            "notes",
            "decisions",
            "assets",
            "qa-audits",
            "plans-handoffs"
        ])
        XCTAssertEqual(cider.surfaces.map(\.title), [
            "Boards",
            "Milestones",
            "Docs",
            "Decisions",
            "Assets",
            "QA",
            "Plans"
        ])
        XCTAssertEqual(cider.surfaces.first?.tabName, "Boards")
        XCTAssertTrue(catalog.home.surfaces.isEmpty)
    }

    func testSidebarTreeExposesRouteBackedProjectChildren() {
        let cider = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0", "3d45ca", "c0ffee"],
            referenceSearchTerms: ["cider"]
        )

        let destinations = ProjectWorkspaceSidebarTree.destinations(
            for: cider,
            boards: [
                KanbanBoard(id: "2afee0", name: "Cider"),
                KanbanBoard(id: "3d45ca", name: "Second-Brain Roadmap v1"),
                KanbanBoard(id: "c0ffee", name: "Cider Social")
            ]
        )

        XCTAssertEqual(destinations.map(\.title), [
            "Overview",
            "Updates",
            "Board",
            "Milestones",
            "Docs",
            "Decisions",
            "Assets",
            "QA",
            "Plans"
        ])
        XCTAssertEqual(destinations.map(\.kind), [
            .overview,
            .inbox,
            .board("2afee0"),
            .surface(.milestones),
            .surface(.notes),
            .surface(.decisions),
            .surface(.assets),
            .surface(.qaAudits),
            .surface(.plansHandoffs)
        ])
        XCTAssertEqual(destinations.first(where: { $0.kind == .board("2afee0") })?.badge, "0")
    }

    func testProjectWorkspaceRoutePolicyMapsWorkspaceDestinationsAndLocalTabs() {
        let cider = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let browseAllBoards = ProjectWorkspace(
            id: "browse-all-boards",
            kind: .browseAllBoards,
            title: "Browse All Boards",
            subtitle: "All boards",
            boardIDs: ["2afee0"],
            referenceSearchTerms: []
        )

        XCTAssertEqual(
            ProjectWorkspaceRoutePolicy.route(for: cider),
            .projects(.workspace(
                projectID: "cider",
                section: .board(boardID: "2afee0", milestoneCardID: nil)
            ))
        )
        XCTAssertEqual(ProjectWorkspaceRoutePolicy.route(for: browseAllBoards), .projects(.browseAllBoards(section: .overview)))
        XCTAssertEqual(
            ProjectWorkspaceRoutePolicy.route(
                for: ProjectWorkspaceSidebarDestination(
                    id: "board-2afee0",
                    title: "Board",
                    systemImage: "rectangle.split.3x1",
                    kind: .board("2afee0"),
                    isSelectable: true
                ),
                in: cider
            ),
            .projects(.workspace(projectID: "cider", section: .board(boardID: "2afee0", milestoneCardID: nil)))
        )
        XCTAssertEqual(
            ProjectWorkspaceRoutePolicy.route(for: .surface(.qaAudits), in: cider),
            .projects(.workspace(projectID: "cider", section: .qa))
        )
        XCTAssertEqual(
            ProjectWorkspaceRoutePolicy.route(
                forBoardID: "2afee0",
                milestoneCardID: "milestone-1",
                in: browseAllBoards
            ),
            .projects(.browseAllBoards(section: .board(boardID: "2afee0", milestoneCardID: "milestone-1")))
        )
    }

    func testProjectLocalTabsUseCompactProjectNavigationLabels() {
        let cider = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0", "a1b2c3"],
            referenceSearchTerms: ["cider"]
        )

        let tabs = ProjectWorkspaceLocalTabs.tabs(
            for: cider,
            boards: [
                KanbanBoard(id: "2afee0", name: "Cider"),
                KanbanBoard(id: "a1b2c3", name: "Cider Roadmap")
            ],
            selectedKind: .board("2afee0")
        )

        XCTAssertEqual(tabs.map(\.title), [
            "Overview",
            "Updates",
            "Board",
            "Milestones",
            "Docs",
            "Decisions",
            "Assets",
            "QA",
            "Plans"
        ])
        XCTAssertEqual(tabs.map(\.kind), [
            .overview,
            .inbox,
            .board("2afee0"),
            .surface(.milestones),
            .surface(.notes),
            .surface(.decisions),
            .surface(.assets),
            .surface(.qaAudits),
            .surface(.plansHandoffs)
        ])
        XCTAssertEqual(tabs.first(where: { $0.isSelected })?.title, "Board")
    }

    func testProjectLocalTabsIncludeSelectedSecondaryBoardOnlyWhenViewingIt() {
        let cider = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0", "a1b2c3"],
            referenceSearchTerms: ["cider"]
        )

        let tabs = ProjectWorkspaceLocalTabs.tabs(
            for: cider,
            boards: [
                KanbanBoard(id: "2afee0", name: "Cider"),
                KanbanBoard(id: "a1b2c3", name: "Cider Roadmap")
            ],
            selectedKind: .board("a1b2c3")
        )

        XCTAssertEqual(tabs.map(\.title), [
            "Overview",
            "Updates",
            "Board",
            "Cider Roadmap",
            "Milestones",
            "Docs",
            "Decisions",
            "Assets",
            "QA",
            "Plans"
        ])
        XCTAssertEqual(tabs.first(where: { $0.isSelected })?.title, "Cider Roadmap")
    }

    func testProjectLocalTabsMarkNonBoardDestinationsSelected() {
        let cider = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let boards = [KanbanBoard(id: "2afee0", name: "Cider")]

        let overviewTabs = ProjectWorkspaceLocalTabs.tabs(
            for: cider,
            boards: boards,
            selectedKind: .overview
        )
        let inboxTabs = ProjectWorkspaceLocalTabs.tabs(
            for: cider,
            boards: boards,
            selectedKind: .inbox
        )
        let qaTabs = ProjectWorkspaceLocalTabs.tabs(
            for: cider,
            boards: boards,
            selectedKind: .surface(.qaAudits)
        )
        let milestoneTabs = ProjectWorkspaceLocalTabs.tabs(
            for: cider,
            boards: boards,
            selectedKind: .surface(.milestones)
        )

        XCTAssertEqual(overviewTabs.first(where: { $0.isSelected })?.title, "Overview")
        XCTAssertEqual(inboxTabs.first(where: { $0.isSelected })?.title, "Updates")
        XCTAssertEqual(qaTabs.first(where: { $0.isSelected })?.title, "QA")
        XCTAssertEqual(milestoneTabs.first(where: { $0.isSelected })?.title, "Milestones")
    }

    func testProjectInboxSurfacesUnreadAgentAndQACardsOnly() {
        let afterInboxLaunch = ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(60)
        let reviewedLater = afterInboxLaunch.addingTimeInterval(60)
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let agentCard = KanbanCard(
            id: "agent",
            title: "Agent report card",
            agent: "Cody",
            created: afterInboxLaunch
        )
        let reviewedQACard = KanbanCard(
            id: "reviewed",
            title: "Already reviewed QA",
            created: afterInboxLaunch,
            reviewedAt: reviewedLater
        )
        let backlogCard = KanbanCard(
            id: "backlog",
            title: "Plain backlog idea",
            created: afterInboxLaunch
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [backlogCard]),
                KanbanColumn(id: "testing", name: "Testing", cards: [agentCard, reviewedQACard])
            ]
        )

        let entries = ProjectWorkspaceInboxProvider.entries(for: workspace, boards: [board])

        XCTAssertEqual(entries.map { $0.card.id }, ["agent"])
        XCTAssertEqual(entries.first?.badges.map(\.title), ["New", "Agent report", "Needs QA"])
        XCTAssertEqual(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: [board]), 1)
    }

    func testProjectInboxProviderRebuildDoesNotPromotePlainQueuedCards() {
        let afterInboxLaunch = ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(60)
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let reviewedAgentCard = KanbanCard(
            id: "reviewed-agent",
            title: "Opened and reviewed agent item",
            agent: "Cody",
            created: afterInboxLaunch,
            updatedAt: afterInboxLaunch,
            reviewedAt: afterInboxLaunch.addingTimeInterval(60)
        )
        let plainQueuedCard = KanbanCard(
            id: "plain-queued",
            title: "Plain queued roadmap item",
            created: afterInboxLaunch,
            updatedAt: afterInboxLaunch.addingTimeInterval(120)
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(id: "testing", name: "Testing", cards: [reviewedAgentCard]),
                KanbanColumn(id: "queued", name: "Queued", cards: [plainQueuedCard])
            ]
        )

        let entries = ProjectWorkspaceInboxProvider.entries(for: workspace, boards: [board])

        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: [board]), 0)
    }

    func testProjectInboxRecognizesAgentEvidenceWrittenToCardNotes() {
        let afterInboxLaunch = ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(60)
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let notes = """
        ## Implementation History
        - 2026-05-30 09:00 - Fixed the inbox refresh issue. (source: codex)

        ## Test Evidence
        - 2026-05-30 09:05 - swift test passed. (source: codex)
        """
        let card = KanbanCard(
            id: "notes-agent",
            title: "Agent evidence in notes",
            notes: notes,
            created: afterInboxLaunch.addingTimeInterval(-30),
            updatedAt: afterInboxLaunch
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [KanbanColumn(id: "testing", name: "Testing", cards: [card])]
        )

        let entries = ProjectWorkspaceInboxProvider.entries(for: workspace, boards: [board])

        XCTAssertEqual(entries.map { $0.card.id }, ["notes-agent"])
        XCTAssertEqual(entries.first?.badges.map(\.title), ["New", "Agent report", "Needs QA"])
        XCTAssertEqual(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: [board]), 1)
    }

    func testProjectInboxHidesLegacyActivityBeforeInboxLaunchBaseline() {
        let oldActivity = ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(-60)
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let oldAgentCard = KanbanCard(
            id: "old-agent",
            title: "Old agent report card",
            agent: "Cody",
            historyEntries: [
                KanbanCardHistoryEntry(
                    type: .implementation,
                    body: "Old implementation evidence",
                    author: "Cody",
                    createdAt: oldActivity
                )
            ],
            created: oldActivity
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [KanbanColumn(id: "testing", name: "Testing", cards: [oldAgentCard])]
        )

        XCTAssertTrue(ProjectWorkspaceInboxProvider.entries(for: workspace, boards: [board]).isEmpty)
        XCTAssertEqual(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: [board]), 0)
    }

    func testProjectInboxReentersOnlyWhenActivityIsNewerThanReviewedTimestamp() {
        let reviewedAt = ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(120)
        let newerActivity = reviewedAt.addingTimeInterval(60)
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let quietReviewedCard = KanbanCard(
            id: "quiet",
            title: "Reviewed card",
            agent: "Cody",
            created: reviewedAt.addingTimeInterval(-120),
            updatedAt: reviewedAt.addingTimeInterval(-30),
            reviewedAt: reviewedAt
        )
        let reenteredCard = KanbanCard(
            id: "reentered",
            title: "New agent follow-up",
            agent: "Cody",
            created: reviewedAt.addingTimeInterval(-120),
            updatedAt: newerActivity,
            reviewedAt: reviewedAt
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [KanbanColumn(id: "testing", name: "Testing", cards: [quietReviewedCard, reenteredCard])]
        )

        let entries = ProjectWorkspaceInboxProvider.entries(for: workspace, boards: [board])

        XCTAssertEqual(entries.map { $0.card.id }, ["reentered"])
        XCTAssertEqual(ProjectWorkspaceInboxProvider.unreadCount(for: workspace, boards: [board]), 1)
    }

    func testProjectInboxSortsByNewestUnreadActivity() {
        let base = ProjectWorkspaceInboxProvider.inboxLaunchBaseline
        let olderActivity = base.addingTimeInterval(60)
        let newerActivity = base.addingTimeInterval(120)
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let older = KanbanCard(id: "older", title: "Older unread", agent: "Cody", created: olderActivity)
        let newer = KanbanCard(id: "newer", title: "Newer unread", agent: "Cody", created: olderActivity, updatedAt: newerActivity)
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [KanbanColumn(id: "testing", name: "Testing", cards: [older, newer])]
        )

        let entries = ProjectWorkspaceInboxProvider.entries(for: workspace, boards: [board])

        XCTAssertEqual(entries.map { $0.card.id }, ["newer", "older"])
    }

    func testProjectInboxLocalTabShowsUnreadCountBadge() {
        let workspace = ProjectWorkspace(
            id: "cider",
            kind: .project,
            title: "Cider",
            subtitle: "Main Cider product workspace",
            boardIDs: ["2afee0"],
            referenceSearchTerms: ["cider"]
        )
        let board = KanbanBoard(
            id: "2afee0",
            name: "Cider",
            columns: [
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "agent",
                            title: "Needs review",
                            agent: "Cody",
                            created: ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(60)
                        ),
                        KanbanCard(
                            id: "reviewed",
                            title: "Reviewed already",
                            agent: "Cody",
                            created: ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(60),
                            reviewedAt: ProjectWorkspaceInboxProvider.inboxLaunchBaseline.addingTimeInterval(120)
                        )
                    ]
                )
            ]
        )

        let inbox = ProjectWorkspaceLocalTabs.tabs(
            for: workspace,
            boards: [board],
            selectedKind: .overview
        ).first { $0.kind == .inbox }

        XCTAssertEqual(inbox?.title, "Updates")
        XCTAssertEqual(inbox?.badge, "1")
    }
}
