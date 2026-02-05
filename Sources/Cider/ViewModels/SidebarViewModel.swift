import Foundation
import Combine

final class SidebarViewModel: ObservableObject {
    enum Section: Hashable {
        case pinnedApps
        case windows
    }

    @Published var hoveredSection: Section? = nil
    @Published var isExpanded: Bool = true
    @Published private(set) var config: CiderConfig

    init(config: CiderConfig = CiderConfig.load()) {
        self.config = config
    }

    func reloadConfig() {
        config = CiderConfig.load()
    }

    var sectionWeights: [Section: CGFloat] {
        if let hovered = hoveredSection {
            return [
                .pinnedApps: hovered == .pinnedApps ? CiderDesign.hoverExpandWeight : CiderDesign.hoverContractWeight,
                .windows: hovered == .windows ? CiderDesign.hoverExpandWeight : CiderDesign.hoverContractWeight
            ]
        }
        return [
            .pinnedApps: 1,
            .windows: 1
        ]
    }
}
