import SwiftUI

// MARK: - Shared Button Styles

/// Primary action pill button — accent-colored text on subtle accent background.
/// Use for primary actions: Save, Create, Sign In, Open Settings.
struct CiderAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(CiderColors.controlAccent)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? CiderColors.accentLight : CiderColors.accentSubtle)
            )
    }
}

/// Destructive action pill button — red text on subtle red background.
/// Use for dangerous actions: Delete, Reset, Remove.
struct CiderDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(CiderColors.destructive)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? CiderColors.destructiveLight : CiderColors.destructiveSubtle)
            )
    }
}

/// Secondary/neutral pill button — muted text on neutral surface background.
/// Use for dismiss/cancel actions alongside a primary button.
struct CiderSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? CiderColors.surfaceHover : CiderColors.surfaceInput)
            )
    }
}
