import Foundation
import Testing
@testable import Cider
@testable import CiderCLI

@Suite("Cider Space Authority Contract Tests")
@MainActor
struct CiderSpaceAuthorityContractTests {
    @Test("space json labels hybrid authority and root path storage role")
    func spaceJSONLabelsHybridAuthorityAndRootPathStorageRole() throws {
        let space = CiderSpace(
            id: "space-media",
            name: "Media",
            systemImage: "play.rectangle",
            purpose: "Entertainment tracking.",
            preset: .media,
            aiInstructions: "Route entertainment items here.",
            routingHints: ["Use native membership over path containment."],
            defaultViews: [.overview, .inbox],
            rootRelativePath: "Spaces/Media",
            createdAt: Date(timeIntervalSince1970: 1),
            updatedAt: Date(timeIntervalSince1970: 2)
        )

        let dict = CiderCLI.spaceToDict(space)
        let authority = try #require(dict["authority"] as? [String: Any])
        let nativeCutover = try #require(dict["nativeCutover"] as? [String: Any])

        #expect(authority["status"] as? String == "hybrid_yaml_bridge")
        #expect(authority["metadataSource"] as? String == ".cider-space.yaml")
        #expect(authority["semanticMembershipSource"] as? String == "space_memberships")
        #expect(authority["rootPathRole"] as? String == "storage_projection")
        #expect(authority["pathContainmentIsSemantic"] as? Bool == false)

        #expect(nativeCutover["plannedTable"] as? String == "spaces")
        #expect(nativeCutover["compatibilityProjection"] as? String == ".cider-space.yaml")
        #expect(nativeCutover["nextGate"] as? String == "39a15a")
    }
}
