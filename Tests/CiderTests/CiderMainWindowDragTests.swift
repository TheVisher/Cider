import AppKit
import XCTest
@testable import Cider

final class CiderMainWindowDragTests: XCTestCase {
    @MainActor
    func testTabExclusionRectsSuppressWindowDragLocations() {
        let window = CiderMainWindow()
        let tabRect = NSRect(x: 120, y: 710, width: 160, height: 32)

        window.setDragExclusionRect(tabRect, for: "tab-library")

        XCTAssertTrue(window.isLocationExcludedFromWindowDrag(NSPoint(x: 180, y: 724)))
        XCTAssertFalse(window.isLocationExcludedFromWindowDrag(NSPoint(x: 340, y: 724)))
    }

    @MainActor
    func testRemovingTabExclusionRestoresWindowDragLocations() {
        let window = CiderMainWindow()
        let tabRect = NSRect(x: 120, y: 710, width: 160, height: 32)

        window.setDragExclusionRect(tabRect, for: "tab-library")
        window.removeDragExclusionRect(for: "tab-library")

        XCTAssertFalse(window.isLocationExcludedFromWindowDrag(NSPoint(x: 180, y: 724)))
    }

    @MainActor
    func testMainWindowResizeUsesItsUsefulMinimumSize() {
        let window = CiderMainWindow()

        let minimumSize = PanelEdgeResizeNSView.minimumResizeSize(for: window)

        XCTAssertEqual(minimumSize.width, 920)
        XCTAssertEqual(minimumSize.height, 560)
    }

    @MainActor
    func testSettledFrameRestoresAcrossMainWindowRecreationOnSameDisplay() throws {
        let suiteName = "CiderMainWindowDragTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let screen = try XCTUnwrap(NSScreen.screens.first)
        let expectedFrame = CiderMainWindowPlacement.clampedFrame(
            NSRect(
                x: screen.visibleFrame.minX + 72,
                y: screen.visibleFrame.minY + 64,
                width: 1_040,
                height: 680
            ),
            in: screen.visibleFrame,
            minimumSize: NSSize(width: 920, height: 560)
        )
        let store = CiderMainWindowFrameStore(defaults: defaults)
        let firstWindow = CiderMainWindow(frameStore: store)
        firstWindow.showCentered()
        firstWindow.setFrame(expectedFrame, display: false)
        firstWindow.persistSettledFrame()
        firstWindow.orderOut(nil)

        let recreatedWindow = CiderMainWindow(
            frameStore: CiderMainWindowFrameStore(defaults: defaults)
        )
        recreatedWindow.showCentered()
        defer { recreatedWindow.orderOut(nil) }

        XCTAssertEqual(recreatedWindow.frame, expectedFrame)
        XCTAssertEqual(
            store.snapshot()?.screenKey,
            CiderMainWindowFrameStore.screenKey(for: screen)
        )
    }
}
