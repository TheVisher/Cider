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
}
