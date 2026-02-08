import SwiftUI

struct TileZoneOverlayView: View {
    let monitor: MonitorInfo
    let onTile: ([CGWindowID], TilePosition) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeZone: TilePosition?

    /// Edge zone fraction of screen dimension
    private let edgeFraction: CGFloat = 0.15

    private var screenWidth: CGFloat { monitor.frame.width }
    private var screenHeight: CGFloat { monitor.frame.height }
    private var edgeW: CGFloat { screenWidth * edgeFraction }
    private var edgeH: CGFloat { screenHeight * edgeFraction }

    var body: some View {
        ZStack {
            // Dim background when a zone is active
            Color.black.opacity(activeZone != nil ? 0.08 : 0.0)
                .animation(reduceMotion ? .none : CiderAnimation.snappy, value: activeZone)

            // Zone preview rectangle
            if let zone = activeZone {
                tilePreview(for: zone)
                    .transition(.opacity)
            }

            // Drop zone grid (invisible hit areas)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    dropZone(.topLeft, width: edgeW, height: edgeH)
                    dropZone(.top, width: screenWidth - edgeW * 2, height: edgeH)
                    dropZone(.topRight, width: edgeW, height: edgeH)
                }
                HStack(spacing: 0) {
                    dropZone(.left, width: edgeW, height: screenHeight - edgeH * 2)
                    // Center: no zone, just a clear area that accepts drops to cancel
                    Color.clear
                        .frame(width: screenWidth - edgeW * 2, height: screenHeight - edgeH * 2)
                        .dropDestination(for: String.self) { items, _ in
                            // Drop in center = cancel (no tile)
                            return false
                        } isTargeted: { targeted in
                            if targeted { activeZone = nil }
                        }
                    dropZone(.right, width: edgeW, height: screenHeight - edgeH * 2)
                }
                HStack(spacing: 0) {
                    dropZone(.bottomLeft, width: edgeW, height: edgeH)
                    dropZone(.bottom, width: screenWidth - edgeW * 2, height: edgeH)
                    dropZone(.bottomRight, width: edgeW, height: edgeH)
                }
            }
        }
        .frame(width: screenWidth, height: screenHeight)
    }

    @ViewBuilder
    private func dropZone(_ position: TilePosition, width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, position: position)
            } isTargeted: { targeted in
                withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
                    activeZone = targeted ? position : (activeZone == position ? nil : activeZone)
                }
            }
    }

    private func handleDrop(items: [String], position: TilePosition) -> Bool {
        guard let idString = items.first else { return false }
        // Supports both single-window drag and app-group drag payloads.
        let windowIDs = idString.split(separator: ",").compactMap { CGWindowID($0) }
        guard !windowIDs.isEmpty else { return false }
        onTile(windowIDs, position)
        return true
    }

    @ViewBuilder
    private func tilePreview(for position: TilePosition) -> some View {
        let tileFrame = WindowManager.calculateTileFrameStatic(position: position, on: monitor)
        // Convert from screen coordinates to overlay-local coordinates
        // Screen coords: bottom-left origin. SwiftUI overlay: top-left origin at monitor.frame.origin
        let localX = tileFrame.minX - monitor.frame.minX
        // Flip Y: screen Y is bottom-up, SwiftUI Y is top-down within the overlay
        let localY = (monitor.frame.maxY - tileFrame.maxY)

        ZStack {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Color.white.opacity(0.10))
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: CiderBorder.innerStrokeWidth)

            // Zone label
            VStack(spacing: Spacing.sm) {
                Image(systemName: position.icon)
                    .font(.system(size: 28, weight: .medium))
                Text(position.displayName)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundColor(CiderColors.primary.opacity(0.8))
        }
        .frame(width: tileFrame.width, height: tileFrame.height)
        .position(x: localX + tileFrame.width / 2, y: localY + tileFrame.height / 2)
    }
}
