import SwiftUI

struct ConnectedDevicesView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "laptopcomputer")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: SettingsDesign.deviceIconColumnWidth)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text("Device sync unavailable")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.primary)

                    Text("Remote device management was removed with the old sync backend.")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
    }
}
