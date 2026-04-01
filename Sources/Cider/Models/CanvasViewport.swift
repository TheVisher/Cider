import Foundation

/// Canvas camera state — zoom level and pan offset.
struct CanvasViewport: Codable, Equatable, Sendable {
    var offset: CGPoint
    var zoom: CGFloat

    static let `default` = CanvasViewport(offset: .zero, zoom: 1.0)

    static let minZoom: CGFloat = 0.1
    static let maxZoom: CGFloat = 2.0
}
