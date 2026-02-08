import AppKit
import SwiftUI

final class TileZoneOverlayPanel: NSPanel {
    let monitor: MonitorInfo

    init(monitor: MonitorInfo) {
        self.monitor = monitor

        super.init(contentRect: monitor.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        // One level below the command palette's .floating
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovable = false
        ignoresMouseEvents = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
