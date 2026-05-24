import Foundation
import Testing
@testable import Cider

struct KanbanCardDetailReadableLayoutPolicyTests {
    @Test("default detail layout promotes comments and hides legacy walls")
    func defaultDetailLayoutPromotesCommentsAndHidesLegacyWalls() {
        let card = KanbanCard(
            id: "readable-card",
            title: "Threaded comments polish",
            notes: """
            ## Current State
            This section is useful context but should not become the first wall in the opened card.

            ## Implementation History
            - Lots of generated legacy notes.
            """,
            aiSummary: "Make the opened card readable with comments as the primary handoff surface.",
            priority: .high,
            tags: ["kanban", "comments"],
            historyEntries: [
                KanbanCardHistoryEntry(type: .implementation, body: "Legacy history stays available.")
            ],
            comments: [
                KanbanCardComment(kind: .handoff, body: "This should be the primary readable activity.")
            ]
        )

        let policy = KanbanCardDetailReadableLayoutPolicy(card: card, statusLabel: "In Progress")

        #expect(policy.headerBadges == ["In Progress", "High", "kanban", "comments"])
        #expect(policy.shortSummary == "Make the opened card readable with comments as the primary handoff surface.")
        #expect(policy.primarySections == [.summary, .comments])
        #expect(policy.defaultCollapsedSections.contains(.legacyNotes))
        #expect(policy.defaultCollapsedSections.contains(.projectedSections))
        #expect(policy.defaultCollapsedSections.contains(.history))
        #expect(policy.defaultCollapsedSections.contains(.agentContext))
    }

    @Test("detail summary falls back to structured current state before raw notes")
    func detailSummaryFallsBackToStructuredCurrentStateBeforeRawNotes() {
        let card = KanbanCard(
            id: "summary-card",
            title: "Readable fallback",
            notes: """
            ## Current State
            Comments are visible; the top of the card needs a compact current-state summary.

            ## Raw Dump
            This should stay tucked away by default.
            """
        )

        let policy = KanbanCardDetailReadableLayoutPolicy(card: card, statusLabel: nil)

        #expect(policy.shortSummary == "Comments are visible; the top of the card needs a compact current-state summary.")
        #expect(policy.headerBadges.isEmpty)
    }
}
