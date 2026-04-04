import AppKit
import SwiftUI
import os

/// Native SwiftUI canvas surface with pan/zoom and positioned cards.
struct NativeCanvasView: View {
    @ObservedObject var viewModel: CanvasViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Gesture state — accumulated + in-flight
    @State private var currentZoom: CGFloat = 1.0
    @State private var currentPan: CGPoint = .zero
    @State private var gesturePan: CGSize = .zero

    private var effectiveZoom: CGFloat {
        min(max(currentZoom, CanvasViewport.minZoom), CanvasViewport.maxZoom)
    }

    private var effectivePan: CGPoint {
        CGPoint(
            x: currentPan.x + gesturePan.width,
            y: currentPan.y + gesturePan.height
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dot grid background — handles click-and-drag panning
                dotGrid(in: geometry.size)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                gesturePan = value.translation
                            }
                            .onEnded { value in
                                currentPan = CGPoint(
                                    x: currentPan.x + value.translation.width,
                                    y: currentPan.y + value.translation.height
                                )
                                gesturePan = .zero
                                syncViewport()
                            }
                    )

                // Canvas content — only visible cards
                canvasContent(viewportSize: geometry.size)
                    .offset(x: effectivePan.x, y: effectivePan.y)
                    .allowsHitTesting(true)
            }
            .clipped()
            .background(CiderColors.acrylicTint)
            .background {
                // Full-size view that hosts the NSEvent monitors for scroll/magnify.
                // Must have correct frame so coordinate conversion works for zoom-to-cursor.
                CanvasScrollHandler(
                    zoom: $currentZoom,
                    pan: $currentPan,
                    onChanged: { syncViewport() }
                )
                .allowsHitTesting(false)
            }
            .overlay {
                // Invisible drop target for URLs dragged from browsers / text
                CanvasDropZone(
                    zoom: effectiveZoom,
                    pan: effectivePan,
                    viewModel: viewModel
                )
            }
            .overlay(alignment: .bottomTrailing) {
                CanvasMinimapView(
                    viewModel: viewModel,
                    viewportSize: geometry.size,
                    currentZoom: effectiveZoom,
                    currentPan: effectivePan,
                    onNavigate: { newPan in
                        withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                            currentPan = newPan
                            syncViewport()
                        }
                    }
                )
                .padding(Spacing.md)
            }
            .onAppear {
                currentZoom = viewModel.viewport.zoom
                currentPan = viewModel.viewport.offset
                if viewModel.viewport == .default {
                    fitToContent(viewportSize: geometry.size)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvasFitAll)) { _ in
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.4)) {
                    fitToContent(viewportSize: geometry.size)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvasZoomIn)) { _ in
                let newZoom = min(currentZoom * 1.25, CanvasViewport.maxZoom)
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.2)) {
                    currentZoom = newZoom
                    syncViewport()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvasZoomOut)) { _ in
                let newZoom = max(currentZoom / 1.25, CanvasViewport.minZoom)
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.2)) {
                    currentZoom = newZoom
                    syncViewport()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .panelFolderSelected)) { notification in
                guard let folderID = notification.userInfo?["folderID"] as? UUID else { return }
                let groupId = "folder-\(folderID.uuidString)"
                guard let node = viewModel.nodes.first(where: { $0.id == groupId }) else { return }
                let cx = node.position.x + node.size.width / 2
                let cy = node.position.y + node.size.height / 2
                let targetPan = CGPoint(
                    x: geometry.size.width / 2 - cx * effectiveZoom,
                    y: geometry.size.height / 2 - cy * effectiveZoom
                )
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.4)) {
                    currentPan = targetPan
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    syncViewport()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvasPanToFolder)) { notification in
                guard let cx = notification.userInfo?["x"] as? CGFloat,
                      let cy = notification.userInfo?["y"] as? CGFloat else { return }
                flyToPoint(cx: cx, cy: cy, viewportSize: geometry.size)
            }
            .onReceive(NotificationCenter.default.publisher(for: .canvasResetZoom)) { _ in
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
                    // Adjust pan so the current viewport center stays centered at 100%
                    let viewportCenter = CGPoint(
                        x: (geometry.size.width / 2 - currentPan.x) / effectiveZoom,
                        y: (geometry.size.height / 2 - currentPan.y) / effectiveZoom
                    )
                    currentZoom = 1.0
                    currentPan = CGPoint(
                        x: geometry.size.width / 2 - viewportCenter.x,
                        y: geometry.size.height / 2 - viewportCenter.y
                    )
                    syncViewport()
                }
            }
        }
    }

    // MARK: - Fly-To Navigation

    /// Animated navigation to a canvas point. Scales the zoom-out and duration
    /// based on distance: short hops just pan, long distances get a fly-over.
    private func flyToPoint(cx: CGFloat, cy: CGFloat, viewportSize: CGSize) {
        let originalZoom = currentZoom

        // Current viewport center in canvas coordinates
        let currentCX = (viewportSize.width / 2 - currentPan.x) / originalZoom
        let currentCY = (viewportSize.height / 2 - currentPan.y) / originalZoom

        // Distance in canvas space
        let dx = cx - currentCX
        let dy = cy - currentCY
        let distance = sqrt(dx * dx + dy * dy)

        // Scale effect by distance: no zoom-out under 500pt, max at 3000pt+
        let normalizedDistance = min(max((distance - 500) / 2500, 0), 1)

        // Smooth pan to target — keep it quick even for long distances
        // so you see a fast slide rather than a slow fade.
        let duration = 0.3 + normalizedDistance * 0.15  // 0.3s – 0.45s

        let targetPan = CGPoint(
            x: viewportSize.width / 2 - cx * originalZoom,
            y: viewportSize.height / 2 - cy * originalZoom
        )

        let animation: Animation? = reduceMotion
            ? .none
            : .timingCurve(0.25, 0.1, 0.25, 1.0, duration: duration) // cubic-bezier ease

        withAnimation(animation) {
            currentPan = targetPan
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            syncViewport()
        }
    }

    // MARK: - Fit to Content

    private func fitToContent(viewportSize: CGSize) {
        let topLevel = viewModel.nodes.filter { $0.parentNodeID == nil }
        guard !topLevel.isEmpty else { return }

        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for node in topLevel {
            minX = min(minX, node.position.x)
            minY = min(minY, node.position.y)
            maxX = max(maxX, node.position.x + node.size.width)
            maxY = max(maxY, node.position.y + node.size.height)
        }

        let contentWidth = maxX - minX
        let contentHeight = maxY - minY
        guard contentWidth > 0, contentHeight > 0 else { return }

        let padding: CGFloat = 80
        let zoomX = (viewportSize.width - padding * 2) / contentWidth
        let zoomY = (viewportSize.height - padding * 2) / contentHeight
        let fitZoom = min(max(min(zoomX, zoomY), CanvasViewport.minZoom), CanvasViewport.maxZoom)

        // Pan so the content center maps to the viewport center
        let contentCenterX = (minX + maxX) / 2
        let contentCenterY = (minY + maxY) / 2
        let panX = viewportSize.width / 2 - contentCenterX * fitZoom
        let panY = viewportSize.height / 2 - contentCenterY * fitZoom

        currentZoom = fitZoom
        currentPan = CGPoint(x: panX, y: panY)
        syncViewport()
    }

    // MARK: - Canvas Content (with viewport culling)

    @ViewBuilder
    private func canvasContent(viewportSize: CGSize) -> some View {
        // Compute visible rect in canvas coordinates
        let visibleRect = visibleCanvasRect(viewportSize: viewportSize)

        // Margin: render cards slightly outside viewport for smooth scrolling
        let margin: CGFloat = 200 / effectiveZoom
        let cullRect = visibleRect.insetBy(dx: -margin, dy: -margin)

        ZStack {
            ForEach(viewModel.nodes.filter { node in
                node.parentNodeID == nil && nodeIntersects(node, rect: cullRect)
            }) { node in
                cardForNode(node)
                    .position(
                        x: node.position.x * effectiveZoom + node.size.width * effectiveZoom / 2,
                        y: node.position.y * effectiveZoom + node.size.height * effectiveZoom / 2
                    )
            }
        }
        // Size the ZStack to fill the viewport — cards are positioned absolutely
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
    }

    /// What's the card for this node at the current zoom level?
    @ViewBuilder
    private func cardForNode(_ node: CanvasNode) -> some View {
        let scaledWidth = node.size.width * effectiveZoom
        let scaledHeight = node.size.height * effectiveZoom

        if effectiveZoom < 0.3 {
            // LOD 3: tiny colored rectangles — ultra cheap
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(lodColor(for: node))
                .frame(width: scaledWidth, height: scaledHeight)
        } else if effectiveZoom < 0.6 {
            // LOD 2: title + colored bar, no thumbnails
            SimplifiedCardView(
                    node: node,
                    zoom: effectiveZoom,
                    titleText: viewModel.titleCache[node.itemID ?? node.id] ?? "—"
                )
                .frame(width: scaledWidth)
                .drawingGroup()
        } else {
            // LOD 1: full detail card — render at native size, then scale down
            CanvasCardView(
                node: node,
                zoom: effectiveZoom,
                viewModel: viewModel
            )
            .frame(width: node.size.width)
            .scaleEffect(effectiveZoom)
            .frame(width: scaledWidth, height: scaledHeight)
        }
    }

    private func lodColor(for node: CanvasNode) -> Color {
        CanvasNodeColors.color(for: node.itemType)
    }

    // MARK: - Viewport Culling

    /// Computes the visible rectangle in canvas coordinates.
    private func visibleCanvasRect(viewportSize: CGSize) -> CGRect {
        let x = -effectivePan.x / effectiveZoom
        let y = -effectivePan.y / effectiveZoom
        let w = viewportSize.width / effectiveZoom
        let h = viewportSize.height / effectiveZoom
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func nodeIntersects(_ node: CanvasNode, rect: CGRect) -> Bool {
        let nodeRect = CGRect(origin: node.position, size: node.size)
        return nodeRect.intersects(rect)
    }

    // MARK: - Dot Grid

    @ViewBuilder
    private func dotGrid(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let baseSpacing: CGFloat = 20
            let spacing = baseSpacing * effectiveZoom

            // Skip grid when dots would be too dense or too sparse
            guard spacing > 6, spacing < 200 else { return }

            let offsetX = effectivePan.x.truncatingRemainder(dividingBy: spacing)
            let offsetY = effectivePan.y.truncatingRemainder(dividingBy: spacing)

            let cols = Int(canvasSize.width / spacing) + 2
            let rows = Int(canvasSize.height / spacing) + 2

            // Cap total dots to prevent lag
            let totalDots = cols * rows
            guard totalDots < 5000 else { return }

            let dotSize: CGFloat = max(1, 1.5 * effectiveZoom)
            var path = Path()

            for col in 0..<cols {
                for row in 0..<rows {
                    let x = CGFloat(col) * spacing + offsetX
                    let y = CGFloat(row) * spacing + offsetY
                    path.addEllipse(in: CGRect(
                        x: x - dotSize / 2,
                        y: y - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    ))
                }
            }

            context.fill(path, with: .color(Color.white.opacity(0.08)))
        }
    }

    private func syncViewport() {
        viewModel.viewport = CanvasViewport(
            offset: currentPan,
            zoom: currentZoom
        )
    }
}

