import SwiftUI

/// Raycast-style Acrylic background for the sidebar.
/// Uses a deep material with dark overlay for high contrast and readability.
struct SidebarBackgroundView: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            opaqueBackground
        } else {
            acrylicBackground
        }
    }

    @ViewBuilder
    private var acrylicBackground: some View {
        ZStack {
            // Shadow layer - drawn as a blurred shape behind content
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .blur(radius: 35)
                .offset(y: 20)
                .opacity(0.7)

            // Main content
            ZStack {
                // 1. Deep Acrylic Base - samples the desktop wallpaper
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)

                // 2. Dark overlay for contrast and saturation boost
                Color.black.opacity(0.45)

                // 3. Subtle inner material layer for depth
                Color.white.opacity(0.03)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // 4. Crisp border - Raycast's signature edge
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        // Solid background when Reduce Transparency is enabled
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(CiderColors.separator.opacity(0.5), lineWidth: 1)
            )
        }
}
