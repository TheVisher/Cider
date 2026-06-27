import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

struct LibraryHubFacetPresentationTests {
    @Test("facet presentation exposes WoW game chips and read-only open hub actions")
    @MainActor
    func facetPresentationExposesGameChipsAndReadOnlyOpenHubActions() throws {
        let anchorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let hub = makeHub(
            itemID: anchorID,
            title: "World of Warcraft Hub",
            facets: [
                CiderLibraryHubDomainFacet(
                    kind: "domain",
                    key: "games",
                    displayValue: "Games",
                    confidenceLabel: "source_backed",
                    source: "test.accepted-link",
                    evidence: "World of Warcraft source.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"]
                ),
                CiderLibraryHubDomainFacet(
                    kind: "entity_type",
                    key: "game",
                    displayValue: "Game",
                    confidenceLabel: "source_backed",
                    source: "test.accepted-link",
                    evidence: "World of Warcraft source.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"]
                ),
                CiderLibraryHubDomainFacet(
                    kind: "alias",
                    key: "wow",
                    displayValue: "WoW",
                    confidenceLabel: "inferred",
                    source: "known_safe_alias",
                    evidence: "World of Warcraft Hub",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"]
                ),
            ],
            safeNextCommands: [
                "cider-cli item hub bookmark \(anchorID.uuidString) --json",
                "cider-cli item hub --query \"WoW\" --limit 5 --json",
            ]
        )

        let presentation = LibraryHubFacetPresentationModel(hub: hub)

        #expect(presentation.chips.map(\.label) == ["Games", "Game", "WoW"])
        #expect(presentation.chips.map(\.accessibilityLabel).contains("Alias facet WoW, inferred"))
        #expect(presentation.chips.allSatisfy { $0.truthBoundary == "interpretive_metadata_not_accepted_truth" })
        #expect(presentation.openHubActions.map(\.label) == ["Open hub", "Open WoW hub"])
        #expect(presentation.openHubActions.allSatisfy { $0.readOnly })
        #expect(presentation.openHubActions.allSatisfy { !$0.promotesTruth })
        #expect(presentation.openHubActions[0].command == "cider-cli item hub bookmark \(anchorID.uuidString) --json")

        let dict = CiderCLI.libraryHubReadModelToDict(hub)
        let hubDict = try #require(dict["hub"] as? [String: Any])
        let presentationDict = try #require(hubDict["presentation"] as? [String: Any])
        let chipDicts = try #require(presentationDict["chips"] as? [[String: Any]])
        let actionDicts = try #require(presentationDict["openHubActions"] as? [[String: Any]])
        #expect(chipDicts.map { $0["label"] as? String } == ["Games", "Game", "WoW"])
        #expect(actionDicts.first?["readOnly"] as? Bool == true)
        #expect(actionDicts.first?["promotesTruth"] as? Bool == false)
    }

    @Test("facet presentation orders media restaurant and place chips for calm rendering")
    func facetPresentationOrdersMediaRestaurantAndPlaceChips() {
        let anchorID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let restaurantID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let hub = makeHub(
            itemID: anchorID,
            title: "The Way Way Back movie",
            facets: [
                CiderLibraryHubDomainFacet(
                    kind: "place",
                    key: "tacoma",
                    displayValue: "Tacoma",
                    confidenceLabel: "inferred",
                    source: "title_path",
                    evidence: "Cactus Tacoma dinner notes",
                    itemRefs: ["note:\(restaurantID.uuidString)"]
                ),
                CiderLibraryHubDomainFacet(
                    kind: "entity_type",
                    key: "restaurant",
                    displayValue: "Restaurant",
                    confidenceLabel: "source_backed",
                    source: "test.graph-candidate",
                    evidence: "We went to Cactus in Tacoma.",
                    itemRefs: ["note:\(restaurantID.uuidString)"]
                ),
                CiderLibraryHubDomainFacet(
                    kind: "domain",
                    key: "media",
                    displayValue: "Media",
                    confidenceLabel: "inferred",
                    source: "title_path",
                    evidence: "The Way Way Back movie",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"]
                ),
                CiderLibraryHubDomainFacet(
                    kind: "entity_type",
                    key: "movie",
                    displayValue: "Movie",
                    confidenceLabel: "source_backed",
                    source: "test.graph-candidate",
                    evidence: "I watched The Way Way Back last night.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"]
                ),
            ],
            safeNextCommands: [
                "cider-cli item hub bookmark \(anchorID.uuidString) --json",
                "cider-cli item hub --query \"The Way Way Back movie\" --limit 5 --json",
                "cider-cli item hub --query \"Cactus Tacoma dinner notes\" --limit 5 --json",
            ]
        )

        let presentation = LibraryHubFacetPresentationModel(hub: hub)

        #expect(presentation.chips.map(\.label) == ["Media", "Movie", "Restaurant", "Tacoma"])
        #expect(presentation.chips.map(\.role) == [.domain, .entityType, .entityType, .place])
        #expect(presentation.openHubActions.map(\.label) == [
            "Open hub",
            "Open The Way Way Back movie hub",
            "Open Cactus Tacoma dinner notes hub",
        ])
        #expect(presentation.truthBoundary.domainFacetsAreTruth == false)
        #expect(presentation.truthBoundary.autoMutatedUserFields == false)
    }

    @Test("facet presentation serializes chips actions and truth boundary")
    func facetPresentationSerializesChipsActionsAndTruthBoundary() throws {
        let anchorID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let hub = makeHub(
            itemID: anchorID,
            title: "Cactus Tacoma",
            facets: [
                CiderLibraryHubDomainFacet(
                    kind: "domain",
                    key: "restaurants",
                    displayValue: "Restaurants",
                    confidenceLabel: "source_backed",
                    source: "test.graph-candidate",
                    evidence: "We went to Cactus in Tacoma.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"]
                ),
            ],
            safeNextCommands: [
                "cider-cli item hub bookmark \(anchorID.uuidString) --json",
            ]
        )
        let presentation = LibraryHubFacetPresentationModel(hub: hub)

        let encoded = try JSONEncoder().encode(presentation)
        let decoded = try JSONDecoder().decode(LibraryHubFacetPresentationModel.self, from: encoded)

        #expect(decoded.title == "Cactus Tacoma")
        #expect(decoded.chips.first?.role == .domain)
        #expect(decoded.openHubActions.first?.readOnly == true)
        #expect(decoded.truthBoundary.domainFacetsAreTruth == false)
    }

    private func makeHub(
        itemID: UUID,
        title: String,
        facets: [CiderLibraryHubDomainFacet],
        safeNextCommands: [String]
    ) -> CiderLibraryHubReadModel {
        let item = CiderItemSummary(
            id: itemID,
            type: .bookmark,
            title: title,
            relativePath: nil,
            folderID: nil,
            createdAt: Date(timeIntervalSince1970: 1_767_001_000),
            updatedAt: Date(timeIntervalSince1970: 1_767_001_100)
        )
        let owner = SecondBrainOwnerRef(ownerType: "bookmark", ownerID: itemID.uuidString)
        let bundle = CiderItemContextBundle(
            item: item,
            owner: owner,
            sections: [],
            chunks: [],
            related: [],
            ownerRelations: [],
            backlinks: [],
            spaceMemberships: [],
            routingDecisions: [],
            agentActions: [],
            actionReceipts: [],
            enrichmentOutputs: [],
            relationCandidates: [],
            captureProvenance: []
        )
        return CiderLibraryHubReadModel(
            anchor: bundle,
            relatedItems: [],
            groups: [],
            domainFacets: facets,
            reviewableCandidates: [],
            safeNextCommands: safeNextCommands
        )
    }
}
