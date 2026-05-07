import AppKit
import SwiftUI
import WebKit

final class CiderMainWindow: NSWindow {
    /// Updated by CiderPanelShell when sidebar visibility changes.
    var isSidebarCurrentlyVisible = true

    private let frameStore: CiderMainWindowFrameStore
    private var shouldPersistFrame = false
    private var dragStartOrigin: NSPoint?
    private var dragStartMouse: NSPoint?
    private var isDragging = false
    private var dragExclusionRects: [String: NSRect] = [:]

    init(frameStore: CiderMainWindowFrameStore = .shared) {
        self.frameStore = frameStore
        let initialFrame = NSRect(x: 0, y: 0, width: 1180, height: 760)

        super.init(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        title = "Cider"
        isReleasedWhenClosed = false
        minSize = NSSize(width: 920, height: 560)
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameDidMove),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleFrameDidResize),
            name: NSWindow.didResizeNotification,
            object: self
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func showCentered() {
        if !restoreSavedFrameIfAvailable() {
            let targetScreen = screenContainingMouse() ?? NSScreen.main

            if frame.origin == .zero || !isVisible(frame, on: targetScreen) {
                center(on: targetScreen)
            } else if let clampedFrame = frameClampedToVisibleScreen(frame, screen: targetScreen) {
                setFrame(clampedFrame, display: true)
            }
        }
        if isMiniaturized {
            deminiaturize(nil)
        }
        shouldPersistFrame = true
        persistCurrentFrame()
        makeKeyAndOrderFront(nil)
    }

