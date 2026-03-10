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
                    .padding(.horizontal, Spacing.xs + 2)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .fill(CiderColors.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                            .stroke(CiderColors.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
    }
}
