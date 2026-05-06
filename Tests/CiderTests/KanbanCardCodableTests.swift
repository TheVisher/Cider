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
}
