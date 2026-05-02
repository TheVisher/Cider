import AppKit
import Testing
@testable import Cider

struct CiderMainWindowPlacementTests {
    @Test("restored frame preserves relative top-left placement on the saved display")
    func restoredFramePreservesRelativePlacement() {
        let sourceVisibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let targetVisibleFrame = NSRect(x: 1200, y: 100, width: 2000, height: 1200)
        let savedFrame = NSRect(x: 700, y: 500, width: 240, height: 180)

        let restored = CiderMainWindowPlacement.restoredFrame(
            savedFrame,
            savedScreenVisibleFrame: sourceVisibleFrame,
            targetVisibleFrame: targetVisibleFrame,
            minimumSize: NSSize(width: 200, height: 160)
        )

        #expect(restored.minX == 2600)
        #expect(restored.maxY == 1120)
        #expect(restored.width == 240)
        #expect(restored.height == 180)
    }

    @Test("restored frame clamps size and origin into the target display")
    func restoredFrameClampsIntoTargetDisplay() {
        let sourceVisibleFrame = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let targetVisibleFrame = NSRect(x: 0, y: 0, width: 600, height: 480)
        let savedFrame = NSRect(x: 900, y: 700, width: 900, height: 700)

        let restored = CiderMainWindowPlacement.restoredFrame(
            savedFrame,
            savedScreenVisibleFrame: sourceVisibleFrame,
            targetVisibleFrame: targetVisibleFrame,
            minimumSize: NSSize(width: 420, height: 300)
        )

        #expect(restored.minX >= CiderMainWindowPlacement.screenPadding)
        #expect(restored.minY >= CiderMainWindowPlacement.screenPadding)
        #expect(restored.maxX <= targetVisibleFrame.maxX - CiderMainWindowPlacement.screenPadding)
        #expect(restored.maxY <= targetVisibleFrame.maxY - CiderMainWindowPlacement.screenPadding)
        #expect(restored.width >= 420)
        #expect(restored.height >= 300)
    }
}