// MARK: - Simplified Card (LOD 2)

/// Lightweight card for medium zoom — title + color bar, no thumbnails or complex views.
private struct SimplifiedCardView: View {
    let node: CanvasNode
    let zoom: CGFloat
    var titleText: String = "—"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Color bar at top
            Rectangle()
                .fill(barColor)
                .frame(height: max(3, 4 * zoom))

            VStack(alignment: .leading, spacing: 2 * zoom) {
                Text(title)
                    .font(.system(size: max(6, 11 * zoom), weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)
            }
            .padding(max(3, 8 * zoom))
        }
        .background(
            RoundedRectangle(cornerRadius: max(2, Radius.md * zoom), style: .continuous)
                .fill(CiderColors.surfaceElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: max(2, Radius.md * zoom), style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: max(2, Radius.md * zoom), style: .continuous))
    }

    private var barColor: Color {
        CanvasNodeColors.color(for: node.itemType)
    }

    private var title: String { titleText }
}

// MARK: - Scroll/Magnify Event Monitor

/// Uses NSEvent local monitors to capture scroll and magnify events for the canvas.
/// Doesn't interfere with SwiftUI hit testing — cards and minimap remain clickable.
struct CanvasScrollHandler: NSViewRepresentable {
    @Binding var zoom: CGFloat
    @Binding var pan: CGPoint
    var onChanged: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostView = view
        context.coordinator.startMonitoring()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.zoom = $zoom
        context.coordinator.pan = $pan
        context.coordinator.onChanged = onChanged
        // Cache the window reference so the nonisolated monitor can check it
        context.coordinator.cacheWindow(nsView.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stopMonitoring()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(zoom: $zoom, pan: $pan, onChanged: onChanged)
    }

