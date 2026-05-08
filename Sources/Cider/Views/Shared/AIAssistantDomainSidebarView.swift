import SwiftUI

struct AIAssistantDomainSidebarView: View {
    let onOpenAssistant: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button(action: onOpenAssistant) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "sparkles")
                        .font(CiderFont.bodySemibold)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: Spacing.xl, height: Spacing.xl)

                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text("Assistant Chat")
                            .font(CiderFont.labelSemibold)
                            .foregroundColor(CiderColors.primary)
                        Text("Ask Cider or run agent workflows")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.10))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the embedded AI Assistant")

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Label("The assistant is a global utility, not a folder collection.", systemImage: "info.circle")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.secondary)
                Text("Use Browse to return to all saved views, folders, and boards.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separatorLight.opacity(0.45))
            )
            .padding(.horizontal, Spacing.xs)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xs)
    }
}
