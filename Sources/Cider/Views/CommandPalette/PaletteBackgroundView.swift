import SwiftUI

struct PaletteBackgroundView: View {
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
            // Shadow layer - tighter, stronger, pushed down significantly
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .blur(radius: 18)
                .offset(y: 18)
                .opacity(0.7)

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
