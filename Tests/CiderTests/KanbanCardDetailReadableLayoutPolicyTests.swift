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

    @Test("resolved thread summary names the resolver")
    func resolvedThreadSummaryNamesTheResolver() {
        let resolved = KanbanCardComment(
            id: "resolved",
            kind: .qa,
            body: "Resolved QA",
            createdAt: Date(timeIntervalSince1970: 1_000),
            resolvedAt: Date(timeIntervalSince1970: 1_100),
            resolvedBy: "brian"
        )
        let missingResolver = KanbanCardComment(
            id: "missing-resolver",
            kind: .note,
            body: "Resolved without an actor",
            createdAt: Date(timeIntervalSince1970: 1_000),
            resolvedAt: Date(timeIntervalSince1970: 1_100)
        )

        #expect(KanbanCardCommentThreadPolicy.resolvedSummaryText(for: resolved) == "brian resolved the thread")
        #expect(KanbanCardCommentThreadPolicy.resolvedSummaryText(for: missingResolver) == "Someone resolved the thread")
    }

    @Test("comment bodies expose URL and image references")
    func commentBodiesExposeURLAndImageReferences() {
        let links = KanbanCardCommentThreadPolicy.referenceLinks(
            in: """
            Research: [Linear docs](https://linear.app/docs/comments).
            Inspiration: ![thread screenshot](https://example.com/thread.png)
            Duplicate bare URL should not duplicate: https://linear.app/docs/comments
            Trailing punctuation: https://example.com/ref?x=1.
            """
        )

        #expect(links.map(\.url.absoluteString) == [
            "https://linear.app/docs/comments",
            "https://example.com/thread.png",
            "https://example.com/ref?x=1"
        ])
        #expect(links.map(\.kind) == [.link, .image, .link])
        #expect(links.first?.displayTitle == "Linear docs")
        #expect(links[1].displayTitle == "thread screenshot")
    }

    @Test("comment body display trims blank wrappers without hiding real text")
    func commentBodyDisplayTrimsBlankWrappersWithoutHidingRealText() {
        let lines = KanbanCardCommentThreadPolicy.displayBodyLines(for: "\n\nThis is the note I wrote.\n")

        #expect(lines == ["This is the note I wrote."])
        #expect(KanbanCardCommentThreadPolicy.displayBodyLines(for: "   ").isEmpty)
    }

    @Test("comment checklist lines toggle by visible line while preserving text")
    func commentChecklistLinesToggleByVisibleLineWhilePreservingText() throws {
        let body = """
        Testing:
        - [ ] Verify narrow header
        - [x] Confirm inspector still opens
        """

        let checked = try #require(KanbanCardCommentThreadPolicy.toggledChecklistBody(body, lineIndex: 1))
        #expect(checked.contains("- [x] Verify narrow header"))
        #expect(checked.contains("- [x] Confirm inspector still opens"))

        let unchecked = try #require(KanbanCardCommentThreadPolicy.toggledChecklistBody(checked, lineIndex: 2))
        #expect(unchecked.contains("- [x] Verify narrow header"))
        #expect(unchecked.contains("- [ ] Confirm inspector still opens"))
        #expect(KanbanCardCommentThreadPolicy.toggledChecklistBody(body, lineIndex: 0) == nil)
    }

    @Test("testing checklist comments resolve only after every item is checked")
    func testingChecklistCommentsResolveOnlyAfterEveryItemIsChecked() {
        let incomplete = KanbanCardComment(
            id: "qa-comment",
            kind: .qa,
            body: """
            - [x] Build passes
            - [ ] Visual QA passes
            """
        )
        let complete = KanbanCardComment(
            id: "qa-comment",
            kind: .qa,
            body: """
            - [x] Build passes
            - [x] Visual QA passes
            """
        )
        let note = KanbanCardComment(kind: .note, body: "- [x] A normal note is not a testing checklist")

        #expect(KanbanCardCommentThreadPolicy.canResolveTestingChecklist(incomplete) == false)
        #expect(KanbanCardCommentThreadPolicy.canResolveTestingChecklist(complete) == true)
        #expect(KanbanCardCommentThreadPolicy.canResolveTestingChecklist(note) == false)
    }

    @Test("checklist failure replies carry an item anchor and quote")
    func checklistFailureRepliesCarryAnItemAnchorAndQuote() throws {
        let comment = KanbanCardComment(
            id: "qa-comment",
            kind: .qa,
            body: """
            - [x] Build passes
            - [ ] Visual QA passes
            """
        )
        let item = try #require(KanbanCardCommentThreadPolicy.checklistItems(in: comment).last)

        let reply = KanbanCardCommentThreadPolicy.failureReply(
            to: comment,
            checklistItem: item,
            author: "Visher",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )

        #expect(reply.parentCommentID == "qa-comment")
        #expect(reply.parentChecklistItemAnchor == "qa-comment#checklist-2")
        #expect(reply.quotedChecklistItem == "Visual QA passes")
        #expect(reply.body.hasPrefix("> - [ ] Visual QA passes"))
        #expect(reply.body.hasSuffix("Failed because:\n"))

        let quote = try #require(KanbanCardCommentThreadPolicy.quotedLine("> - [ ] Visual QA passes"))
        let quotedChecklist = try #require(KanbanCardCommentThreadPolicy.checklistLineContent(quote.content))
        #expect(quotedChecklist.text == "Visual QA passes")
        #expect(quotedChecklist.isChecked == false)
    }
}
