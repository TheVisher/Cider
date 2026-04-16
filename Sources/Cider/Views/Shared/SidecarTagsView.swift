import SwiftUI

/// Displays lightweight imported metadata tags.
/// These are visually distinct from Cider labels and currently appear when
/// legacy sidecar tags have been absorbed into the item model.
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
