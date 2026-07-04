import Foundation
import Testing
@testable import Cider

struct KanbanBoardHeaderControlTests {
    @Test("Kanban board header uses compact chrome when inspector narrows the board")
    func headerUsesCompactChromeWhenInspectorNarrowsBoard() {
        #expect(KanbanBoardHeaderLayoutMode.mode(availableWidth: 1180, inspectorVisible: true) == .compact)
        #expect(KanbanBoardHeaderLayoutMode.mode(availableWidth: 1180, inspectorVisible: false) == .regular)
        #expect(KanbanBoardHeaderLayoutMode.mode(availableWidth: 1440, inspectorVisible: true) == .regular)
    }

    @Test("Kanban board view preferences persist per board")
    func boardViewPreferencesPersistPerBoard() {
        let suiteName = "KanbanBoardViewPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = KanbanBoardViewPreferenceStore(defaults: defaults)
        let preferences = KanbanBoardViewPreferences(
            selectedDisplayProperties: [.id, .status, .updated],
            showEmptyColumns: false,
            showSubIssues: false,
            isInspectorVisible: true
        )

        first.setPreferences(preferences, for: "cider")

        let second = KanbanBoardViewPreferenceStore(defaults: defaults)
        #expect(second.preferences(for: "cider") == preferences)
        #expect(second.preferences(for: "other") == .default)
    }

    @Test("Kanban board view preferences can reset to defaults")
    func boardViewPreferencesCanResetToDefaults() {
        let suiteName = "KanbanBoardViewPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = KanbanBoardViewPreferenceStore(defaults: defaults)
        store.setPreferences(
            KanbanBoardViewPreferences(
                selectedDisplayProperties: [.priority],
                showEmptyColumns: false,
                showSubIssues: false,
                isInspectorVisible: true
            ),
            for: "cider"
        )

        store.resetPreferences(for: "cider")

        #expect(store.preferences(for: "cider") == .default)
    }

