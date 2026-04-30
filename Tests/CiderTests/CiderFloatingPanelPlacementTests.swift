import AppKit
import Testing
@testable import Cider

struct CiderFloatingPanelPlacementTests {
    @Test("translated frame preserves relative top-left placement across displays")
    func translatedFramePreservesRelativePlacement() {
        let source = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let target = NSRect(x: 1200, y: 100, width: 2000, height: 1200)
        let frame = NSRect(x: 700, y: 500, width: 200, height: 180)

        let translated = CiderFloatingPanelPlacement.translatedFrame(frame, from: source, to: target)

        #expect(translated.minX == 2600)
        #expect(translated.maxY == 1120)
        #expect(translated.width == 200)
        #expect(translated.height == 180)
    }

    @Test("translated frame clamps oversized saved frames into the target display")
    func translatedFrameClampsToTargetDisplay() {
        let source = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let target = NSRect(x: 0, y: 0, width: 500, height: 400)
        let frame = NSRect(x: 900, y: 700, width: 600, height: 500)

        let translated = CiderFloatingPanelPlacement.translatedFrame(frame, from: source, to: target)

        #expect(translated.minX >= CiderFloatingPanelPlacement.screenPadding)
        #expect(translated.minY >= CiderFloatingPanelPlacement.screenPadding)
        #expect(translated.maxX <= target.maxX - CiderFloatingPanelPlacement.screenPadding)
        #expect(translated.maxY <= target.maxY - CiderFloatingPanelPlacement.screenPadding)
    }
}