    func persistCurrentFrame() {
        guard shouldPersistFrame, CiderConfig.load().rememberPanelPosition else { return }
        let targetScreen = screen ?? CiderFloatingPanelPlacement.preferredScreen(for: frame)
        frameStore.save(frame: frame, screen: targetScreen)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            if isInDraggableArea(event.locationInWindow) {
                dragStartOrigin = frame.origin
                dragStartMouse = NSEvent.mouseLocation
                isDragging = false
            }
            super.sendEvent(event)

        case .leftMouseDragged:
            if let startOrigin = dragStartOrigin,
               let startMouse = dragStartMouse {
                let currentMouse = NSEvent.mouseLocation
                let dx = currentMouse.x - startMouse.x
                let dy = currentMouse.y - startMouse.y

                if !isDragging && (abs(dx) > 3 || abs(dy) > 3) {
                    isDragging = true
                }

                if isDragging {
                    setFrameOrigin(NSPoint(
                        x: startOrigin.x + dx,
                        y: startOrigin.y + dy
                    ))
                    return
                }
            }
            super.sendEvent(event)

        case .leftMouseUp:
            dragStartOrigin = nil
            dragStartMouse = nil
            isDragging = false
            super.sendEvent(event)

        default:
            super.sendEvent(event)
        }
    }

    func setDragExclusionRect(_ rect: NSRect, for id: String) {
        dragExclusionRects[id] = rect
    }

    func removeDragExclusionRect(for id: String) {
        dragExclusionRects.removeValue(forKey: id)
    }

    func isLocationExcludedFromWindowDrag(_ locationInWindow: NSPoint) -> Bool {
        dragExclusionRects.values.contains { rect in
            rect.insetBy(dx: -1, dy: -1).contains(locationInWindow)
        }
    }

    private func isInDraggableArea(_ locationInWindow: NSPoint) -> Bool {
        guard let contentView else { return false }
        let bounds = contentView.bounds

        if isInResizeEdgeBand(locationInWindow, bounds: bounds) {
            return false
        }

        if isLocationExcludedFromWindowDrag(locationInWindow) {
            return false
        }

        if let hitView = contentView.hitTest(locationInWindow) {
            var view: NSView? = hitView
            while let v = view, v !== contentView {
                if v is NSControl { return false }
                if v is WKWebView { return false }
                if v is PanelEdgeResizeNSView { return false }
                view = v.superview
            }
        }

        let titleBarMinY = bounds.height - CiderPanelDesign.titleBarHeight - (Spacing.sm - 1)
        if locationInWindow.y >= titleBarMinY {
            return true
        }

        if isSidebarCurrentlyVisible {
            let sidebarMaxX = BookmarksDesign.folderSidebarWidth + Spacing.md * 2 + Spacing.sm
            if locationInWindow.x <= sidebarMaxX {
                return true
            }
        }

        return false
    }

    private func isInResizeEdgeBand(_ locationInWindow: NSPoint, bounds: NSRect) -> Bool {
        let hPad = CiderPanelDesign.shadowPadding
        let topPad = CiderPanelDesign.topPadding
        let bottomPad = CiderPanelDesign.shadowPadding + CiderPanelDesign.bottomPadding
        let edgeInset = CiderPanelDesign.resizeEdgeThickness

        let contentMinX = hPad
        let contentMaxX = bounds.width - hPad
        let contentMinY = bottomPad
        let contentMaxY = bounds.height - topPad

        return locationInWindow.x < contentMinX + edgeInset
            || locationInWindow.x > contentMaxX - edgeInset
            || locationInWindow.y < contentMinY + edgeInset
            || locationInWindow.y > contentMaxY - edgeInset
    }

    private func isVisible(_ rect: NSRect, on screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        let minimumVisibleArea: CGFloat = 12_000
        return rect.intersection(screen.visibleFrame).area >= minimumVisibleArea
    }

    private func frameClampedToVisibleScreen(_ rect: NSRect, screen: NSScreen?) -> NSRect? {
        guard let screen else { return nil }
        let visibleFrame = screen.visibleFrame
        var clamped = rect
        clamped.size.width = min(max(minSize.width, clamped.width), visibleFrame.width)
        clamped.size.height = min(max(minSize.height, clamped.height), visibleFrame.height)
        clamped.origin.x = min(max(clamped.minX, visibleFrame.minX), visibleFrame.maxX - clamped.width)
        clamped.origin.y = min(max(clamped.minY, visibleFrame.minY), visibleFrame.maxY - clamped.height)
        return clamped
    }

    private func center(on screen: NSScreen?) {
        guard let visibleFrame = screen?.visibleFrame else {
            center()
            return
        }

        var centeredFrame = frame
        centeredFrame.size.width = min(max(minSize.width, centeredFrame.width), visibleFrame.width)
        centeredFrame.size.height = min(max(minSize.height, centeredFrame.height), visibleFrame.height)
        centeredFrame.origin.x = visibleFrame.midX - centeredFrame.width / 2
        centeredFrame.origin.y = visibleFrame.midY - centeredFrame.height / 2
        setFrame(centeredFrame, display: true)
    }

    private func restoreSavedFrameIfAvailable() -> Bool {
        guard CiderConfig.load().rememberPanelPosition,
              let snapshot = frameStore.snapshot() else {
            return false
        }

        let targetScreen = screen(matching: snapshot.screenKey)
            ?? CiderFloatingPanelPlacement.preferredScreen(for: snapshot.frame.rect)
            ?? screenContainingMouse()
            ?? NSScreen.main
        guard let targetScreen else { return false }

        let restoredFrame = CiderMainWindowPlacement.restoredFrame(
            snapshot.frame.rect,
            savedScreenVisibleFrame: snapshot.screenVisibleFrame.rect,
            targetVisibleFrame: targetScreen.visibleFrame,
            minimumSize: minSize
        )
        setFrame(restoredFrame, display: true)
        return true
    }

    private func screen(matching key: String?) -> NSScreen? {
        guard let key else { return nil }
        return NSScreen.screens.first { CiderMainWindowFrameStore.screenKey(for: $0) == key }
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    @objc private func handleFrameDidMove() {
        persistCurrentFrame()
        CiderLivePerformanceRecorder.shared.recordFrame(event: .move, windowSize: frame.size)
    }

    @objc private func handleFrameDidResize() {
        persistCurrentFrame()
        CiderLivePerformanceRecorder.shared.recordFrame(event: .resize, windowSize: frame.size)
    }
}

private extension NSRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

final class CiderMainWindowHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
