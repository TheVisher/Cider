import AppKit
import Testing
@testable import Cider

struct CiderMainWindowPlacementTests {
    @Test("available display matches stable and legacy saved identities")
    @MainActor
    func availableDisplayMatchesSavedIdentities() throws {
        let screen = try #require(NSScreen.screens.first)
        let stableKey = CiderMainWindowFrameStore.screenKey(for: screen)

        #expect(CiderMainWindowFrameStore.screen(screen, matches: stableKey))

        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[screenNumberKey] as? NSNumber {
            #expect(CiderMainWindowFrameStore.screen(
                screen,
                matches: "display-\(number.uint32Value)"
            ))
        }
    }

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

    @Test("missing saved display centers a useful frame fully on the fallback display")
    func missingSavedDisplayCentersUsefulFrameOnFallbackDisplay() {
        let disconnectedVisibleFrame = NSRect(x: 2560, y: 0, width: 2560, height: 1415)
        let fallbackVisibleFrame = NSRect(x: 0, y: 25, width: 1440, height: 875)
        let savedFrame = NSRect(x: 4820, y: 1280, width: 360, height: 240)
        let minimumSize = NSSize(width: 920, height: 560)

        let restored = CiderMainWindowPlacement.restoredFrame(
            savedFrame,
            savedScreenVisibleFrame: disconnectedVisibleFrame,
            targetVisibleFrame: fallbackVisibleFrame,
            minimumSize: minimumSize,
            savedScreenIsAvailable: false
        )

        #expect(restored.width == minimumSize.width)
        #expect(restored.height == minimumSize.height)
        #expect(abs(restored.midX - fallbackVisibleFrame.midX) < 0.001)
        #expect(abs(restored.midY - fallbackVisibleFrame.midY) < 0.001)
        #expect(restored.minX >= fallbackVisibleFrame.minX + CiderMainWindowPlacement.screenPadding)
        #expect(restored.minY >= fallbackVisibleFrame.minY + CiderMainWindowPlacement.screenPadding)
        #expect(restored.maxX <= fallbackVisibleFrame.maxX - CiderMainWindowPlacement.screenPadding)
        #expect(restored.maxY <= fallbackVisibleFrame.maxY - CiderMainWindowPlacement.screenPadding)
    }

    @Test("QA visible frame centers and clamps within the target display")
    func qaVisibleFrameCentersAndClampsWithinTargetDisplay() {
        let targetVisibleFrame = NSRect(x: 80, y: 40, width: 1440, height: 900)

        let frame = CiderMainWindowPlacement.qaVisibleFrame(
            in: targetVisibleFrame,
            preferredSize: NSSize(width: 1180, height: 760),
            minimumSize: NSSize(width: 920, height: 560)
        )

        #expect(frame.minX >= targetVisibleFrame.minX + CiderMainWindowPlacement.screenPadding)
        #expect(frame.minY >= targetVisibleFrame.minY + CiderMainWindowPlacement.screenPadding)
        #expect(frame.maxX <= targetVisibleFrame.maxX - CiderMainWindowPlacement.screenPadding)
        #expect(frame.maxY <= targetVisibleFrame.maxY - CiderMainWindowPlacement.screenPadding)
        #expect(abs(frame.midX - targetVisibleFrame.midX) < 0.001)
        #expect(abs(frame.midY - targetVisibleFrame.midY) < 0.001)
    }

    @Test("QA visible window chrome is opt-in through environment")
    func qaVisibleWindowChromeIsEnvironmentGated() {
        #expect(CiderMainWindowChromePolicy.usesQAVisibleWindowChrome(environment: [:]) == false)
        #expect(CiderMainWindowChromePolicy.usesQAVisibleWindowChrome(environment: [
            CiderMainWindowChromePolicy.qaVisibleEnvironmentKey: "1"
        ]))
        #expect(CiderMainWindowChromePolicy.usesVerificationVisibleWindowPlacement(environment: [:]) == false)
        #expect(CiderMainWindowChromePolicy.usesVerificationVisibleWindowPlacement(environment: [
            CiderMainWindowChromePolicy.verificationVisibleEnvironmentKey: "1"
        ]))
        #expect(CiderMainWindowChromePolicy.shouldPersistMainWindowFrame(environment: [:]))
        #expect(CiderMainWindowChromePolicy.shouldPersistMainWindowFrame(environment: [
            CiderMainWindowChromePolicy.verificationVisibleEnvironmentKey: "1"
        ]) == false)
        #expect(CiderMainWindowChromePolicy.shouldPersistMainWindowFrame(environment: [
            CiderMainWindowChromePolicy.qaVisibleEnvironmentKey: "1"
        ]) == false)
        #expect(CiderMainWindowChromePolicy.styleMask(qaVisible: false).contains(.titled) == false)
        #expect(CiderMainWindowChromePolicy.styleMask(qaVisible: false).contains(.borderless))
        #expect(CiderMainWindowChromePolicy.styleMask(qaVisible: false).contains(.fullSizeContentView) == false)
        #expect(CiderMainWindowChromePolicy.styleMask(qaVisible: true).contains(.titled))
        #expect(CiderMainWindowChromePolicy.styleMask(qaVisible: true).contains(.fullSizeContentView) == false)
    }
}
