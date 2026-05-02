import Testing
@testable import Cider

struct CiderDetailNavigationPolicyTests {
    @Test("opening bookmark clears contact detail")
    func openingBookmarkClearsContactDetail() {
        #expect(CiderDetailNavigationPolicy.surfacesToClear(whenOpening: .bookmark).contains(.contact))
    }

    @Test("opening any detail keeps only the target surface")
    func openingAnyDetailKeepsOnlyTargetSurface() {
        for target in CiderDetailSurfaceKind.allCases {
            let cleared = CiderDetailNavigationPolicy.surfacesToClear(whenOpening: target)

            #expect(!cleared.contains(target))
            #expect(cleared.count == CiderDetailSurfaceKind.allCases.count - 1)
        }
    }
}
