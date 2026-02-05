import SwiftUI

struct SectionFrameKey: PreferenceKey {
    static let defaultValue: [SidebarViewModel.Section: CGRect] = [:]

    static func reduce(value: inout [SidebarViewModel.Section: CGRect], nextValue: () -> [SidebarViewModel.Section: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
