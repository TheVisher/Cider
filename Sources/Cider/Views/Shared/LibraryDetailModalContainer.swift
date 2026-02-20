import SwiftUI

/// Shared modal chrome for date-card and contact detail overlays.
/// Matches the acrylic container, traffic lights, clip shape, and border
/// used by BookmarkDetailsSheet.
struct LibraryDetailModalContainer<Content: View>: View {
    let onClose: () -> Void
    let onEdit: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Traffic lights header
            HStack(spacing: NotesDesign.trafficLightSpacing) {
                BookmarksTrafficLightButton(
                    color: .systemRed,
                    symbol: "xmark",
                    help: "Close",
                    action: onClose
                )
                BookmarksTrafficLightButton(
                    color: .systemYellow,
                    symbol: "minus",
                    help: "Close",
                    action: onClose
                )
                BookmarksTrafficLightButton(
                    color: .systemGreen,
                    symbol: "pencil",
                    help: "Edit",
                    action: onEdit ?? onClose
                )
            }

            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                CiderColors.acrylicOverlayTint
                CiderColors.surfaceSubtle
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(
                cornerRadius: Radius.lg - CiderBorder.innerStrokeInset,
                style: .continuous
            )
            .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
            .padding(CiderBorder.innerStrokeInset)
        )
    }
}
