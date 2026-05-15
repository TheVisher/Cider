import Foundation
import Testing
@testable import Cider

struct KanbanAgentWorkflowTests {
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
}
