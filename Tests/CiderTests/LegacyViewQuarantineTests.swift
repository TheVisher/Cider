import XCTest

final class LegacyViewQuarantineTests: XCTestCase {
    func testActiveNavigationFilesDoNotExposeRemovedViewProductSurface() throws {
        let forbiddenPatternsByPath: [String: [String]] = [
            "Sources/Cider/Models/CiderTab.swift": [
                "case savedView",
                "savedViewID",
                "case legacyView",
                "legacyViewID"
            ],
            "Sources/Cider/Models/WorkspaceDomainRoute.swift": [
                "case savedViews",
                "Saved Views",
                "case views",
                "legacy views"
            ],
            "Sources/Cider/Models/WorkspaceContextualTabPolicy.swift": [
                "savedViews: [SavedView]",
                "views: [LegacyView]"
            ],
            "Sources/Cider/Views/CiderPanelView+TabManagement.swift": [
                "createSavedViewFromCurrentState",
                "deleteSavedView",
                "deleteLegacyView",
                "deleteClosedTab",
                "reopenTab",
                ".savedView",
                ".legacyView"
            ],
            "Sources/Cider/Views/CiderPanelView+SidebarFooter.swift": [
                "selectedTab?.savedViewID",
                "selectedTab?.legacyViewID",
                "onlyUnassignedBinding(for savedViewID",
                "onlyUnassignedBinding(for legacyViewID",
                "tagFilterBinding(for savedViewID",
                "tagFilterBinding(for legacyViewID",
                "entityFilterBinding(for savedViewID",
                "entityFilterBinding(for legacyViewID",
                "sortModeBinding(for savedViewID",
                "sortModeBinding(for legacyViewID"
            ],
            "Sources/Cider/Views/CiderPanelView+ContentArea.swift": [
                "case .savedView",
                "case .legacyView",
                "blankTabWelcome",
                "closedTabsGrid",
                "activateBlankTab",
                "dismissOnboardingTab",
                "openDashboardTab(_ tab: HomeOverviewClosedTabSummary)",
                "libraryFeedMaxVisibleItems(for savedView",
                "libraryFeedMaxVisibleItems(for legacyView"
            ],
            "Sources/Cider/Views/CiderPanelView+KeyboardNavigation.swift": [
                "selectedTab?.savedViewID",
                "selectedTab?.legacyViewID"
            ],
            "Sources/Cider/Views/CiderPanelView+BulkSelection.swift": [
                "selectedTab?.savedViewID",
                "selectedTab?.legacyViewID"
            ],
            "Sources/Cider/Diagnostics/CiderPanelView+LivePerformanceContext.swift": [
                "case .savedView",
                "case .legacyView"
            ]
        ]

        try assertFilesDoNotContain(forbiddenPatternsByPath)
    }

    func testLegacyViewStorageIsReadDeleteCompatibilityOnly() throws {
        let forbiddenPatternsByPath = [
            "Sources/Cider/Services/LegacyViewStorage.swift": [
                "func tabOrderedViews",
                "func addToTabOrder",
                "func insertInTabOrder",
                "func removeFromTabOrder",
                "func moveTab",
                "func createSavedView",
                "func createLegacyView",
                "func createDashboardView",
                "func createKanbanView",
                "func ensureKanbanView",
                "func updateSavedView",
                "func updateLegacyView"
            ]
        ]

        try assertFilesDoNotContain(forbiddenPatternsByPath)
    }

    func testHomeOverviewDoesNotCarryGeneratedTabViewArtifacts() throws {
        let forbiddenPatternsByPath: [String: [String]] = [
            "Sources/Cider/Views/Home/HomeOverviewDataProvider.swift": [
                "savedViews: [SavedView]",
                "views: [LegacyView]",
                "tabOrder: [UUID]",
                "HomeOverviewClosedTabSummary"
            ],
            "Sources/Cider/Views/Home/HomeOverviewModels.swift": [
                "HomeOverviewClosedTabSummary",
                "closedTabs"
            ],
            "Sources/Cider/Views/Home/HomeOverviewDashboardView.swift": [
                "onOpenTab",
                "closedTabsPanel"
            ],
            "Sources/Cider/Views/Home/HomeOverviewPanelComponents.swift": [
                "HomeOverviewClosedTab"
            ],
            "Sources/Cider/Utilities/Constants.swift": [
                "closedTabs",
                "closedTab"
            ]
        ]

        try assertFilesDoNotContain(forbiddenPatternsByPath)
    }

