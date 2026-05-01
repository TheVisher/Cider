import Foundation

struct ItemLinkMetadataCandidate: Identifiable, Equatable {
    let ref: LibraryEntityRef
    let title: String
    let subtitle: String

    var id: String { ref.id }
}

struct ItemLinkMetadataCandidateGroup: Identifiable, Equatable {
    let title: String
    let candidates: [ItemLinkMetadataCandidate]

    var id: String { title }
}

enum ItemLinkMetadataActions {
    static func visibleGroups(
        source: LibraryEntityRef,
        relatedRefs: [LibraryEntityRef],
        groups: [ItemLinkMetadataCandidateGroup]
    ) -> [ItemLinkMetadataCandidateGroup] {
        let blockedIDs = Set(([source] + relatedRefs).map(\.id))

        return groups.compactMap { group in
            let candidates = group.candidates.filter { !blockedIDs.contains($0.ref.id) }
            guard !candidates.isEmpty else { return nil }
            return ItemLinkMetadataCandidateGroup(title: group.title, candidates: candidates)
        }
    }

    static func emptyStateText(hasAddableTargets: Bool) -> String {
        hasAddableTargets ? "No linked items yet." : "No other items available to link."
    }
}
