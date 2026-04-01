import SwiftUI

/// Draggable minimap overlay showing all canvas nodes and the current viewport rect.
struct CanvasMinimapView: View {
    @ObservedObject var viewModel: CanvasViewModel
    let viewportSize: CGSize
    let currentZoom: CGFloat
    let currentPan: CGPoint
    var onNavigate: (CGPoint) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var isDragging = false

    private let minimapWidth: CGFloat = 180
    private let minimapHeight: CGFloat = 120

    var body: some View {
        let bounds = contentBounds
        let scale = minimapScale(for: bounds)

        ZStack(alignment: .topLeading) {
            // Background
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: 1)
                )

            // Node rectangles
            ForEach(viewModel.nodes.filter { $0.parentNodeID == nil }) { node in
                let x = (node.position.x - bounds.minX) * scale
                let y = (node.position.y - bounds.minY) * scale
                let w = max(4, node.size.width * scale)
                let h = max(3, node.size.height * scale)

                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(nodeColor(for: node))
                    .frame(width: w, height: h)
                    .offset(x: x, y: y)
            }

            // Viewport indicator
            viewportRect(bounds: bounds, scale: scale)
        }
        .frame(width: minimapWidth, height: minimapHeight)
        .opacity(isHovered || isDragging ? 1.0 : 0.6)
        .animation(reduceMotion ? .none : .snappy(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .gesture(minimapDragGesture(bounds: bounds, scale: scale))
    }

    // MARK: - Content Bounds

    private var contentBounds: CGRect {
        let topLevel = viewModel.nodes.filter { $0.parentNodeID == nil }
        guard !topLevel.isEmpty else {
            return CGRect(x: 0, y: 0, width: 2000, height: 1500)
        }

        var minX = CGFloat.infinity, minY = CGFloat.infinity
        var maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for node in topLevel {
            minX = min(minX, node.position.x)
            minY = min(minY, node.position.y)
            maxX = max(maxX, node.position.x + node.size.width)
            maxY = max(maxY, node.position.y + node.size.height)
        }

        // Also include current viewport so it's always on the minimap
        let vpMinX = -currentPan.x / currentZoom
        let vpMinY = -currentPan.y / currentZoom
        let vpMaxX = vpMinX + viewportSize.width / currentZoom
        let vpMaxY = vpMinY + viewportSize.height / currentZoom
        minX = min(minX, vpMinX)
        minY = min(minY, vpMinY)
        maxX = max(maxX, vpMaxX)
        maxY = max(maxY, vpMaxY)

        let pad: CGFloat = 200
        return CGRect(
            x: minX - pad,
            y: minY - pad,
            width: (maxX - minX) + pad * 2,
            height: (maxY - minY) + pad * 2
        )
    }

    private func minimapScale(for bounds: CGRect) -> CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(minimapWidth / bounds.width, minimapHeight / bounds.height)
    }

    // MARK: - Viewport Rect

    @ViewBuilder
    private func viewportRect(bounds: CGRect, scale: CGFloat) -> some View {
        // Visible area in canvas coords
        let visMinX = -currentPan.x / currentZoom
        let visMinY = -currentPan.y / currentZoom
        let visW = viewportSize.width / currentZoom
        let visH = viewportSize.height / currentZoom

        let vpX = (visMinX - bounds.minX) * scale
        let vpY = (visMinY - bounds.minY) * scale
        let vpW = visW * scale
        let vpH = visH * scale

        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .frame(width: max(8, vpW), height: max(6, vpH))
            .offset(x: vpX, y: vpY)
    }

    // MARK: - Node Colors

    private func nodeColor(for node: CanvasNode) -> Color {
        CanvasNodeColors.color(for: node.itemType)
    }

    // MARK: - Navigation

    private func minimapDragGesture(bounds: CGRect, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                navigateToMinimapPoint(value.location, bounds: bounds, scale: scale)
            }
            .onEnded { _ in
                isDragging = false
            }
    }

    private func navigateToMinimapPoint(_ point: CGPoint, bounds: CGRect, scale: CGFloat) {
        guard scale > 0 else { return }

        // Convert minimap point to canvas coordinates (center of viewport there)
        let canvasX = point.x / scale + bounds.minX
        let canvasY = point.y / scale + bounds.minY

        // Pan so this canvas point is centered in the viewport
        let panX = -canvasX * currentZoom + viewportSize.width / 2
        let panY = -canvasY * currentZoom + viewportSize.height / 2

        onNavigate(CGPoint(x: panX, y: panY))
    }
}
