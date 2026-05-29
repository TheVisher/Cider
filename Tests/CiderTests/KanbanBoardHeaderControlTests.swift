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
}
