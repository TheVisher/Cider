import XCTest
@testable import Cider

final class WorkspaceNavigationDomainTests: XCTestCase {
    func testDomainMetadataIncludesRequiredShellDestinations() {
        let domains = WorkspaceNavigationDomain.allCases

        XCTAssertTrue(domains.contains(.mainDashboard))
        XCTAssertTrue(domains.contains(.media))
        XCTAssertTrue(domains.contains(.projects))
        XCTAssertTrue(domains.contains(.aiAssistant))
        XCTAssertTrue(domains.contains(.browse))
        XCTAssertEqual(WorkspaceNavigationDomain.aiAssistant.title, "AI Assistant")
        XCTAssertTrue(WorkspaceNavigationDomain.aiAssistant.opensDomainSidebar)
        XCTAssertEqual(WorkspaceNavigationDomain.projects.systemImage, "square.split.2x1")
    }

    func testHomeAndLibraryAreFirstClassTopLevelDestinations() {
        let domains = WorkspaceDomainSidebarModel.primaryDomains(selectedDomain: .projects)

        XCTAssertEqual(domains.prefix(2), [.mainDashboard, .browse])
        XCTAssertEqual(WorkspaceNavigationDomain.mainDashboard.title, "Home")
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

        XCTAssertEqual(domains, [
            .mainDashboard,
            .browse,
            .media,
            .projects,
            .tasksEvents,
            .people,
            .aiAssistant
        ])
        XCTAssertFalse(domains.contains(.bookmarks))
        XCTAssertFalse(domains.contains(.notes))
        XCTAssertFalse(domains.contains(.files))
    }

    func testLibraryRoutesExposeContentTypesForFastFiltering() {
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .browse).map(\.kind),
            [.inbox, .all, .bookmarks, .notes, .files, .tags]
        )
        XCTAssertEqual(WorkspaceDomainRouteKind.bookmarks.libraryEntityTypes, [.bookmark])
        XCTAssertEqual(WorkspaceDomainRouteKind.notes.libraryEntityTypes, [.note])
        XCTAssertEqual(WorkspaceDomainRouteKind.files.libraryEntityTypes, [.vaultFile])
    }

    func testDomainRoutesUseWorkflowDestinationsInsteadOfContentTypeDomains() {
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .tasksEvents).map(\.kind),
            [.overview, .inbox]
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .media).map(\.kind),
            [.overview]
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .people).map(\.kind),
            [.overview]
        )
        XCTAssertEqual(
            WorkspaceDomainRoutePolicy.routes(for: .aiAssistant).map(\.kind),
            [.overview, .chats]
        )
    }

    func testNestedSidebarRowsUseSharedCompactMetrics() {
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.iconFrame, Spacing.lg)
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.horizontalPadding, Spacing.sm)
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.verticalPadding, Spacing.xxs)
        XCTAssertEqual(WorkspaceSidebarNestedRowMetrics.childIndent, Spacing.lg)
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
}
