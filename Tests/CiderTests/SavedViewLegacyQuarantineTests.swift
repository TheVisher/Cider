import XCTest

final class SavedViewLegacyQuarantineTests: XCTestCase {
    func testActiveNavigationFilesDoNotExposeSavedViewProductSurface() throws {
        let forbiddenPatternsByPath: [String: [String]] = [
            "Sources/Cider/Models/CiderTab.swift": [
                "case savedView",
                "savedViewID"
            ],
            "Sources/Cider/Models/WorkspaceDomainRoute.swift": [
                "case savedViews",
                "Saved Views"
            ],
            "Sources/Cider/Models/WorkspaceContextualTabPolicy.swift": [
                "savedViews: [SavedView]"
            ],
            "Sources/Cider/Views/CiderPanelView+TabManagement.swift": [
                "createSavedViewFromCurrentState",
                "deleteSavedView",
                "deleteClosedTab",
                "reopenTab",
                ".savedView"
            ],
            "Sources/Cider/Views/CiderPanelView+SidebarFooter.swift": [
                "selectedTab?.savedViewID",
                "onlyUnassignedBinding(for savedViewID",
                "tagFilterBinding(for savedViewID",
                "entityFilterBinding(for savedViewID",
                "sortModeBinding(for savedViewID"
            ],
            "Sources/Cider/Views/Shared/CiderTabBar.swift": [
                "SavedViewStorage.shared",
                "closedTabs",
                "savedViewMenuItems",
                "onReopenTab",
                ".savedView"
            ],
            "Sources/Cider/Views/CiderPanelView+ContentArea.swift": [
                "case .savedView",
                "blankTabWelcome",
                "closedTabsGrid",
                "activateBlankTab",
                "dismissOnboardingTab",
                "openDashboardTab(_ tab: HomeOverviewClosedTabSummary)",
                "libraryFeedMaxVisibleItems(for savedView"
            ],
            "Sources/Cider/Views/CiderPanelView+KeyboardNavigation.swift": [
                "selectedTab?.savedViewID"
            ],
            "Sources/Cider/Views/CiderPanelView+BulkSelection.swift": [
                "selectedTab?.savedViewID"
            ],
            "Sources/Cider/Diagnostics/CiderPanelView+LivePerformanceContext.swift": [
                "case .savedView"
            ]
        ]

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for (relativePath, forbiddenPatterns) in forbiddenPatternsByPath {
            let contents = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )

            for pattern in forbiddenPatterns {
                XCTAssertFalse(
                    contents.contains(pattern),
                    "\(relativePath) still contains active SavedView product-surface pattern: \(pattern)"
                )
            }
        }
    }

    func testSavedViewStorageIsLegacyReadDeleteCompatibilityOnly() throws {
        let forbiddenPatterns = [
            "func tabOrderedViews",
            "func addToTabOrder",
            "func insertInTabOrder",
            "func removeFromTabOrder",
            "func moveTab",
            "func createSavedView",
            "func createDashboardView",
            "func createKanbanView",
            "func ensureKanbanView",
            "func updateSavedView"
        ]

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let storagePath = "Sources/Cider/Services/SavedViewStorage.swift"
        let contents = try String(
            contentsOf: repositoryRoot.appendingPathComponent(storagePath),
            encoding: .utf8
        )

        for pattern in forbiddenPatterns {
            XCTAssertFalse(
                contents.contains(pattern),
                "\(storagePath) still exposes legacy SavedView mutation API: \(pattern)"
            )
        }
    }

    func testHomeOverviewDoesNotCarryGeneratedTabSavedViewArtifacts() throws {
        let forbiddenPatternsByPath: [String: [String]] = [
            "Sources/Cider/Views/Home/HomeOverviewDataProvider.swift": [
                "savedViews: [SavedView]",
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

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for (relativePath, forbiddenPatterns) in forbiddenPatternsByPath {
            let contents = try String(
                contentsOf: repositoryRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )

            for pattern in forbiddenPatterns {
                XCTAssertFalse(
                    contents.contains(pattern),
                    "\(relativePath) still carries generated-tab SavedView artifact: \(pattern)"
                )
            }
        }
    }
}
