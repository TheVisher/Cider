import SwiftUI

struct CollapsiblePinnedSection<Content: View>: View {
    @Binding var isCollapsed: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !isCollapsed {
            content()
                .background {
                    if reduceTransparency {
                        Color(nsColor: NSColor.windowBackgroundColor)
                    } else {
                        VisualEffectView(
                            material: .underWindowBackground,
                            blendingMode: .withinWindow
                        )
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
