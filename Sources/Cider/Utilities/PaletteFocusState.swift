import Foundation

// MARK: - Palette Section

enum PaletteSection: Hashable, CaseIterable {
    case search
    case apps
    case content
}

// MARK: - Palette Focus State

struct PaletteFocusState: Equatable {
    var section: PaletteSection = .search
    var appsIndex: Int = 0
    var contentIndex: Int = 0

    static let initial = PaletteFocusState()
}