    final class Coordinator {
        var zoom: Binding<CGFloat>
        var pan: Binding<CGPoint>
        var onChanged: () -> Void
        weak var hostView: NSView?
        private let windowLock = OSAllocatedUnfairLock<NSWindow?>(initialState: nil)

        private var scrollMonitor: Any?
        private var magnifyMonitor: Any?

        init(zoom: Binding<CGFloat>, pan: Binding<CGPoint>, onChanged: @escaping () -> Void) {
            self.zoom = zoom
            self.pan = pan
            self.onChanged = onChanged
        }

        func cacheWindow(_ window: NSWindow?) {
            windowLock.withLock { $0 = window }
        }

        func startMonitoring() {
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.isEventInCanvas(event) else { return event }
                self.handleScroll(event)
                return event
            }

            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                guard let self, self.isEventInCanvas(event) else { return event }
                self.handleMagnify(event)
                return event
            }
        }

        func stopMonitoring() {
            if let m = scrollMonitor { NSEvent.removeMonitor(m) }
            if let m = magnifyMonitor { NSEvent.removeMonitor(m) }
            scrollMonitor = nil
            magnifyMonitor = nil
        }

        private nonisolated func isEventInCanvas(_ event: NSEvent) -> Bool {
            let window = windowLock.withLock { $0 }
            return event.window === window
        }

        private func handleScroll(_ event: NSEvent) {
            let isTrackpad = event.momentumPhase != [] || event.phase != []

            if isTrackpad {
                pan.wrappedValue = CGPoint(
                    x: pan.wrappedValue.x + event.scrollingDeltaX,
                    y: pan.wrappedValue.y + event.scrollingDeltaY
                )
            } else {
                if event.modifierFlags.contains(.shift) {
                    pan.wrappedValue = CGPoint(
                        x: pan.wrappedValue.x + event.scrollingDeltaY * 3,
                        y: pan.wrappedValue.y
                    )
                } else {
                    zoomAtCursor(magnification: event.scrollingDeltaY * 0.03, event: event)
                }
            }
            onChanged()
        }

        private func handleMagnify(_ event: NSEvent) {
            zoomAtCursor(magnification: event.magnification, event: event)
            onChanged()
        }

        /// Zoom anchored at the cursor position so the point under the cursor stays fixed.
        private func zoomAtCursor(magnification: CGFloat, event: NSEvent) {
            let oldZoom = zoom.wrappedValue
            let newZoom = min(max(oldZoom * (1.0 + magnification), CanvasViewport.minZoom), CanvasViewport.maxZoom)

            // Convert cursor from window coordinates to the canvas view's local space.
            // hostView is the NSView embedded in the canvas area via NSViewRepresentable,
            // so converting through it accounts for title bar, toolbar, and any SwiftUI
            // layout offsets automatically.
            let view = hostView
            guard let canvasView = MainActor.assumeIsolated({ view }),
                  MainActor.assumeIsolated({ canvasView.bounds.width }) > 0 else {
                zoom.wrappedValue = newZoom
                return
            }

            let windowPoint = event.locationInWindow
            let localPoint = MainActor.assumeIsolated {
                canvasView.convert(windowPoint, from: nil)
            }
            // Flip Y: NSView is bottom-left origin, SwiftUI is top-left
            let cursorX = localPoint.x
            let cursorY = MainActor.assumeIsolated { canvasView.bounds.height } - localPoint.y

            // Canvas point under cursor: canvasP = (screenP - pan) / oldZoom
            let currentPan = pan.wrappedValue
            let canvasX = (cursorX - currentPan.x) / oldZoom
            let canvasY = (cursorY - currentPan.y) / oldZoom

            // Adjust pan so the same canvas point maps to the same screen point at newZoom
            // screenP = canvasP * newZoom + newPan  =>  newPan = screenP - canvasP * newZoom
            let newPanX = cursorX - canvasX * newZoom
            let newPanY = cursorY - canvasY * newZoom

            zoom.wrappedValue = newZoom
            pan.wrappedValue = CGPoint(x: newPanX, y: newPanY)
        }
    }
}

