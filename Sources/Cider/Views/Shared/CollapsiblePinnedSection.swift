import SwiftUI

struct CollapsiblePinnedSection<Content: View>: View {
    @Binding var isCollapsed: Bool
    @ViewBuilder var content: () -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if !isCollapsed {
            VStack(spacing: 0) {
                content()

                Rectangle()
                    .fill(CiderColors.separator)
                    .frame(height: Spacing.hairline)
            }
            .background {
                if reduceTransparency {
                    Color(nsColor: NSColor.windowBackgroundColor)
                } else {
                    ZStack {
                        VisualEffectView(
                            material: .underWindowBackground,
                            blendingMode: .withinWindow
                        )
                        Color.black.opacity(0.45)
                        Color.white.opacity(0.03)
                    }
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
