import XCTest
@testable import Cider

final class WorkspaceNavigationDomainTests: XCTestCase {
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testDomainMetadataIncludesRequiredShellDestinations() {
        let domains = WorkspaceNavigationDomain.allCases

        XCTAssertTrue(domains.contains(.mainDashboard))
        XCTAssertTrue(domains.contains(.spaces))
        XCTAssertTrue(domains.contains(.media))
        XCTAssertTrue(domains.contains(.projects))
        XCTAssertTrue(domains.contains(.review))
        XCTAssertTrue(domains.contains(.aiAssistant))
        XCTAssertTrue(domains.contains(.journal))
        XCTAssertTrue(domains.contains(.browse))
        XCTAssertEqual(WorkspaceNavigationDomain.aiAssistant.title, "Main Brain")
        XCTAssertEqual(WorkspaceNavigationDomain.journal.title, "Journal")
        XCTAssertTrue(WorkspaceNavigationDomain.aiAssistant.opensDomainSidebar)
        XCTAssertEqual(WorkspaceNavigationDomain.projects.systemImage, "square.split.2x1")
    }

    func testPrimarySidebarRootsAreExplicitAndStable() {
        XCTAssertEqual(WorkspaceNavigationDomain.primaryRoots, [
            .aiAssistant,
            .journal,
            .mainDashboard,
            .browse,
            .projects
        ])
        XCTAssertEqual(
            WorkspaceNavigationDomain.primaryRoots.map(\.title),
            ["Main Brain", "Journal", "Today", "Library", "Projects"]
        )
        XCTAssertTrue(WorkspaceNavigationDomain.primaryRoots.allSatisfy(\.isPrimaryRoot))
        XCTAssertFalse(WorkspaceNavigationDomain.review.isPrimaryRoot)
        XCTAssertFalse(WorkspaceNavigationDomain.spaces.isPrimaryRoot)
    }

    func testDomainSurfacesAreClassifiedAsSpacesInsteadOfPrimaryRoots() {
        let domainSurfaces: [WorkspaceNavigationDomain] = [
            .projects,
            .tasksEvents,
            .people,
            .media,
            .bookmarks,
            .notes,
            .files,
            .review
        ]

        XCTAssertTrue(domainSurfaces.allSatisfy(\.isDomainSpaceSurface))
        XCTAssertTrue(domainSurfaces.filter { $0 != .projects }.allSatisfy { !$0.isPrimaryRoot })
        XCTAssertTrue(WorkspaceNavigationDomain.projects.isPrimaryRoot)
    }

    func testTodayAndLibraryAreFirstClassTopLevelDestinations() {
        let domains = WorkspaceDomainSidebarModel.primaryDomains(selectedDomain: .projects)

        XCTAssertEqual(Array(domains.dropFirst(2).prefix(2)).map(\.title), ["Today", "Library"])
        XCTAssertEqual(WorkspaceNavigationDomain.mainDashboard.title, "Today")
        XCTAssertEqual(WorkspaceNavigationDomain.browse.title, "Library")
    }

    func testNavigationStateBuildsBreadcrumbAndCanReturnToGlobalDomains() {
        var state = WorkspaceNavigationState()

        XCTAssertTrue(state.isShowingGlobalDomains)
        XCTAssertEqual(state.breadcrumbPath, ["Cider"])

        state.select(.media)

        XCTAssertFalse(state.isShowingGlobalDomains)
        XCTAssertEqual(state.selectedDomain, .media)
        XCTAssertEqual(state.breadcrumbPath, ["Cider", "Media"])

        state.goBackToGlobalDomains()

        XCTAssertNil(state.selectedDomain)
        XCTAssertEqual(state.breadcrumbPath, ["Cider"])
    }

    func testPersistentSidebarShowsWorkflowDomainsNotContentTypes() {
        let domains = WorkspaceDomainSidebarModel.primaryDomains(selectedDomain: .browse)

        XCTAssertEqual(domains.map(\.title), ["Main Brain", "Journal", "Today", "Library", "Projects"])
        XCTAssertFalse(domains.contains(.review))
        XCTAssertTrue(domains.contains(.projects))
        XCTAssertFalse(domains.contains(.tasksEvents))
        XCTAssertFalse(domains.contains(.people))
        XCTAssertFalse(domains.contains(.bookmarks))
        XCTAssertFalse(domains.contains(.notes))
        XCTAssertFalse(domains.contains(.files))
    }

