import SwiftUI

struct PaletteBackgroundView: View {
    let cornerRadius: CGFloat
    var shadowStyle: ShadowStyle = .full
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    enum ShadowStyle {
        case full
        case compact
    }

    var body: some View {
        if reduceTransparency {
            opaqueBackground
        } else {
            acrylicBackground
        }
    }

    @ViewBuilder
    private var acrylicBackground: some View {
        let metrics = shadowMetrics(for: shadowStyle)
        ZStack {
            // Panel shadow (compact for collapsed notes, full for larger panels)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .blur(radius: metrics.blur)
                .offset(y: metrics.yOffset)
                .opacity(metrics.opacity)

            // Main content
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                Color.black.opacity(0.45)
                Color.white.opacity(0.03)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
        }
    }

    private func shadowMetrics(for style: ShadowStyle) -> (blur: CGFloat, yOffset: CGFloat, opacity: Double) {
        switch style {
        case .full:
            return (blur: 18, yOffset: 18, opacity: 0.7)
        case .compact:
            return (blur: 10, yOffset: 8, opacity: 0.52)
        }
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.separator.opacity(0.5), lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
    }
}
