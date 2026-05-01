import Foundation
import Testing
@testable import Cider

@Suite("Item Link Metadata Models")
struct ItemLinkMetadataModelsTests {
    @Test("candidate groups omit source and already related refs")
    func candidateGroupsOmitSourceAndRelatedRefs() {
        let source = LibraryEntityRef(type: .bookmark, entityID: UUID())
        let linkedContact = LibraryEntityRef(type: .contact, entityID: UUID())
        let addableContact = LibraryEntityRef(type: .contact, entityID: UUID())

        let groups = [
            ItemLinkMetadataCandidateGroup(
                title: "Contacts",
                candidates: [
                    ItemLinkMetadataCandidate(ref: linkedContact, title: "Baine", subtitle: "Contact"),
                    ItemLinkMetadataCandidate(ref: addableContact, title: "Sam", subtitle: "Contact")
                ]
            ),
            ItemLinkMetadataCandidateGroup(
                title: "Bookmarks",
                candidates: [
                    ItemLinkMetadataCandidate(ref: source, title: "Current bookmark", subtitle: "Bookmark")
                ]
            )
        ]

        let visible = ItemLinkMetadataActions.visibleGroups(
            source: source,
            relatedRefs: [linkedContact],
            groups: groups
        )

        #expect(visible.map(\.title) == ["Contacts"])
        #expect(visible.first?.candidates.map(\.ref) == [addableContact])
    }

    @Test("empty state copy changes when no addable targets remain")
    func emptyStateCopyChangesWhenNoAddableTargetsRemain() {
        #expect(ItemLinkMetadataActions.emptyStateText(hasAddableTargets: true) == "No linked items yet.")
        #expect(ItemLinkMetadataActions.emptyStateText(hasAddableTargets: false) == "No other items available to link.")
    }
}
