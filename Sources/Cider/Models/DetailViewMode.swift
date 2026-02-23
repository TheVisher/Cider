import Foundation

enum DetailViewMode: String, Codable, CaseIterable {
    case slideOut
    case fullPanel
    case page

    var displayName: String {
        switch self {
        case .slideOut: return "Slide-out"
        case .fullPanel: return "Full panel"
        case .page: return "Page"
        }
    }
}