    @Test("Kanban visible card filter applies attachment type without hiding unattached cards by default")
    func visibleCardFilterAppliesAttachmentTypeWithoutHidingUnattachedCardsByDefault() {
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "queued", name: "Queued", cards: [
                    KanbanCard(
                        id: "research-card",
                        title: "Research card",
                        comments: [
                            KanbanCardComment(
                                id: "research-comment",
                                kind: .note,
                                body: "Comment carries market context.",
                                attachments: [
                                    KanbanCardCommentAttachment(
                                        id: "research-link",
                                        kind: .url,
                                        type: .research,
                                        title: "Research",
                                        url: "https://example.com/research"
                                    )
                                ]
                            )
                        ]
                    ),
                    KanbanCard(
                        id: "qa-card",
                        title: "QA card",
                        comments: [
                            KanbanCardComment(
                                id: "qa-comment",
                                kind: .qa,
                                body: "QA notes.",
                                attachments: [
                                    KanbanCardCommentAttachment(
                                        id: "qa-file",
                                        kind: .file,
                                        type: .qa,
                                        title: "QA",
                                        localPath: "Projects/Cider/QA/report.md"
                                    )
                                ]
                            )
                        ]
                    ),
                    KanbanCard(id: "plain-card", title: "Plain card")
                ])
            ]
        )
        let column = board.columns[0]

        let unfiltered = KanbanBoardVisibleCardFilter.filteredCards(
            column.cards,
            in: column,
            board: board,
            searchText: "",
            attachmentType: nil,
            featureDomainFilter: nil,
            projectBoardViewID: "all",
            milestoneFilterCardID: nil
        )
        let researchFiltered = KanbanBoardVisibleCardFilter.filteredCards(
            column.cards,
            in: column,
            board: board,
            searchText: "",
            attachmentType: .research,
            featureDomainFilter: nil,
            projectBoardViewID: "all",
            milestoneFilterCardID: nil
        )
        let commentSearchFiltered = KanbanBoardVisibleCardFilter.filteredCards(
            column.cards,
            in: column,
            board: board,
            searchText: "market context",
            attachmentType: nil,
            featureDomainFilter: nil,
            projectBoardViewID: "all",
            milestoneFilterCardID: nil
        )
        let researchAndPlainIDFiltered = KanbanBoardVisibleCardFilter.filteredCards(
            column.cards,
            in: column,
            board: board,
            searchText: "plain-card",
            attachmentType: .research,
            featureDomainFilter: nil,
            projectBoardViewID: "all",
            milestoneFilterCardID: nil
        )

        #expect(unfiltered.map(\.id) == ["research-card", "qa-card", "plain-card"])
        #expect(researchFiltered.map(\.id) == ["research-card"])
        #expect(commentSearchFiltered.map(\.id) == ["research-card"])
        #expect(researchAndPlainIDFiltered.isEmpty)
    }

    @Test("Kanban attachment filter options use command-center order")
    func attachmentFilterOptionsUseCommandCenterOrder() {
        #expect(KanbanBoardAttachmentTypeFilterOption.allCases.map(\.type) == [
            .research,
            .inspiration,
            .evidence,
            .handoff,
            .qa,
            .reference,
        ])
    }

    @Test("Kanban scan strip summarizes active filters, result counts, and column counts")
    func scanStripSummarizesActiveFiltersResultCountsAndColumnCounts() {
        let milestone = KanbanCard(
            id: "milestone",
            title: "Milestone: Command center",
            displayKey: "CID-10",
            tags: ["milestone-object"]
        )
        let matching = KanbanCard(
            id: "matching",
            title: "Wire scan filters",
            displayKey: "CID-11",
            priority: .high,
            tags: ["kanban", "needs-qa"],
            parentCardID: milestone.id,
            comments: [
                KanbanCardComment(
                    id: "qa-comment",
                    kind: .qa,
                    body: "Verify scan strip layout.",
                    attachments: [
                        KanbanCardCommentAttachment(
                            id: "qa-file",
                            kind: .file,
                            type: .qa,
                            title: "QA report",
                            localPath: "Projects/Cider/QA/scan.md"
                        )
                    ]
                )
            ]
        )
        let hiddenByDomain = KanbanCard(
            id: "hidden-domain",
            title: "Capture flow",
            tags: ["capture"],
            parentCardID: milestone.id
        )
        let hiddenByColumn = KanbanCard(id: "done-child", title: "Done child", parentCardID: milestone.id)
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [milestone, hiddenByDomain]),
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [matching]),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true, cards: [hiddenByColumn]),
            ]
        )

        let state = KanbanBoardScanStripState.state(
            in: board,
            searchText: "scan",
            attachmentType: .qa,
            featureDomainFilter: "kanban",
            projectBoardViewID: "active",
            milestoneFilterCardID: milestone.id
        )

        #expect(state.totalCardCount == 4)
        #expect(state.visibleCardCount == 1)
        #expect(state.resultText == "1 of 4 cards")
        #expect(state.activeFilterCount == 5)
        #expect(state.activeFilterSummary == "5 filters")
        #expect(state.columnCounts.map(\.label) == ["Backlog", "In Progress", "Done"])
        #expect(state.columnCounts.map(\.countText) == ["0/2", "1/1", "0/1"])
    }

    @Test("Kanban scan strip rows expose ordered high signal filter metadata")
    func scanStripRowsExposeOrderedHighSignalFilterMetadata() {
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [
                    KanbanCard(id: "milestone", title: "Milestone: Board control", displayKey: "CID-90")
                ])
            ]
        )

        let rows = KanbanBoardScanStripFilterRow.rows(
            in: board,
            searchText: "control",
            attachmentType: .research,
            featureDomainFilter: "kanban",
            projectBoardViewID: "active",
            milestoneFilterCardID: "milestone"
        )

        #expect(rows.map(\.title) == ["View", "Domain", "Attachment", "Milestone", "Search"])
        #expect(rows.map(\.value) == ["Active", "Kanban", "Research", "CID-90", "control"])
        #expect(rows.map(\.isActive) == [true, true, true, true, true])
        #expect(rows.map(\.systemImage) == [
            "rectangle.3.group",
            "cube.transparent",
            "paperclip",
            "diamond",
            "magnifyingglass",
        ])
    }

    @Test("Kanban compact card scan metadata exposes key status chips readiness and attachments")
    func compactCardScanMetadataExposesKeyStatusChipsReadinessAndAttachments() {
        let card = KanbanCard(
            id: "card",
            title: "Ship command strip",
            displayKey: "CID-200",
            priority: .high,
            tags: ["kanban", "needs-qa", "agent-can-verify"],
            comments: [
                KanbanCardComment(
                    id: "evidence-comment",
                    kind: .qa,
                    body: "Agent verification notes.",
                    attachments: [
                        KanbanCardCommentAttachment(
                            id: "evidence",
                            kind: .file,
                            type: .evidence,
                            title: "Evidence",
                            localPath: "Projects/Cider/QA/evidence.md"
                        )
                    ]
                )
            ]
        )
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [KanbanColumn(id: "testing", name: "Testing", cards: [card])]
        )

        let metadata = KanbanCardScanMetadata.metadata(
            for: card,
            in: board,
            column: board.columns[0]
        )

        #expect(metadata.displayKey == "CID-200")
        #expect(metadata.title == "Ship command strip")
        #expect(metadata.status == "Testing")
        #expect(metadata.readiness == "Agent can verify")
        #expect(metadata.attachmentText == "1 ref")
        #expect(metadata.chips.map(\.label) == ["Refs 1", "Kanban", "Needs QA"])
    }

    @Test("Kanban board header exposes the three control entry points")
    func exposesBoardControlEntryPoints() {
        #expect(KanbanBoardHeaderControl.allCases.map(\.title) == [
            "Filter",
            "Display Options",
            "Properties",
        ])

        #expect(KanbanBoardHeaderControl.allCases.map(\.systemImage) == [
            "line.3.horizontal.decrease.circle",
            "slider.horizontal.3",
            "sidebar.right",
        ])

        #expect(KanbanBoardHeaderControl.allCases.map(\.helpText) == [
            "Filter board",
            "Display options",
            "Show board properties",
        ])
    }

    @Test("Kanban board header control placeholders stay shell-only")
    func placeholdersStayShellOnly() {
        #expect(KanbanBoardHeaderControl.filter.placeholderTitle == "Filter controls are coming next.")
        #expect(KanbanBoardHeaderControl.displayOptions.placeholderTitle == "Display options are coming next.")
        #expect(KanbanBoardHeaderControl.properties.placeholderTitle == "Board properties are coming next.")
    }

    @Test("Kanban properties inspector shell exposes ordered placeholder sections")
    func propertiesInspectorShellExposesOrderedPlaceholderSections() {
        #expect(KanbanBoardInspectorSection.allCases.map(\.title) == [
            "Properties",
            "Milestones",
            "Progress",
            "Activity",
        ])

        #expect(KanbanBoardInspectorSection.allCases.map(\.systemImage) == [
            "list.bullet.rectangle",
            "diamond",
            "chart.bar.xaxis",
            "clock.arrow.circlepath",
        ])

        #expect(KanbanBoardInspectorSection.allCases.map(\.placeholderText) == [
            "Board status, priority, ownership, labels, dates, and counts will appear here.",
            "Milestone rows with child counts and quick filter actions will appear here.",
            "Completed, active, blocked, and testing breakdowns will appear here.",
            "Recent board changes, card history, and test evidence will appear here.",
        ])
    }

    @Test("Kanban inspector milestone rows expose progress and selected state")
    func inspectorMilestoneRowsExposeProgressAndSelectedState() {
        let milestone = KanbanCard(
            id: "milestone",
            title: "Milestone: Inspector work",
            displayKey: "CID-10",
            tags: ["milestone-object"]
        )
        let queued = KanbanCard(id: "queued", title: "Queued child", parentCardID: milestone.id)
        let testing = KanbanCard(id: "testing", title: "Testing child", parentCardID: milestone.id)
        let done = KanbanCard(id: "done", title: "Done child", parentCardID: milestone.id)
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [milestone, queued]),
                KanbanColumn(id: "testing", name: "Testing", cards: [testing]),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true, cards: [done]),
            ]
        )

        let rows = KanbanBoardInspectorMilestoneRow.rows(in: board, selectedID: milestone.id)

        #expect(rows.map(\.id) == ["milestone"])
        #expect(rows.map(\.title) == ["Inspector work"])
        #expect(rows.map(\.displayKey) == ["CID-10"])
        #expect(rows.map(\.status) == ["Backlog"])
        #expect(rows.map(\.progressText) == ["1/3"])
        #expect(rows.map(\.completedChildCount) == [1])
        #expect(rows.map(\.childCount) == [3])
        #expect(rows.map(\.progressPercentText) == ["33%"])
        #expect(rows.map(\.isSelected) == [true])
    }

    @Test("Kanban inspector progress summary counts board workflow states")
    func inspectorProgressSummaryCountsBoardWorkflowStates() {
        let completedAt = Date(timeIntervalSince1970: 1)
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [
                    KanbanCard(id: "queued", title: "Queued"),
                    KanbanCard(id: "blocked", title: "Blocked by design", tags: ["blocked"]),
                ]),
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [
                    KanbanCard(id: "active", title: "Active"),
                ]),
                KanbanColumn(id: "testing", name: "Testing", cards: [
                    KanbanCard(id: "testing", title: "Testing"),
                ]),
                KanbanColumn(id: "done", name: "Done", isDoneColumn: true, cards: [
                    KanbanCard(id: "done", title: "Done", completed: completedAt),
                ]),
            ]
        )

        let summary = KanbanBoardInspectorProgressSummary.summary(in: board)

        #expect(summary.total == 5)
        #expect(summary.completed == 1)
        #expect(summary.backlog == 2)
        #expect(summary.inProgress == 1)
        #expect(summary.testing == 1)
        #expect(summary.blocked == 1)
        #expect(summary.completedPercentText == "20%")
    }

    @Test("Kanban inspector activity entries prefer meaningful recent card events")
    func inspectorActivityEntriesPreferMeaningfulRecentCardEvents() {
        let older = Date(timeIntervalSince1970: 100)
        let newest = Date(timeIntervalSince1970: 300)
        let middle = Date(timeIntervalSince1970: 200)
        let milestone = KanbanCard(
            id: "milestone",
            title: "Milestone: Inspector work",
            displayKey: "CID-10",
            tags: ["milestone-object"],
            historyEntries: [
                KanbanCardHistoryEntry(
                    id: "implementation",
                    type: .implementation,
                    body: "Implemented the inspector activity rows.\nExtra detail should be summarized.",
                    author: "codex",
                    createdAt: newest
                ),
            ],
            updatedAt: older,
            lastActivityKind: "updated"
        )
        let child = KanbanCard(
            id: "child",
            title: "QA inspector polish",
            displayKey: "CID-11",
            comments: [
                KanbanCardComment(
                    id: "qa",
                    kind: .qa,
                    body: "Visual QA passed for the activity section.",
                    author: "tester",
                    source: "computer-use",
                    createdAt: middle
                ),
            ],
            updatedAt: older
        )
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [milestone, child]),
            ]
        )

        let entries = KanbanBoardInspectorActivityEntry.entries(in: board, limit: 3)

        #expect(entries.map(\.id) == ["history-implementation", "comment-qa", "updated-milestone"])
        #expect(entries.map(\.cardID) == ["milestone", "child", "milestone"])
        #expect(entries.map(\.displayKey) == ["CID-10", "CID-11", "CID-10"])
        #expect(entries.map(\.title) == ["Inspector work", "QA inspector polish", "Inspector work"])
        #expect(entries.map(\.kind) == ["Implementation", "QA", "Updated"])
        #expect(entries.map(\.body) == [
            "Implemented the inspector activity rows.",
            "Visual QA passed for the activity section.",
            "Card updated",
        ])
    }

    @Test("Kanban filter popover exposes ordered seed categories")
    func filterPopoverExposesOrderedSeedCategories() {
        #expect(KanbanBoardFilterCategory.allCases.map(\.title) == [
            "AI filter",
            "Advanced filter",
            "Status",
            "Priority",
            "Labels",
            "Attachments",
            "Relations",
            "Dates",
            "Project milestone",
            "Content",
            "Links",
        ])

        #expect(KanbanBoardFilterCategory.allCases.map(\.stateLabel) == [
            "Placeholder",
            "Placeholder",
            "Coming later",
            "Coming later",
            "Coming later",
            "Ready",
            "Coming later",
            "Coming later",
            "Next",
            "Coming later",
            "Coming later",
        ])
    }

    @Test("Kanban milestone filter options include milestone cards with progress and selected state")
    func milestoneFilterOptionsIncludeMilestoneCardsWithProgressAndSelectedState() {
        let selected = KanbanCard(
            id: "selected-milestone",
            title: "Milestone: Selected goal",
            displayKey: "CID-20",
            tags: ["milestone-object"]
        )
        let regularParent = KanbanCard(
            id: "regular-parent",
            title: "Regular parent"
        )
        let fallbackMilestone = KanbanCard(
            id: "fallback-milestone",
            title: "Milestone: Fallback title",
            displayKey: "CID-21"
        )
        let selectedChild = KanbanCard(
            id: "selected-child",
            title: "Selected child",
            parentCardID: selected.id
        )
        let selectedDoneChild = KanbanCard(
            id: "selected-done-child",
            title: "Selected done child",
            parentCardID: selected.id,
            completed: Date(timeIntervalSince1970: 1)
        )

        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [
                    regularParent,
                    selected,
                    selectedChild,
                    fallbackMilestone,
                ]),
                KanbanColumn(id: "done", name: "Done", cards: [
                    selectedDoneChild,
                ]),
            ]
        )

        let options = KanbanBoardMilestoneFilterOption.options(in: board, selectedID: selected.id)

        #expect(options.map(\.id) == ["selected-milestone", "fallback-milestone"])
        #expect(options.map(\.title) == ["Selected goal", "Fallback title"])
        #expect(options.map(\.displayKey) == ["CID-20", "CID-21"])
        #expect(options.map(\.progressText) == ["1/2", nil])
        #expect(options.map(\.isSelected) == [true, false])
    }

    @Test("Kanban display options shell exposes expected layout ordering and property controls")
    func displayOptionsShellExposesExpectedControls() {
        #expect(KanbanBoardDisplayModeOption.allCases.map(\.title) == [
            "Board",
            "List",
        ])
        #expect(KanbanBoardDisplayModeOption.allCases.map(\.stateLabel) == [
            "Active",
            "Later",
        ])

        #expect(KanbanBoardDisplayOrderingOption.allCases.map(\.title) == [
            "Manual lane order",
            "Priority",
            "Created",
            "Updated",
        ])

        #expect(KanbanBoardDisplayPropertyOption.allCases.map(\.title) == [
            "ID",
            "Status",
            "Priority",
            "Milestone",
            "Labels",
            "Links",
            "Created",
            "Updated",
        ])
    }

    @Test("Kanban display property values expose selected card metadata with fallbacks")
    func displayPropertyValuesExposeSelectedCardMetadataWithFallbacks() {
        let created = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01
        let updated = Date(timeIntervalSince1970: 1_704_153_600) // 2024-01-02
        let milestone = KanbanCard(
            id: "milestone",
            title: "Milestone: Launch board controls",
            displayKey: "CID-100",
            tags: ["milestone-object"]
        )
        let card = KanbanCard(
            id: "card",
            title: "Wire properties",
            displayKey: "CID-101",
            priority: .high,
            tags: ["cider-web", "needs-qa"],
            linkedEntities: [LibraryEntityRef(type: .bookmark, entityID: UUID())],
            parentCardID: milestone.id,
            created: created,
            updatedAt: updated
        )
        let board = KanbanBoard(
            id: "cider",
            name: "Cider",
            columns: [
                KanbanColumn(id: "backlog", name: "Backlog", cards: [milestone]),
                KanbanColumn(id: "in_progress", name: "In Progress", cards: [card]),
            ]
        )

        let values = KanbanBoardDisplayPropertyValue.values(
            for: card,
            in: board,
            column: board.columns[1],
            options: KanbanBoardDisplayPropertyOption.allCases
        )

        #expect(values.map(\.value) == [
            "CID-101",
            "In Progress",
            "High",
            "Launch board controls",
            "Cider Web, Needs QA",
            "1 link",
            "Jan 1, 2024",
            "Jan 2, 2024",
        ])

        let sparse = KanbanCard(id: "sparse", title: "Sparse", created: created)
        let sparseValues = KanbanBoardDisplayPropertyValue.values(
            for: sparse,
            in: board,
            column: board.columns[0],
            options: [.priority, .milestone, .labels, .links, .updated]
        )

        #expect(sparseValues.map(\.value) == [
            "No priority",
            "No milestone",
            "No labels",
            "No links",
            "No updates",
        ])
        #expect(sparseValues.map(\.isFallback) == [true, true, true, true, true])
    }
}
