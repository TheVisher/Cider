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
}
