import Foundation
import Testing
@testable import Cider

struct LibraryHubFacetChipRowModelTests {
    @Test("chip row model keeps source backed facet copy and disables hub actions without a safe bridge")
    func chipRowModelKeepsTruthBoundaryAndDisabledActions() {
        let anchorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let presentation = LibraryHubFacetPresentationModel(hub: makeHub(
            itemID: anchorID,
            title: "World of Warcraft Hub",
            facets: [
                LibraryHubFacetPresentationModel.Chip(
                    id: "domain:games",
                    role: .domain,
                    label: "Games",
                    confidenceLabel: "source_backed",
                    source: "test.accepted-link",
                    evidence: "World of Warcraft source.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"],
                    truthBoundary: "interpretive_metadata_not_accepted_truth"
                ).domainFacet,
                LibraryHubFacetPresentationModel.Chip(
                    id: "entity_type:game",
                    role: .entityType,
                    label: "Game",
                    confidenceLabel: "source_backed",
                    source: "test.accepted-link",
                    evidence: "World of Warcraft source.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"],
                    truthBoundary: "interpretive_metadata_not_accepted_truth"
                ).domainFacet,
                LibraryHubFacetPresentationModel.Chip(
                    id: "alias:wow",
                    role: .alias,
                    label: "WoW",
                    confidenceLabel: "inferred",
                    source: "known_safe_alias",
                    evidence: "World of Warcraft Hub",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"],
                    truthBoundary: "interpretive_metadata_not_accepted_truth"
                ).domainFacet,
            ],
            safeNextCommands: [
                "cider-cli item hub bookmark \(anchorID.uuidString) --json",
            ]
        ))

        let model = LibraryHubFacetChipRowModel(
            presentation: presentation,
            supportsOpenHubActions: false
        )

        #expect(model.isVisible)
        #expect(model.title == "Source-backed hints")
        #expect(model.subtitle == "Interpretive metadata, not accepted truth.")
        #expect(model.chips.map(\.label) == ["Games", "Game", "WoW"])
        #expect(model.chips.map(\.accessibilityLabel).contains("Alias facet WoW, inferred. Interpretive metadata, not accepted truth."))
        #expect(model.openActions.map(\.label) == ["Open hub"])
        #expect(model.openActions.allSatisfy { !$0.isEnabled })
        #expect(model.openActions.allSatisfy { $0.readOnly && !$0.promotesTruth })
    }

    @Test("chip row model enables only parsed safe hub navigation targets")
    func chipRowModelEnablesOnlyParsedSafeHubNavigationTargets() throws {
        let anchorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let presentation = LibraryHubFacetPresentationModel(hub: makeHub(
            itemID: anchorID,
            title: "World of Warcraft Hub",
            facets: [
                LibraryHubFacetPresentationModel.Chip(
                    id: "domain:games",
                    role: .domain,
                    label: "Games",
                    confidenceLabel: "source_backed",
                    source: "test.accepted-link",
                    evidence: "World of Warcraft source.",
                    itemRefs: ["bookmark:\(anchorID.uuidString)"],
                    truthBoundary: "interpretive_metadata_not_accepted_truth"
                ).domainFacet,
            ],
            safeNextCommands: [
                "cider-cli item hub --query \"WoW\" --limit 5 --json",
                "cider-cli item hub --query \"WoW\" --accept --json",
            ]
        ))

        let model = LibraryHubFacetChipRowModel(
            presentation: presentation,
            supportsOpenHubActions: true
        )

        #expect(model.openActions.count == 1)
        let action = try #require(model.openActions.first)
        #expect(action.isEnabled)
        #expect(action.target == .query("WoW"))
        #expect(action.readOnly)
        #expect(!action.promotesTruth)
    }

    @Test("chip row model hides when there are no chips")
    func chipRowModelHidesWithoutChips() {
        let presentation = LibraryHubFacetPresentationModel(hub: makeHub(
            itemID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Plain Item",
            facets: [],
            safeNextCommands: []
        ))

        let model = LibraryHubFacetChipRowModel(presentation: presentation)

        #expect(!model.isVisible)
        #expect(model.chips.isEmpty)
        #expect(model.openActions.isEmpty)
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

private extension LibraryHubFacetPresentationModel.Chip {
    var domainFacet: CiderLibraryHubDomainFacet {
        CiderLibraryHubDomainFacet(
            kind: role.facetKind,
            key: id.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? id,
            displayValue: label,
            confidenceLabel: confidenceLabel,
            source: source,
            evidence: evidence,
            itemRefs: itemRefs
        )
    }
}

private extension LibraryHubFacetPresentationModel.Chip.Role {
    var facetKind: String {
        switch self {
        case .domain: "domain"
        case .entityType: "entity_type"
        case .alias: "alias"
        case .place: "place"
        case .other: "other"
        }
    }
}