    func testWorkspaceRouteShellDoesNotRestoreDynamicTabsOrContentSwitchOnSelectedTab() throws {
        let forbiddenPatternsByPath: [String: [String]] = [
            "Sources/Cider/Views/CiderPanelView.swift": [
                "@State var selectedTab",
                ".onChange(of: selectedTab)",
                "selectedTab: selectedTab",
                "@State var dynamicTabs",
                "dynamicTabs",
                "var allTabs",
                "var contextualTabs",
                "WorkspaceContextualTabPolicy.tabs"
            ],
            "Sources/Cider/Services/CiderWorkspaceTabStateStore.swift": [
                "restoredDynamicTabs"
            ],
            "Sources/Cider/Views/CiderPanelView+TabManagement.swift": [
                "dynamicTabs.removeAll",
                "allTabs",
                "selectedTab == tab",
                "selectedTab == nil",
                "openDomainDashboardTab("
            ],
            "Sources/Cider/Views/CiderPanelView+ContentArea.swift": [
                "} else if let tab = selectedTab {",
                "switch tab {",
                "noTabsEmptyState",
                "WorkspaceRouteLegacyProjection.state(for: workspaceRouter.currentRoute).selectedTab",
                "selectedTagIDs = [id]",
                "selectedTagIDs.removeAll()"
            ],
            "Sources/Cider/Views/CiderPanelView+Sidebar.swift": [
                "guard case .spaceOverview(let id, _) = selectedTab",
                "selectedTab == .spacesManager",
                "selectedTab == .aiAssistant",
                "selectedTab: selectedTab",
                "openLibraryView(",
                "selectedTab = .domainDashboard(.browse)",
                "selectedTab = .domainDashboard(domain)",
                "selectedTab = headerTab",
                "selectedTab = legacyState.selectedTab",
                "selectedTab = .domainDashboard(.mainDashboard)",
                "selectedTab = .domainDashboard(.aiAssistant)",
                "selectedTab = WorkspaceRouteLegacyProjection.state(for: workspaceRouter.currentRoute).selectedTab",
                "selectedTab: .domainDashboard(.browse)",
                "applyLegacySelectedTab(",
                "selectLegacyDomainDashboardTab("
            ],
            "Sources/Cider/Models/WorkspaceRoute.swift": [
                "WorkspaceRouteLegacyNavigationState",
                "WorkspaceRouteLegacyProjection",
                "var selectedTab: CiderTab?",
                "selectedTab: CiderTab?",
                "selectedTab: .domainDashboard",
                "selectedTab: .aiAssistant",
                "selectedTab: .search",
                "selectedTab: .tag",
                "selectedTab: projectTab",
                "selectedTab: .spaceOverview",
                "selectedTab: .spacesManager"
            ],
            "Sources/Cider/Views/Shared/ProjectsDomainSidebarView.swift": [
                "let selectedTab: CiderTab?",
                "switch selectedTab"
            ],
            "Sources/Cider/Diagnostics/CiderPanelView+LivePerformanceContext.swift": [
                "selectedTab?.displayName",
                "guard let selectedTab",
                "switch selectedTab"
            ],
            "Sources/Cider/Models/CiderPanelViewOptionsPolicy.swift": [
                "selectedTab: CiderTab?",
                "case .search = selectedTab"
            ],
            "Sources/Cider/Views/CiderPanelView+SidebarFooter.swift": [
                "selectedTab: selectedTab"
            ],
            "Sources/Cider/Views/CiderPanelView+TitleBar.swift": [
                "case .spaceOverview",
                "selectedTab == .spacesManager",
                "selectedTab?.displayName",
                "selectedTab.displayName",
                "selectedTab.systemImage"
            ],
            "Sources/Cider/Models/WorkspaceDomainDashboardModel.swift": [
                "allTabs: [CiderTab]",
                "WorkspaceContextualTabPolicy.tabs",
                "target: CiderTab?",
                "item(for tab:"
            ],
            "Sources/Cider/Views/Dashboard/WorkspaceDomainDashboardView.swift": [
                "onOpenTab",
                "CiderTab?"
            ]
        ]

        try assertFilesDoNotContain(forbiddenPatternsByPath)
    }

    func testFinalSavedViewNamesDoNotRemainInActiveCodeOrDocs() throws {
        let repositoryRoot = Self.repositoryRoot
        let removedFiles = [
            "Sources/Cider/Models/SavedView.swift",
            "Sources/Cider/Models/SavedViewKind.swift",
            "Sources/Cider/Services/SavedViewStorage.swift"
        ]
        for relativePath in removedFiles {
            XCTAssertFalse(
                FileManager.default.fileExists(atPath: repositoryRoot.appendingPathComponent(relativePath).path),
                "\(relativePath) should be renamed away from the removed SavedView product name"
            )
        }

        let forbiddenPatternsByPath: [String: [String]] = [
            "Sources/Cider/Views/Home/HomeDashboardView.swift": [
                "SavedViewFilterSpec",
                "SavedViewSortSpec"
            ],
            "Sources/Cider/ViewModels/LibraryViewModel.swift": [
                "SavedViewFilterSpec",
                "SavedViewSortSpec"
            ],
            "Sources/Cider/Views/Settings/SettingsView.swift": [
                ".savedViews",
                ".retiredViewCompatibility"
            ],
            "Sources/CiderCLI/JSONOutput.swift": [
                "savedViewToDict",
                "legacyViewToDict"
            ],
            "Docs/FEATURES.md": [
                "Saved Views",
                "SavedView",
                "legacy views",
                "LegacyView"
            ],
            "Docs/PRODUCT.md": [
                "Saved Views",
                "legacy views"
            ],
            "Docs/STORAGE.md": [
                "saved views",
                "legacy views"
            ],
            "Docs/AGENT.md": [
                "saved-view",
                "legacy-view"
            ],
            "Docs/QA.md": [
                "saved views",
                "legacy views"
            ]
        ]

        try assertFilesDoNotContain(forbiddenPatternsByPath, caseInsensitive: true)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func assertFilesDoNotContain(
        _ forbiddenPatternsByPath: [String: [String]],
        caseInsensitive: Bool = false
    ) throws {
        for (relativePath, forbiddenPatterns) in forbiddenPatternsByPath {
            let fileURL = Self.repositoryRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                continue
            }

            let contents = try String(contentsOf: fileURL, encoding: .utf8)

            for pattern in forbiddenPatterns {
                let contains = caseInsensitive
                    ? contents.localizedCaseInsensitiveContains(pattern)
                    : contents.contains(pattern)
                XCTAssertFalse(
                    contains,
                    "\(relativePath) still contains removed view artifact: \(pattern)"
                )
            }
        }
    }
}
