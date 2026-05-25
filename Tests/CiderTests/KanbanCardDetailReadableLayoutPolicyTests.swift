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

    @Test("comment threads group replies under chronological roots")
    func commentThreadsGroupRepliesUnderChronologicalRoots() {
        let start = Date(timeIntervalSince1970: 1_000)
        let root = KanbanCardComment(id: "root", kind: .note, body: "Root", createdAt: start)
        let secondRoot = KanbanCardComment(id: "second", kind: .qa, body: "Second", createdAt: start.addingTimeInterval(3))
        let reply = KanbanCardComment(id: "reply", kind: .note, body: "Reply", createdAt: start.addingTimeInterval(2), parentCommentID: "root")

        let threads = KanbanCardCommentThreadPolicy.threads(from: [secondRoot, reply, root])

        #expect(threads.map(\.root.id) == ["root", "second"])
        #expect(threads.first?.replies.map(\.id) == ["reply"])
        #expect(threads.last?.replies.isEmpty == true)
    }

    @Test("comment display threads preserve root creation order while resolved threads collapse in place")
    func commentDisplayThreadsPreserveRootCreationOrderWhileResolvedThreadsCollapseInPlace() {
        let start = Date(timeIntervalSince1970: 1_000)
        let oldActive = KanbanCardComment(id: "old-active", kind: .note, body: "Older active", createdAt: start)
        let resolved = KanbanCardComment(
            id: "resolved",
            kind: .qa,
            body: "Resolved QA",
            createdAt: start.addingTimeInterval(10),
            resolvedAt: start.addingTimeInterval(20),
            resolvedBy: "Erik"
        )
        let recentActive = KanbanCardComment(id: "recent-active", kind: .handoff, body: "Recent active", createdAt: start.addingTimeInterval(30))
        let reply = KanbanCardComment(id: "reply", kind: .note, body: "Reply does not reorder the root thread", createdAt: start.addingTimeInterval(40), parentCommentID: "old-active")

        let threads = KanbanCardCommentThreadPolicy.displayThreads(from: [resolved, recentActive, oldActive, reply])
        let counts = KanbanCardCommentThreadPolicy.threadCounts(from: [resolved, recentActive, oldActive, reply])

        #expect(threads.map(\.root.id) == ["old-active", "resolved", "recent-active"])
        #expect(KanbanCardCommentThreadPolicy.defaultCollapsedThreadIDs(from: [resolved, recentActive, oldActive, reply]) == Set(["resolved"]))
        #expect(counts.active == 2)
        #expect(counts.resolved == 1)
    }

    @Test("comment composer uses account display name instead of generic human")
    func commentComposerUsesAccountDisplayNameInsteadOfGenericHuman() {
        let name = KanbanCardCommentThreadPolicy.defaultAuthorName(
            accountEmail: "visher@example.com",
            fullUserName: "Human",
            userName: "human"
        )

        #expect(name == "Visher")
    }

    @Test("comment body display trims blank wrappers without hiding real text")
    func commentBodyDisplayTrimsBlankWrappersWithoutHidingRealText() {
        let lines = KanbanCardCommentThreadPolicy.displayBodyLines(for: "\n\nThis is the note I wrote.\n")

        #expect(lines == ["This is the note I wrote."])
        #expect(KanbanCardCommentThreadPolicy.displayBodyLines(for: "   ").isEmpty)
    }
}
