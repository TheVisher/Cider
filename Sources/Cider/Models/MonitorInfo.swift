import Foundation
import CoreGraphics

struct MonitorInfo: Identifiable, Hashable {
    let id: UInt32  // CGDirectDisplayID
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isPrimary: Bool
    var relativePosition: RelativePosition

    enum RelativePosition: String, CaseIterable {
        case primary
        case left
        case right
        case top
        case bottom

        var displayName: String {
            switch self {
            case .primary: return "Main"
            case .left: return "Left"
            case .right: return "Right"
            case .top: return "Top"
            case .bottom: return "Bottom"
            }
        }

        var icon: String {
            switch self {
            case .primary: return "display"
            case .left: return "rectangle.lefthalf.inset.filled.arrow.left"
            case .right: return "rectangle.righthalf.inset.filled.arrow.right"
            case .top: return "rectangle.tophalf.inset.filled"
            case .bottom: return "rectangle.bottomhalf.inset.filled"
            }
        }
    }

    var displayName: String {
        if isPrimary {
            return "\(name) (Main)"
        }
        return "\(name) (\(relativePosition.displayName))"
    }
}