// MARK: - Shared Node Colors

/// Centralized node-type color mapping used by LOD views, minimap, and simplified cards.
enum CanvasNodeColors {
    static func color(for itemType: String) -> Color {
        switch itemType {
        case "folderGroup": return CiderColors.controlAccent
        case "bookmark": return CiderColors.controlAccent.opacity(0.6)
        case "note": return CiderColors.warning.opacity(0.6)
        case "todo": return CiderColors.success.opacity(0.6)
        default: return CiderColors.surfaceElevated
        }
    }
}

// MARK: - Canvas Drop Zone

/// Invisible overlay that accepts dragged URLs from browsers and text, creating
/// bookmark cards at the drop location on the canvas.
struct CanvasDropZone: NSViewRepresentable {
    let zoom: CGFloat
    let pan: CGPoint
    let viewModel: CanvasViewModel

    private static let logger = Logger(subsystem: "com.cider.app", category: "CanvasDropZone")

    func makeNSView(context: Context) -> CanvasDropTargetView {
        let view = CanvasDropTargetView()
        view.onDrop = { [viewModel] screenPoint, urls in
            handleDroppedURLs(urls, at: screenPoint, in: view)
        }
        return view
    }

    func updateNSView(_ nsView: CanvasDropTargetView, context: Context) {
        nsView.onDrop = { [viewModel] screenPoint, urls in
            handleDroppedURLs(urls, at: screenPoint, in: nsView)
        }
    }

