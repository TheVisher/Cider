import Foundation
import Testing
@testable import Cider

struct KanbanAgentWorkflowTests {
    @Test("parent rollup derives child status and next action from board state")
    func parentRollupDerivesChildStatusAndNextActionFromBoardState() throws {
        let board = KanbanBoard(
            id: "rollup-board",
            name: "Rollup Board",
            columns: [
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "queued-child", title: "Queued child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "in_progress",
                    name: "In Progress",
                    cards: [
                        KanbanCard(id: "parent", title: "Parent card"),
                        KanbanCard(id: "active-child", title: "Active child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "failed-qa",
                            title: "Failed QA child",
                            notes: """
                            ## QA Results
                            - Step 1 failed: Button did not persist the note.
                            """,
                            parentCardID: "parent"
                        ),
                    ]
                ),
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(
                            id: "done-child",
                            title: "Done child",
                            parentCardID: "parent",
                            completed: Date(timeIntervalSince1970: 0)
                        ),
                    ]
                ),
            ]
        )

        let rollup = try #require(KanbanParentChildRollup(board: board, parentID: "parent"))

        #expect(rollup.totalChildCount == 4)
        #expect(rollup.counts.queued == 1)
        #expect(rollup.counts.inProgress == 1)
        #expect(rollup.counts.testing == 1)
        #expect(rollup.counts.done == 1)
        #expect(rollup.failedQAChild?.id == "failed-qa")
        #expect(rollup.currentGate?.id == "failed-qa")
        #expect(rollup.nextActionableChild?.id == "failed-qa")
        #expect(rollup.nextQueuedChild?.id == "queued-child")
        #expect(rollup.statusLine == "4 children: 1 queued, 1 in progress, 1 testing, 1 done.")
        #expect(rollup.nextActionLine == "Fix failed QA on Failed QA child.")
    }

    @Test("parent rollup falls through to active queued and completed children")
    func parentRollupFallsThroughToActiveQueuedAndCompletedChildren() throws {
        let board = KanbanBoard(
            id: "rollup-board",
            name: "Rollup Board",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "backlog-child", title: "Backlog child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "queued-child", title: "Queued child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(id: "done-child", title: "Done child", parentCardID: "parent", completed: Date()),
                    ]
                ),
            ]
        )

        let rollup = try #require(KanbanParentChildRollup(board: board, parentID: "parent"))

        #expect(rollup.currentGate?.id == "queued-child")
        #expect(rollup.nextActionableChild?.id == "queued-child")
        #expect(rollup.nextActionLine == "Start Queued child.")
        #expect(rollup.isComplete == false)
    }

    @Test("parent rollup marks parent complete when every child is done")
    func parentRollupMarksParentCompleteWhenEveryChildIsDone() throws {
        let board = KanbanBoard(
            id: "rollup-board",
            name: "Rollup Board",
            columns: [
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(id: "done-a", title: "Done A", parentCardID: "parent", completed: Date()),
                        KanbanCard(id: "done-b", title: "Done B", parentCardID: "parent", completed: Date()),
                    ]
                ),
            ]
        )

        let rollup = try #require(KanbanParentChildRollup(board: board, parentID: "parent"))

        #expect(rollup.isComplete)
        #expect(rollup.currentGate == nil)
        #expect(rollup.nextActionLine == "All child cards are done.")
    }

    @Test("roadmap next up projection exposes ordered sequence and insertion guidance")
    func roadmapNextUpProjectionExposesOrderedSequenceAndInsertionGuidance() throws {
        let board = KanbanBoard(
            id: "roadmap-board",
            name: "Roadmap Board",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "later-child", title: "Later child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "parent", title: "Parent roadmap"),
                        KanbanCard(id: "next-child", title: "Next child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "in_progress",
                    name: "In Progress",
                    cards: [
                        KanbanCard(id: "active-child", title: "Active child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(
                            id: "done-child",
                            title: "Done child",
                            parentCardID: "parent",
                            completed: Date(timeIntervalSince1970: 0)
                        ),
                    ]
                ),
            ]
        )

        let nextUp = try #require(KanbanRoadmapNextUpProjection(board: board, parentID: "parent"))

        #expect(nextUp.parentID == "parent")
        #expect(nextUp.sequence.map(\.id) == ["later-child", "next-child", "active-child", "done-child"])
        #expect(nextUp.sequence.map(\.stepNumber) == [1, 2, 3, 4])
        #expect(nextUp.currentGate?.id == "active-child")
        #expect(nextUp.nextActionableChild?.id == "active-child")
        #expect(nextUp.sequence[2].isCurrentGate)
        #expect(nextUp.sequence[2].isNextActionable)
        #expect(nextUp.suggestedInsertion.columnName == "Queued")
        #expect(nextUp.suggestedInsertion.parentID == "parent")
        #expect(nextUp.suggestedInsertion.command == "cider-cli board add-card \"Roadmap Board\" --column \"Queued\" --title \"<title>\" --parent parent --after next-child")
    }

    @Test("roadmap next up groups children by parent plan status")
    func roadmapNextUpGroupsChildrenByParentPlanStatus() throws {
        let board = KanbanBoard(
            id: "roadmap-board",
            name: "Roadmap Board",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "later-child", title: "Later child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "next-child", title: "Next child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "review-child", title: "Review child", parentCardID: "parent"),
                    ]
                ),
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(id: "done-child", title: "Done child", parentCardID: "parent", completed: Date()),
                    ]
                ),
            ]
        )

        let nextUp = try #require(KanbanRoadmapNextUpProjection(board: board, parentID: "parent"))

        #expect(nextUp.groups.map(\.kind) == [.currentGate, .nextUp, .later, .testingNeedsReview, .done])
        #expect(nextUp.groups.first { $0.kind == .currentGate }?.items.map(\.id) == ["review-child"])
        #expect(nextUp.groups.first { $0.kind == .nextUp }?.items.map(\.id) == ["next-child"])
        #expect(nextUp.groups.first { $0.kind == .later }?.items.map(\.id) == ["later-child"])
        #expect(nextUp.groups.first { $0.kind == .testingNeedsReview }?.items.map(\.id) == ["review-child"])
        #expect(nextUp.groups.first { $0.kind == .done }?.items.map(\.id) == ["done-child"])
    }

    @Test("agent workflow summary groups implementation testing and fix loops")
    func agentWorkflowSummaryGroupsImplementationTestingAndFixLoops() {
        let board = KanbanBoard(
            name: "Agent Workflow",
            columns: [
                KanbanColumn(
                    id: "backlog",
                    name: "Backlog",
                    cards: [
                        KanbanCard(id: "future", title: "Future card"),
                    ]
                ),
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "next", title: "Next card", priority: .high),
                    ]
                ),
                KanbanColumn(
                    id: "in_progress",
                    name: "In Progress",
                    cards: [
                        KanbanCard(id: "active", title: "Active card", agent: "codex"),
                    ]
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(id: "qa", title: "QA card", agent: "hermes"),
                    ]
                ),
                KanbanColumn(
                    id: "needs_fix",
                    name: "Needs Fix",
                    cards: [
                        KanbanCard(id: "bug", title: "Bug card", tags: ["bug"]),
                    ]
                ),
                KanbanColumn(
                    id: "done",
                    name: "Done",
                    isDoneColumn: true,
                    cards: [
                        KanbanCard(id: "done-card", title: "Done card", completed: Date(timeIntervalSince1970: 0)),
                    ]
                ),
            ]
        )

        let summary = KanbanAgentWorkflowSummary(board: board)

        #expect(summary.backlogCards.map(\.id) == ["future"])
        #expect(summary.nextImplementationCards.map(\.id) == ["next"])
        #expect(summary.activeAgentCards.map(\.id) == ["active"])
        #expect(summary.testingCards.map(\.id) == ["qa"])
        #expect(summary.needsFixCards.map(\.id) == ["bug"])
        #expect(summary.completedCards.map(\.id) == ["done-card"])
        #expect(summary.agentNames == ["codex", "hermes"])
        #expect(summary.laneSummaries.map(\.role) == [.backlog, .implementationQueue, .inProgress, .testing, .needsFix, .done])
    }

    @Test("agent workflow summary exposes approval-aware routing actions")
    func agentWorkflowSummaryExposesApprovalAwareRoutingActions() throws {
        let board = KanbanBoard(
            id: "agent-loop-board",
            name: "Agent Loop",
            columns: [
                KanbanColumn(
                    id: "queued",
                    name: "Queued",
                    cards: [
                        KanbanCard(id: "next", title: "Next implementation", priority: .high),
                    ]
                ),
                KanbanColumn(
                    id: "in_progress",
                    name: "In Progress",
                    cards: []
                ),
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "failed",
                            title: "Failed review",
                            notes: """
                            ## QA Results
                            - Step 1 failed: The review button moved the card without recording why.
                            """
                        ),
                    ]
                ),
                KanbanColumn(
                    id: "needs_fix",
                    name: "Needs Fix",
                    cards: []
                ),
            ]
        )

        let summary = KanbanAgentWorkflowSummary(board: board)

        let startAction = try #require(summary.automationActions.first { $0.cardID == "next" })
        #expect(startAction.action == .startAgent)
        #expect(startAction.requiresApproval)
        #expect(startAction.safeCommands.contains("cider-cli board move-card \"Agent Loop\" --card next --to \"In Progress\""))

        let failedReviewAction = try #require(summary.automationActions.first { $0.cardID == "failed" })
        #expect(failedReviewAction.action == .routeBackForFix)
        #expect(failedReviewAction.destinationColumnID == "needs_fix")
        #expect(failedReviewAction.reason == "Manual QA failed; route back with an explicit failed-attempt note before more implementation.")
        #expect(failedReviewAction.safeCommands.contains("cider-cli board history add \"Agent Loop\" --card failed --type failed-attempt --text \"Step 1 failed: The review button moved the card without recording why.\" --source reviewer"))
        #expect(failedReviewAction.safeCommands.contains("cider-cli board move-card \"Agent Loop\" --card failed --to \"Needs Fix\""))
    }

    @Test("testing triage separates Erik manual QA from agent-verifiable cards")
    func testingTriageSeparatesManualAndAgentVerification() {
        let board = KanbanBoard(
            id: "triage-board",
            name: "Triage Board",
            columns: [
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "visual",
                            title: "Sidebar drag polish",
                            notes: """
                            ## Test Evidence
                            - swift test --filter SidebarTests passed.

                            ## Manual QA Guidance
                            - Drag the sidebar divider and confirm it feels smooth.
                            - Relaunch the app and confirm the width persists.
                            """,
                            priority: .high
                        ),
                        KanbanCard(
                            id: "cli",
                            title: "Board JSON smoke",
                            notes: """
                            ## Test Evidence
                            - cider-cli board show 2afee0 --json returns valid JSON.
                            - swift test --filter BoardCLITests passed.
                            """
                        ),
                        KanbanCard(
                            id: "unknown",
                            title: "Unclear QA card",
                            notes: "Needs a closer look."
                        ),
                    ]
                ),
                KanbanColumn(
                    id: "ready_to_test",
                    name: "Ready to Test",
                    cards: [
                        KanbanCard(
                            id: "manual-only",
                            title: "Dashboard visual pass",
                            notes: "Manual QA: Open the dashboard and confirm the cards feel balanced."
                        ),
                    ]
                ),
            ]
        )

        let summary = KanbanTestingTriageSummary(board: board)

        #expect(summary.items.map(\.id) == ["visual", "cli", "unknown", "manual-only"])
        #expect(summary.mixed.map(\.id) == ["visual", "unknown"])
        #expect(summary.agentCanVerify.map(\.id) == ["cli"])
        #expect(summary.needsErik.map(\.id) == ["manual-only"])
        #expect(summary.items.first(where: { $0.id == "visual" })?.manualQASteps.count == 2)
    }

    @Test("testing triage extracts what changed test evidence and agent verification handoff")
    func testingTriageExtractsHandoffContext() {
        let board = KanbanBoard(
            id: "handoff-board",
            name: "Handoff Board",
            columns: [
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "ready",
                            title: "Ready to Test handoff card",
                            notes: """
                            ## What Changed
                            - Added a visible Testing summary panel.
                            - Preserved existing card history while editing notes.

                            ## Test Evidence
                            - swift test --filter KanbanAgentWorkflowTests passed.
                            - cider-cli board testing-summary 2afee0 --json parsed successfully.

                            ## Agent Verification
                            - Re-run the focused Swift test.
                            - Re-run the JSON CLI smoke.

                            ## Manual QA Guidance
                            - Open the card detail and confirm the Testing section is readable.
                            """
                        ),
                    ]
                ),
            ]
        )

        let item = KanbanTestingTriageSummary(board: board).items[0]

        #expect(item.whatChanged == [
            "Added a visible Testing summary panel.",
            "Preserved existing card history while editing notes.",
        ])
        #expect(item.testEvidence == [
            "swift test --filter KanbanAgentWorkflowTests passed.",
            "cider-cli board testing-summary 2afee0 --json parsed successfully.",
        ])
        #expect(item.agentVerificationSteps == [
            "Re-run the focused Swift test.",
            "Re-run the JSON CLI smoke.",
        ])
        #expect(item.manualQASteps == ["Open the card detail and confirm the Testing section is readable."])
    }

    @Test("testing triage exposes failed manual QA as agent review work")
    func testingTriageExposesFailedManualQAAsAgentReviewWork() {
        let board = KanbanBoard(
            id: "qa-results-board",
            name: "QA Results Board",
            columns: [
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "failed",
                            title: "Review queue action polish",
                            notes: """
                            ## Manual QA Guidance
                            - Click Enrich and route from the Review Queue.

                            ## QA Results
                            - Step 1 failed: Click Enrich and route from the Review Queue. Note: It only opened the slideout.
                            """
                        ),
                    ]
                ),
            ]
        )

        let item = KanbanTestingTriageSummary(board: board).items[0]

        #expect(item.owner == .agentCanVerify)
        #expect(item.failedQASteps == [
            "Step 1 failed: Click Enrich and route from the Review Queue. Note: It only opened the slideout.",
        ])
        #expect(item.reason == "Manual QA failed; an agent should inspect and fix before asking Erik to retest.")
    }

    @Test("testing triage ignores passed QA steps whose instructions mention failure")
    func testingTriageIgnoresPassedQAStepsWhoseInstructionsMentionFailure() {
        let board = KanbanBoard(
            id: "qa-results-board",
            name: "QA Results Board",
            columns: [
                KanbanColumn(
                    id: "testing",
                    name: "Testing",
                    cards: [
                        KanbanCard(
                            id: "passed",
                            title: "QA companion polish",
                            notes: """
                            ## Test Evidence
                            - swift test --filter KanbanAgentWorkflowTests passed.

                            ## QA Results
                            - Step 1 passed: Confirm failed rows can be cleared.
                            - Step 2 passed: After recording a failed step, inspect testing summary.
                            """
                        ),
                    ]
                ),
            ]
        )

        let item = KanbanTestingTriageSummary(board: board).items[0]

        #expect(item.owner == .mixed)
        #expect(item.failedQASteps.isEmpty)
        #expect(item.reason != "Manual QA failed; an agent should inspect and fix before asking Erik to retest.")
    }
}
