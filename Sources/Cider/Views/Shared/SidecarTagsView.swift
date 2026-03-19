import SwiftUI

/// Displays sidecar metadata tags as lightweight text pills.
/// Visually distinct from Cider labels — these come from AI tools
/// or `.cider-meta.json` files in the vault.
struct SidecarTagsView: View {
    let tags: [String]

    var body: some View {
        TagFlowLayout(spacing: Spacing.xs) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(CiderFont.micro)
                    .foregroundColor(CiderColors.secondary)
                    .padding(.horizontal, Spacing.xs + Spacing.xxs)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.sidecarTagFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .stroke(CiderColors.sidecarTagBorder, lineWidth: CiderBorder.hairlineStrokeWidth)
                    )
            }
        }
    }
}
