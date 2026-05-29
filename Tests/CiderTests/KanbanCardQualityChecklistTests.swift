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

        Current State:
        The card is ready for implementation.

        MVP scope:
        Add deterministic checks.

        Next Step:
        Run the checklist test.

        Acceptance criteria:
        - Shows readiness.

        Test evidence:
        - swift test passes.

        Manual QA guidance:
        - Open card detail.
        """

        let report = KanbanCardQualityReport(notes: notes)

        #expect(report.status == .ready)
        #expect(report.presentEssentials.map(\.section) == [.currentState, .problem, .goal, .mvpScope, .nextStep, .acceptanceCriteria])
        #expect(report.missingEssentials.isEmpty)
        #expect(report.presentRecommended.map(\.section).contains(.testEvidence))
        #expect(report.presentRecommended.map(\.section).contains(.manualQAGuidance))
    }

    @Test("quality checklist flags missing essentials without blocking cards")
    func flagsMissingEssentialsWithoutBlockingCards() {
        let report = KanbanCardQualityReport(notes: "Quick idea with no structured handoff yet.")

        #expect(report.status == .needsContext)
        #expect(report.missingEssentials.map(\.section) == [.currentState, .problem, .goal, .mvpScope, .nextStep, .acceptanceCriteria])
        #expect(report.summary == "Needs context: Current State, Problem, Goal, MVP scope, Next Step, Acceptance criteria")
    }

    @Test("quality checklist accepts markdown headings and alternate labels")
    func acceptsMarkdownHeadingsAndAlternateLabels() {
        let notes = """
        ## Issue
        Cards are hard to hand off.

        ## Desired outcome
        Agents know what done means.

        ## Status
        Ready to verify alternate labels.

        ## Scope
        Quality checklist only.

        ## Handoff
        Run the focused test.

        ## Acceptance Criteria
        - Checklist detects this.

        ## Follow-up
        Later polish.
        """

        let report = KanbanCardQualityReport(notes: notes)

        #expect(report.status == .ready)
        #expect(report.presentEssentials.map(\.section) == [.currentState, .problem, .goal, .mvpScope, .nextStep, .acceptanceCriteria])
        #expect(report.presentRecommended.map(\.section) == [.followUp])
    }

    @Test("quality checklist aligns agent-ready status with dashboard core handoff sections")
    func alignsAgentReadyStatusWithDashboardCoreHandoffSections() {
        let notes = """
        Problem:
        Dashboard and checklist disagree.

        Goal:
        Use one definition of handoff-ready.

        MVP scope:
        Make the checklist stricter.

        Acceptance criteria:
        - Missing handoff sections keep the advisory status out of ready.
        """

        let report = KanbanCardQualityReport(notes: notes)

        #expect(report.status == .needsContext)
        #expect(report.missingEssentials.map(\.section) == [.currentState, .nextStep])
        #expect(report.summary == "Needs context: Current State, Next Step")
    }
}
