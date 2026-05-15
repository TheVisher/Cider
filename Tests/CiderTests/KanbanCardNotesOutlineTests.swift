import Foundation
import Testing
@testable import Cider

struct KanbanCardNotesOutlineTests {
    @Test("notes outline parses common markdown sections without rewriting raw notes")
    func notesOutlineParsesCommonMarkdownSections() {
        let notes = """
        Intro context that should stay available.

        ## Problem
        - Cards feel like one long blob.

        ## Goal
        Make common handoff sections scannable.

        ## Test Evidence
        - swift test --filter KanbanCardNotesOutlineTests passed.
        - git diff --check passed.
        """

        let outline = KanbanCardNotesOutline(notes: notes)

        #expect(outline.leadingText == "Intro context that should stay available.")
        #expect(outline.sections.map(\.title) == ["Problem", "Goal", "Test Evidence"])
        #expect(outline.sections[0].body == "- Cards feel like one long blob.")
        #expect(outline.sections[1].body == "Make common handoff sections scannable.")
        #expect(outline.sections[2].bulletItems == [
            "swift test --filter KanbanCardNotesOutlineTests passed.",
            "git diff --check passed.",
        ])
        #expect(outline.hasStructuredSections)
    }

    @Test("notes outline leaves unstructured notes alone")
    func notesOutlineLeavesUnstructuredNotesAlone() {
        let notes = "A quick freeform reminder with no headings."

        let outline = KanbanCardNotesOutline(notes: notes)

        #expect(outline.leadingText == notes)
        #expect(outline.sections.isEmpty)
        #expect(!outline.hasStructuredSections)
    }

    @Test("notes outline gives repeated headings unique stable ids")
    func notesOutlineGivesRepeatedHeadingsUniqueStableIDs() {
        let outline = KanbanCardNotesOutline(notes: """
        ## Notes
        First section.

        ## Notes
        Second section.
        """)

        #expect(outline.sections.map(\.title) == ["Notes", "Notes"])
        #expect(outline.sections.map(\.id) == ["section-0", "section-1"])
        #expect(Set(outline.sections.map(\.id)).count == 2)
    }
}
