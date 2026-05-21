import Testing
import CoreGraphics
@testable import Cider

struct BookmarkCardAspectRatioTests {
    @Test("aspect ratio state ignores repeated equivalent values")
    func aspectRatioStateIgnoresRepeatedEquivalentValues() {
        #expect(!BookmarkCard.shouldUpdateResolvedAspectRatio(current: nil, candidate: nil))
        #expect(BookmarkCard.shouldUpdateResolvedAspectRatio(current: nil, candidate: 0.525))
        #expect(!BookmarkCard.shouldUpdateResolvedAspectRatio(current: 0.525, candidate: 0.5254))
        #expect(BookmarkCard.shouldUpdateResolvedAspectRatio(current: 0.525, candidate: 0.54))
        #expect(BookmarkCard.shouldUpdateResolvedAspectRatio(current: 0.525, candidate: nil))
    }
}
