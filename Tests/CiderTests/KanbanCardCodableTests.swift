import Foundation
import Testing
@testable import Cider

struct KanbanCardCodableTests {
    @Test("card linked entities round trip through codable storage")
    func linkedEntitiesRoundTripThroughCodableStorage() throws {
        let ref = LibraryEntityRef(type: .note, entityID: UUID())
        let card = KanbanCard(
            id: "card-linked",
            title: "Card with spec",
            linkedEntities: [ref]
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.linkedEntities == [ref])
    }

    @Test("legacy cards without linked entities decode with empty links")
    func legacyCardsWithoutLinkedEntitiesDecodeWithEmptyLinks() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.linkedEntities.isEmpty)
    }

    @Test("card parent id round trips through codable storage")
    func parentCardIDRoundTripsThroughCodableStorage() throws {
        let card = KanbanCard(
            id: "child-card",
            title: "Child",
            parentCardID: "parent-card"
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.parentCardID == "parent-card")
    }

    @Test("legacy cards without parent id decode with nil parent")
    func legacyCardsWithoutParentIDDecodeWithNilParent() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.parentCardID == nil)
    }

    @Test("card related card ids round trip through codable storage")
    func relatedCardIDsRoundTripThroughCodableStorage() throws {
        let card = KanbanCard(
            id: "card-with-history",
            title: "Follow-up fix",
            relatedCardIDs: ["old-card", "bug-card"]
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.relatedCardIDs == ["old-card", "bug-card"])
    }

    @Test("legacy cards without related card ids decode with empty references")
    func legacyCardsWithoutRelatedCardIDsDecodeWithEmptyReferences() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.relatedCardIDs.isEmpty)
    }

    @Test("card AI summary round trips through codable storage")
    func cardAISummaryRoundTripsThroughCodableStorage() throws {
        let card = KanbanCard(
            id: "card-with-summary",
            title: "Generated preview",
            aiSummary: "A concise generated board preview."
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.aiSummary == "A concise generated board preview.")
    }

    @Test("legacy cards without AI summary decode with nil summary")
    func legacyCardsWithoutAISummaryDecodeWithNilSummary() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.aiSummary == nil)
    }

    @Test("card review timestamp round trips through codable storage")
    func cardReviewTimestampRoundTripsThroughCodableStorage() throws {
        let reviewedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let card = KanbanCard(
            id: "reviewed-card",
            title: "Reviewed",
            reviewedAt: reviewedAt
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.reviewedAt == reviewedAt)
    }

    @Test("legacy cards without review timestamp decode with nil review timestamp")
    func legacyCardsWithoutReviewTimestampDecodeWithNilReviewTimestamp() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.reviewedAt == nil)
    }

    @Test("card history entries round trip through codable storage")
    func cardHistoryEntriesRoundTripThroughCodableStorage() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let card = KanbanCard(
            id: "card-with-history",
            title: "Fix regression",
            historyEntries: [
                KanbanCardHistoryEntry(
                    id: "history-1",
                    type: .implementation,
                    body: "Added the visible dashboard history section.",
                    author: "Codex",
                    createdAt: createdAt
                ),
                KanbanCardHistoryEntry(
                    id: "history-2",
                    type: .decision,
                    body: "Keep history below What To Test.",
                    author: "Codex",
                    createdAt: createdAt
                ),
                KanbanCardHistoryEntry(
                    id: "history-3",
                    type: .handoff,
                    body: "Reopen the card and verify the entry persists.",
                    author: "Codex",
                    createdAt: createdAt
                ),
            ]
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.historyEntries.count == 3)
        #expect(decoded.historyEntries.map(\.type) == [.implementation, .decision, .handoff])
        #expect(decoded.historyEntries.first?.body == "Added the visible dashboard history section.")
        #expect(decoded.historyEntries.first?.author == "Codex")
        #expect(decoded.historyEntries.first?.createdAt == createdAt)
    }

    @Test("legacy cards without history entries decode with empty history")
    func legacyCardsWithoutHistoryEntriesDecodeWithEmptyHistory() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.historyEntries.isEmpty)
    }

    @Test("card comments round trip with metadata, categories, and replies")
    func cardCommentsRoundTripWithMetadataCategoriesAndReplies() throws {
        let createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        let root = KanbanCardComment(
            id: "comment-root",
            kind: .handoff,
            body: "Cody handoff for the next agent.",
            author: "Cody",
            source: "discord:cody-chat",
            createdAt: createdAt
        )
        let reply = KanbanCardComment(
            id: "comment-reply",
            kind: .qa,
            body: "- [x] QA verified the persisted handoff.",
            author: "Erik",
            source: "cider-ui",
            createdAt: createdAt.addingTimeInterval(60),
            parentCommentID: root.id,
            resolvedAt: createdAt.addingTimeInterval(120),
            resolvedBy: "Erik"
        )
        let card = KanbanCard(
            id: "comment-card",
            title: "Threaded comments",
            comments: [root, reply]
        )

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(KanbanCard.self, from: data)

        #expect(decoded.comments.map(\.id) == ["comment-root", "comment-reply"])
        #expect(decoded.comments.map(\.kind) == [.handoff, .qa])
        #expect(decoded.comments.first?.source == "discord:cody-chat")
        #expect(decoded.comments.last?.parentCommentID == "comment-root")
        #expect(decoded.comments.last?.body == "- [x] QA verified the persisted handoff.")
        #expect(decoded.comments.last?.resolvedAt == createdAt.addingTimeInterval(120))
        #expect(decoded.comments.last?.resolvedBy == "Erik")
        #expect(decoded.comments.last?.isResolved == true)
        #expect(decoded.comments.first?.permalinkID == "comment-root")
    }

    @Test("legacy cards without comments decode with empty comments")
    func legacyCardsWithoutCommentsDecodeWithEmptyComments() throws {
        let json = """
        {
          "id": "legacy-card",
          "title": "Legacy Kanban Card",
          "created": "2026-05-02"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))

        #expect(decoded.comments.isEmpty)
    }

    @Test("date-only created values preserve local Pacific calendar day")
    func dateOnlyCreatedValuesPreserveLocalPacificCalendarDay() throws {
        let originalTimeZone = NSTimeZone.default
        let pacific = try #require(TimeZone(identifier: "America/Los_Angeles"))
        NSTimeZone.default = pacific
        defer { NSTimeZone.default = originalTimeZone }

        let json = """
        {
          "id": "date-only-card",
          "title": "Date-only card",
          "created": "2026-05-09"
        }
        """

        let decoded = try JSONDecoder().decode(KanbanCard.self, from: Data(json.utf8))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let components = calendar.dateComponents([.year, .month, .day], from: decoded.created)

        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 9)
    }
}