    func testParkedSpacesStayOutOfPrimarySidebarUntilSpacesRouteIsOpen() {
        let mediaSpace = CiderSpace(
            id: "media-space",
            name: "Media",
            systemImage: "play.rectangle",
            purpose: "Movies, shows, games, books, and entertainment tracking.",
            preset: .media,
            isPinned: true,
            aiInstructions: "Route media here.",
            routingHints: [],
            defaultViews: [.overview],
            rootRelativePath: "Spaces/Media"
        )

        let domains = WorkspaceDomainSidebarModel.primaryDomains(
            selectedDomain: .browse,
            pinnedSpaces: [mediaSpace]
        )

        XCTAssertFalse(domains.contains(.media))
        XCTAssertEqual(domains.map(\.title), ["Main Brain", "Journal", "Today", "Library", "Projects"])

        XCTAssertEqual(
            WorkspaceDomainSidebarModel.primaryDomains(
                selectedDomain: .spaces,
                pinnedSpaces: [mediaSpace]
            ).map(\.title),
            ["Main Brain", "Journal", "Today", "Library", "Projects"]
        )
    }

    func testLibraryRoutesExposeContentTypesAndFoldersForFastFiltering() {
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .browse).map(\.kind),
            [.inbox, .all, .bookmarks, .notes, .files, .folders, .tags]
        )
        XCTAssertEqual(WorkspaceDomainRouteKind.bookmarks.libraryEntityTypes, [.bookmark])
        XCTAssertEqual(WorkspaceDomainRouteKind.notes.libraryEntityTypes, [.note])
        XCTAssertEqual(WorkspaceDomainRouteKind.files.libraryEntityTypes, [.vaultFile])
    }

    func testLibraryLeafRoutesResolveToScopedContentInsteadOfDashboard() {
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .overview, in: .browse),
            .dashboard
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .all, in: .browse),
            .libraryFeed(onlyUnassigned: false, entityTypes: LibraryEntityType.activeCases)
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .inbox, in: .browse),
            .libraryFeed(onlyUnassigned: true, entityTypes: LibraryEntityType.activeCases)
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .bookmarks, in: .browse),
            .libraryFeed(onlyUnassigned: false, entityTypes: [.bookmark])
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .notes, in: .browse),
            .libraryFeed(onlyUnassigned: false, entityTypes: [.note])
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .files, in: .browse),
            .libraryFeed(onlyUnassigned: false, entityTypes: [.vaultFile])
        )
    }

    func testHomeRouteResolvesToOverviewDashboard() {
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.contentPresentation(for: .overview, in: .mainDashboard),
            .homeOverviewDashboard
        )
    }

    func testHeaderDestinationsOpenSectionDashboardsInsteadOfFirstChildRoutes() {
        XCTAssertNil(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .mainDashboard))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .browse), .domainDashboard(.browse))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .spaces), .domainDashboard(.spaces))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .projects), .domainDashboard(.projects))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .review), .domainDashboard(.review))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .tasksEvents), .domainDashboard(.tasksEvents))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .people), .domainDashboard(.people))
        XCTAssertEqual(WorkspaceDomainRoutePolicy.headerDefaultTab(for: .aiAssistant), .domainDashboard(.aiAssistant))
    }

    func testDomainRoutesUseWorkflowDestinationsInsteadOfContentTypeDomains() {
        for domain in WorkspaceNavigationDomain.allCases {
            XCTAssertFalse(
                WorkspaceDomainRoutePolicy.routes(for: domain).contains { $0.title == "Saved Views" },
                "\(domain.title) should not expose retired saved-view route"
            )
        }
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .tasksEvents).map(\.kind),
            [.inbox]
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .media).map(\.kind),
            []
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .spaces).map(\.kind),
            []
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .review).map(\.kind),
            []
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .people).map(\.kind),
            []
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .aiAssistant).map(\.kind),
            [.chats]
        )
    }

    func testNestedSidebarRowsUseSharedCompactMetrics() {
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.iconFrame, Spacing.lg)
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.horizontalPadding, Spacing.sm)
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.verticalPadding, Spacing.xxs)
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.childIndent, Spacing.lg)
    }

    func testSidebarSelectionChangesAreNotImplicitlyAnimated() throws {
        let sourceURL = Self.repositoryRoot
            .appendingPathComponent("Sources/Cider/Views/Shared/WorkspaceDomainSidebarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("value: selectedDomain"),
            "Sidebar selection should update immediately; keep animation scoped to expansion/layout changes."
        )
        XCTAssertTrue(
            source.contains("value: expandedDomains"),
            "Domain expansion can remain animated independently of route selection feedback."
        )
    }

    func testSpacesSidebarDoesNotExposeStarterChildButtons() throws {
        let sourceURL = Self.repositoryRoot
            .appendingPathComponent("Sources/Cider/Views/Shared/WorkspaceDomainSidebarView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(
            source.contains("missingStarterPresets"),
            "Starter Spaces should stay deferred to the Spaces manager/dashboard instead of appearing as live sidebar child buttons."
        )
        XCTAssertFalse(
            source.contains("starterSpaceButton"),
            "The Spaces sidebar should not expose one-click starter Space creation rows."
        )
        XCTAssertFalse(
            source.contains("ForEach(pinnedSpaces)"),
            "Pinned Spaces should stay reachable through All Spaces instead of appearing as sidebar child buttons."
        )
    }

    func testDomainExpansionStateCanOpenMultipleDomainsWithoutNavigationSelection() {
        var state = WorkspaceDomainSidebarExpansionState()

        state.toggle(.browse)
        state.toggle(.projects)

        XCTAssertTrue(state.isExpanded(.browse))
        XCTAssertTrue(state.isExpanded(.projects))
        XCTAssertFalse(state.isExpanded(.media))

        state.toggle(.browse)

        XCTAssertFalse(state.isExpanded(.browse))
        XCTAssertTrue(state.isExpanded(.projects))
    }

    func testDomainExpansionStateExpandsAllExpandableDomainsAndKeepsHomeCollapsed() {
        var state = WorkspaceDomainSidebarExpansionState()
        let domains = WorkspaceDomainSidebarModel.primaryDomains(selectedDomain: .projects)

        state.expandAll(in: domains)

        XCTAssertEqual(
            state.expandedDomains,
            Set(domains.filter { $0 != .mainDashboard })
        )
        XCTAssertFalse(state.isExpanded(.mainDashboard))

        state.collapseAll()

        XCTAssertTrue(state.expandedDomains.isEmpty)
    }

    func testSpaceTabsHaveStableIdentityAndReadableLabels() {
        let tab = CiderTab.spaceOverview(id: "media-space", name: "Media")

        XCTAssertEqual(tab.id, "space-overview-media-space")
        XCTAssertEqual(tab.displayName, "Media")
        XCTAssertEqual(tab.systemImage, "square.grid.2x2")
    }

    func testSpacesManagerTabIsSeparateFromLibraryAndDomains() {
        let tab = CiderTab.spacesManager

        XCTAssertEqual(tab.id, "spaces-manager")
        XCTAssertEqual(tab.displayName, "All Spaces")
        XCTAssertEqual(tab.systemImage, "square.grid.2x2")
    }

    func testHomeSidebarSelectionDoesNotCompeteWithSpaces() {
        XCTAssertTrue(WorkspaceDomainSidebarModel.isDomainSelected(
            .mainDashboard,
            selectedDomain: nil,
            selectedSpaceID: nil,
            isSpacesManagerSelected: false
        ))
        XCTAssertFalse(WorkspaceDomainSidebarModel.isDomainSelected(
            .mainDashboard,
            selectedDomain: nil,
            selectedSpaceID: "media-space",
            isSpacesManagerSelected: false
        ))
        XCTAssertFalse(WorkspaceDomainSidebarModel.isDomainSelected(
            .mainDashboard,
            selectedDomain: nil,
            selectedSpaceID: nil,
            isSpacesManagerSelected: true
        ))
        XCTAssertTrue(WorkspaceDomainSidebarModel.isDomainSelected(
            .projects,
            selectedDomain: .projects,
            selectedSpaceID: "media-space",
            isSpacesManagerSelected: false
        ))
    }

    func testSpacesSidebarSelectionFollowsPinnedSpacesAndSpacesManager() {
        XCTAssertTrue(WorkspaceDomainSidebarModel.isDomainSelected(
            .spaces,
            selectedDomain: nil,
            selectedSpaceID: "media-space",
            isSpacesManagerSelected: false
        ))
        XCTAssertTrue(WorkspaceDomainSidebarModel.isDomainSelected(
            .spaces,
            selectedDomain: nil,
            selectedSpaceID: nil,
            isSpacesManagerSelected: true
        ))
        XCTAssertTrue(WorkspaceDomainSidebarModel.isDomainSelected(
            .spaces,
            selectedDomain: .spaces,
            selectedSpaceID: nil,
            isSpacesManagerSelected: false
        ))
        XCTAssertFalse(WorkspaceDomainSidebarModel.isDomainSelected(
            .browse,
            selectedDomain: nil,
            selectedSpaceID: "media-space",
            isSpacesManagerSelected: false
        ))
    }
}
