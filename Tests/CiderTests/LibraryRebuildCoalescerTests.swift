import XCTest
@testable import Cider

@MainActor
final class LibraryRebuildCoalescerTests: XCTestCase {
    func testBurstInvalidationsCoalesceIntoOneRebuild() async {
        var rebuildCount = 0
        let coalescer = LibraryRebuildCoalescer {
            rebuildCount += 1
        }

        coalescer.requestRebuild()
        coalescer.requestRebuild()
        coalescer.requestRebuild()

        XCTAssertEqual(rebuildCount, 0)
        await Task.yield()
        XCTAssertEqual(rebuildCount, 1)

        coalescer.requestRebuild()
        await Task.yield()
        XCTAssertEqual(rebuildCount, 2)
    }
}
