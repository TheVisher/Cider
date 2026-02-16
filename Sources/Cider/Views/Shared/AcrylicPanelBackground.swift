import SwiftUI

struct AcrylicPanelBackground: View {
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
                CiderColors.acrylicTint
                CiderColors.surfaceHighlight
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
        }
    }

    private func shadowMetrics(for style: ShadowStyle) -> (blur: CGFloat, yOffset: CGFloat, opacity: Double) {
        switch style {
        case .full:
            return (blur: 18, yOffset: 18, opacity: CiderColors.shadowShapeFullOpacity)
        case .compact:
            return (blur: 10, yOffset: 8, opacity: CiderColors.shadowShapeCompactOpacity)
        }
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.separatorStrong, lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
    }
}
