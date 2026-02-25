import AppKit
import SwiftUI

final class ScreenCaptureToastPanel: NSPanel {
    init() {
        let initialFrame = NSRect(
            x: 0,
            y: 0,
            width: ScreenCaptureToastDesign.panelWidth,
            height: ScreenCaptureToastDesign.panelHeight
        )

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false

        isMovable = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ScreenCaptureToastModel: ObservableObject {
    @Published var progress: CGFloat = 1
}
