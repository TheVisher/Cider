import SwiftUI

struct CollapsiblePinnedSection<Content: View>: View {
    @Binding var isCollapsed: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if !isCollapsed {
            content()
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
