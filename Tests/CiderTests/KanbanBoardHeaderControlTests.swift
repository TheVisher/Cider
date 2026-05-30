import Foundation
import Testing
@testable import Cider

struct KanbanBoardHeaderControlTests {
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

    @Test("Kanban filter popover exposes ordered seed categories")
    func filterPopoverExposesOrderedSeedCategories() {
        #expect(KanbanBoardFilterCategory.allCases.map(\.title) == [
            "AI filter",
            "Advanced filter",
            "Status",
            "Priority",
            "Labels",
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
