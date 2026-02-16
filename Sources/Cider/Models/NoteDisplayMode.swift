import CoreGraphics

enum NoteDisplayMode: String, Codable, CaseIterable {
    case list
    case grid
    case masonry

    var displayName: String {
        switch self {
        case .list:
            "List"
        case .grid:
            "Grid"
        case .masonry:
            "Masonry"
        }
    }

    var icon: String {
        switch self {
        case .list:
            "list.bullet"
        case .grid:
            "square.grid.2x2"
        case .masonry:
            "rectangle.grid.1x2"
        }
    }
}

struct NoteCardSizing {
    let scale: Double

    /// Minimum card width — wider than bookmarks since notes are text-forward
    var cardMinWidth: CGFloat { interpolate(200, 250, 350, 520) }
    /// Text preview area height in grid mode (fixed-height cards)
    var previewHeight: CGFloat { interpolate(80, 100, 140, 200) }
    /// Side image width in card view
    var imageWidth: CGFloat { interpolate(60, 80, 110, 160) }
    /// Square thumbnail size in list view
    var listImageSize: CGFloat { interpolate(36, 44, 56, 72) }

    private func interpolate(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat) -> CGFloat {
        let stops = [a, b, c, d]
        let clamped = min(max(scale, 0), 3)
        let lower = Int(clamped)
        let upper = min(lower + 1, 3)
        let frac = CGFloat(clamped - Double(lower))
        return stops[lower] + frac * (stops[upper] - stops[lower])
    }
}
