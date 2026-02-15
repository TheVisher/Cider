import SwiftUI

// MARK: - Button Styles

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(CiderColors.controlAccent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.controlAccent.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
    }
}

struct SettingsDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(.red)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.red.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
    }
}