    private func handleDroppedURLs(_ urls: [URL], at viewPoint: CGPoint, in view: NSView) {
        // Convert the drop point (in view coordinates, bottom-left origin)
        // to canvas coordinates: flip Y, then reverse pan+zoom transform
        let flippedY = view.bounds.height - viewPoint.y
        let canvasX = (viewPoint.x - pan.x) / zoom
        let canvasY = (flippedY - pan.y) / zoom

        for (index, url) in urls.enumerated() {
            let offsetY = CGFloat(index) * 280 // Stack multiple drops vertically
            let dropPosition = CGPoint(x: canvasX, y: canvasY + offsetY)

            Self.logger.info("Dropped URL on canvas: \(url.absoluteString, privacy: .public)")

            if let bookmark = VaultBookmarkService.shared.add(
                urlString: url.absoluteString,
                title: url.host ?? url.absoluteString
            ) {
                let node = CanvasNode(
                    id: "node-\(bookmark.id.uuidString)",
                    itemID: bookmark.id.uuidString,
                    itemType: "bookmark",
                    position: dropPosition
                )
                viewModel.addNode(node)
            }
        }
    }
}

/// AppKit view that registers for URL/string drag types and forwards drops.
final class CanvasDropTargetView: NSView {
    var onDrop: ((_ viewPoint: CGPoint, _ urls: [URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.URL, .fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        // Accept if there's a web URL or text that looks like a URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           urls.contains(where: { !$0.isFileURL }) {
            return .copy
        }
        if let text = pasteboard.string(forType: .string),
           let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let dropPoint = convert(sender.draggingLocation, from: nil)
        var webURLs: [URL] = []

        // Collect web URLs from pasteboard
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] {
            webURLs.append(contentsOf: urls.filter { !$0.isFileURL })
        }

        // Fall back to plain text that parses as a URL
        if webURLs.isEmpty,
           let text = pasteboard.string(forType: .string),
           let url = URL(string: text), url.scheme?.hasPrefix("http") == true {
            webURLs.append(url)
        }

        guard !webURLs.isEmpty else { return false }

        DispatchQueue.main.async { [onDrop] in
            onDrop?(dropPoint, webURLs)
        }
        return true
    }
}
