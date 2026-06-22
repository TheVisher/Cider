import Testing
@testable import Cider

struct KanbanCardQualityChecklistTests {
    @Test("structure hints recognize common agent-ready sections")
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

    @Test("structure hints flags missing essentials without blocking cards")
    func flagsMissingEssentialsWithoutBlockingCards() {
        let report = KanbanCardQualityReport(notes: "Quick idea with no structured handoff yet.")

        #expect(report.status == .needsContext)
        #expect(report.missingEssentials.map(\.section) == [.currentState, .problem, .goal, .mvpScope, .nextStep, .acceptanceCriteria])
        #expect(report.summary == "Needs context: Current State, Problem, Goal, MVP scope, Next Step, Acceptance criteria")
    }

    @Test("structure hints accepts markdown headings and alternate labels")
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

    @Test("structure hints align agent-ready status with dashboard core handoff sections")
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

    @Test("dashboard readiness surface has deterministic title slot and checks")
    func dashboardReadinessSurfaceHasDeterministicTitleSlotAndChecks() {
        let model = KanbanCardDashboardModel(
            title: "Make cards agent-ready",
            notes: """
            What To Test:
            - Open the card detail dashboard.

            Problem:
            Agents need deterministic readiness hints.

            Goal:
            Make readiness easy to verify.

            MVP scope:
            Surface Structure Hints.

            Current State:
            Ready for focused implementation.

            Next Step:
            Run the focused tests.

            Acceptance criteria:
            - The readiness surface is named and positioned.
            """
        )

        #expect(model.readinessSurface.title == "Structure Hints")
        #expect(model.readinessSurface.dashboardSlot == "Below What To Test and above Problem")
        #expect(model.readinessSurface.summary == "Agent-ready context present")
        #expect(model.readinessSurface.missingChecks.isEmpty)
        #expect(model.readinessSurface.presentChecks == [
            "Current State",
            "Problem",
            "Goal",
            "MVP scope",
            "Next Step",
            "Acceptance criteria",
            "Manual QA guidance",
        ])
    }

    @Test("weak cards project more structure needs than strong cards")
    func weakCardsProjectMoreStructureNeedsThanStrongCards() {
        let weak = KanbanCardDashboardModel(
            title: "Loose idea",
            notes: "Maybe improve cards someday."
        )
        let strong = KanbanCardDashboardModel(
            title: "Structured implementation card",
            notes: """
            Problem:
            Card details are ambiguous.

            Goal:
            Make the dashboard deterministic.

            MVP scope:
            Use existing Structure Hints.

            Current State:
            Ready to implement.

            Next Step:
            Add tests.

            Acceptance criteria:
            - Weak cards expose more needs-work context.

            What To Test:
            - Compare weak and strong card dashboards.
            """
        )

        #expect(weak.readinessSurface.status == .needsContext)
        #expect(strong.readinessSurface.status == .ready)
        #expect(weak.readinessSurface.missingChecks.count > strong.readinessSurface.missingChecks.count)
        #expect(weak.readinessSurface.needsWorkChecks.count > strong.readinessSurface.needsWorkChecks.count)
        #expect(weak.readinessSurface.needsWorkChecks.contains("Problem"))
        #expect(strong.readinessSurface.needsWorkChecks.isEmpty)
    }
}
