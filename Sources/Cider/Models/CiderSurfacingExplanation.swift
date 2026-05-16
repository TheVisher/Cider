import Foundation

struct CiderSurfacingExplanation: Codable, Equatable {
    let reason: String
    let urgency: String
    let sourceSignal: String
    let reviewState: String
    let suggestedAction: String
    let actionURLString: String?
}
