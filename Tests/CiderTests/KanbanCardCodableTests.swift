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
}
