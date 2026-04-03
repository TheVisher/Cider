import SwiftUI

struct UtilityPanelShell<Content: View>: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator
    let onClose: () -> Void
    let onMaximize: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AcrylicPanelBackground(
                cornerRadius: UtilityPanelDesign.cornerRadius
            )

            VStack(spacing: 0) {
                UtilityPanelHeaderBar(
                    coordinator: coordinator,
                    onClose: onClose,
                    onMaximize: onMaximize
                )

                Rectangle()
                    .fill(CiderColors.borderSubtle)
                    .frame(height: Spacing.hairline)
                    .padding(.horizontal, Spacing.md)

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: UtilityPanelDesign.cornerRadius, style: .continuous))
        .overlay {
            PanelEdgeResizeView(
                minWidth: UtilityPanelDesign.panelMinWidth,
                minHeight: UtilityPanelDesign.panelMinHeight,
                shadowPadding: 0,
                topPadding: 0,
                bottomPadding: 0,
                resizeCornerSize: 28,
                resizeEdgeThickness: 12
            )
        }
    }
}
