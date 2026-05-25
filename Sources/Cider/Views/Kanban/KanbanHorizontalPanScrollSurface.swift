import AppKit
import SwiftUI

enum KanbanHorizontalPanPolicy {
    static func proposedOffset(
        currentOffset: CGFloat,
        dragDeltaX: CGFloat,
        contentWidth: CGFloat,
        viewportWidth: CGFloat
    ) -> CGFloat {
        let maxOffset = max(contentWidth - viewportWidth, 0)
        let proposedOffset = currentOffset - dragDeltaX
        return min(max(proposedOffset, 0), maxOffset)
    }
}

struct KanbanHorizontalPanScrollSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> KanbanHorizontalPanView {
        KanbanHorizontalPanView()
    }

    func updateNSView(_ nsView: KanbanHorizontalPanView, context: Context) {}
}

final class KanbanHorizontalPanView: NSView {
    private static weak var activePanView: KanbanHorizontalPanView?

    private var eventMonitor: KanbanHorizontalPanEventMonitor?
    private weak var activeScrollView: NSScrollView?
    private var initialDragLocation: CGPoint?
    private var lastDragLocation: CGPoint?
    private var didPassDragThreshold = false
    private var pushedCursor = false

    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            removeEventMonitor()
            clearDragState()
        } else {
            installEventMonitor()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    private func installEventMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = KanbanHorizontalPanEventMonitor { [weak self] event in
            self?.handle(event)
        }
    }

    private func removeEventMonitor() {
        eventMonitor?.invalidate()
        eventMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            beginDragIfNeeded(with: event)
        case .leftMouseDragged:
            updateDrag(with: event)
        case .leftMouseUp:
            endDrag()
        default:
            break
        }
    }

    private func beginDragIfNeeded(with event: NSEvent) {
        let scrollView = horizontalScrollView(containing: event.locationInWindow)
        guard Self.activePanView == nil,
              event.window === window,
              scrollView != nil else {
            return
        }

        Self.activePanView = self
        activeScrollView = scrollView
        initialDragLocation = event.locationInWindow
        lastDragLocation = event.locationInWindow
        didPassDragThreshold = false
    }

    private func updateDrag(with event: NSEvent) {
        guard Self.activePanView === self,
              event.window === window,
              let initialDragLocation,
              let lastDragLocation,
              let scrollView = activeScrollView,
              let documentView = scrollView.documentView else {
            return
        }

        let location = event.locationInWindow
        let totalDelta = CGPoint(
            x: location.x - initialDragLocation.x,
            y: location.y - initialDragLocation.y
        )

        if !didPassDragThreshold {
            let horizontalDistance = abs(totalDelta.x)
            let verticalDistance = abs(totalDelta.y)
            guard horizontalDistance > 5, horizontalDistance > verticalDistance * 1.15 else {
                return
            }
            didPassDragThreshold = true
            NSCursor.closedHand.push()
            pushedCursor = true
        }

        let currentBounds = scrollView.contentView.bounds
        let nextOffset = KanbanHorizontalPanPolicy.proposedOffset(
            currentOffset: currentBounds.origin.x,
            dragDeltaX: location.x - lastDragLocation.x,
            contentWidth: documentView.bounds.width,
            viewportWidth: currentBounds.width
        )

        scrollView.contentView.scroll(to: CGPoint(x: nextOffset, y: currentBounds.origin.y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        self.lastDragLocation = location
    }

    private func endDrag() {
        guard Self.activePanView === self else { return }
        clearDragState()
    }

    private func clearDragState() {
        if Self.activePanView === self {
            Self.activePanView = nil
        }
        activeScrollView = nil
        initialDragLocation = nil
        lastDragLocation = nil
        didPassDragThreshold = false
        if pushedCursor {
            NSCursor.pop()
            pushedCursor = false
        }
    }

    private func horizontalScrollView(containing windowPoint: CGPoint? = nil) -> NSScrollView? {
        if let windowPoint, let contentView = window?.contentView {
            return scrollViews(in: contentView)
                .first { scrollView in
                    guard isHorizontallyScrollable(scrollView) else { return false }
                    let localPoint = scrollView.contentView.convert(windowPoint, from: nil)
                    return scrollView.contentView.bounds.contains(localPoint)
                }
        }

        return sequence(first: superview) { view in
            view?.superview
        }
            .compactMap { $0 as? NSScrollView }
            .first(where: isHorizontallyScrollable)
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        var matches: [NSScrollView] = []
        if let scrollView = view as? NSScrollView {
            matches.append(scrollView)
        }
        for subview in view.subviews {
            matches.append(contentsOf: scrollViews(in: subview))
        }
        return matches
    }

    private func isHorizontallyScrollable(_ scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return false }
        return documentView.bounds.width > scrollView.contentView.bounds.width
    }
}

private final class KanbanHorizontalPanEventMonitor {
    private var token: Any?

    init(handler: @escaping (NSEvent) -> Void) {
        token = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { event in
            handler(event)
            return event
        }
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        if let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }
}
