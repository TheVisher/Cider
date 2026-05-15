import Testing
@testable import Cider

struct KanbanCardQualityChecklistTests {
    @Test("quality checklist recognizes common agent-ready sections")
    func recognizesCommonAgentReadySections() {
        let notes = """
        Problem:
        The agent does not know what to fix.

        Goal:
        Make the card self-contained.

        MVP scope:
        Add deterministic checks.

        Acceptance criteria:
        - Shows readiness.

        Test evidence:
        - swift test passes.

        Manual QA guidance:
        - Open card detail.
        """

        let report = KanbanCardQualityReport(notes: notes)

        #expect(report.status == .ready)
        #expect(report.presentEssentials.map(\.section) == [.problem, .goal, .acceptanceCriteria])
        #expect(report.missingEssentials.isEmpty)
        #expect(report.presentRecommended.map(\.section).contains(.testEvidence))
        #expect(report.presentRecommended.map(\.section).contains(.manualQAGuidance))
    }

    @Test("quality checklist flags missing essentials without blocking cards")
    func flagsMissingEssentialsWithoutBlockingCards() {
        let report = KanbanCardQualityReport(notes: "Quick idea with no structured handoff yet.")

        #expect(report.status == .needsContext)
        #expect(report.missingEssentials.map(\.section) == [.problem, .goal, .acceptanceCriteria])
        #expect(report.summary == "Needs context: Problem, Goal, Acceptance criteria")
    }

    @Test("quality checklist accepts markdown headings and alternate labels")
    func acceptsMarkdownHeadingsAndAlternateLabels() {
        let notes = """
        ## Issue
        Cards are hard to hand off.

        ## Desired outcome
        Agents know what done means.

        ## Acceptance Criteria
        - Checklist detects this.

        ## Follow-up
        Later polish.
        """

        let report = KanbanCardQualityReport(notes: notes)

        #expect(report.status == .ready)
        #expect(report.presentEssentials.map(\.section) == [.problem, .goal, .acceptanceCriteria])
        #expect(report.presentRecommended.map(\.section) == [.followUp])
    }
}
