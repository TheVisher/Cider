import AppKit
import XCTest
@testable import Cider

@MainActor
final class SparkleUpdaterWindowOrderingTests: XCTestCase {
    func testSparkleUIDemotesAndRestoresVisibleCiderFloatingWindows() {
        let settingsWindow = SettingsWindow()
        settingsWindow.setFrame(NSRect(x: 100, y: 100, width: 320, height: 240), display: false)
        settingsWindow.orderFront(nil)

        let normalWindow = NSWindow(
            contentRect: NSRect(x: 140, y: 140, width: 120, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        normalWindow.orderFront(nil)

        defer {
            SparkleUpdaterService.shared.restoreWindowsAfterSparkleUserInterface()
            settingsWindow.close()
            normalWindow.close()
        }

        XCTAssertEqual(settingsWindow.level, .floating)
        XCTAssertEqual(normalWindow.level, .normal)

        SparkleUpdaterService.shared.prepareForSparkleUserInterface()

        XCTAssertEqual(settingsWindow.level, .normal)
        XCTAssertEqual(normalWindow.level, .normal)

        SparkleUpdaterService.shared.restoreWindowsAfterSparkleUserInterface()

        XCTAssertEqual(settingsWindow.level, .floating)
        XCTAssertEqual(normalWindow.level, .normal)
    }
}
