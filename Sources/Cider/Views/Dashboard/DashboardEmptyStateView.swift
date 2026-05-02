import SwiftUI

struct DashboardEmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)

            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: DashboardEmptyStateDesign.messageWidth)
            }
        }
        .padding(Spacing.xxl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                )
        )
    }
}

private enum DashboardEmptyStateDesign {
    static let messageWidth: CGFloat = 320
}
