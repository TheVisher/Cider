import SwiftUI

struct PaletteFooterBar: View {
    let onSettingsClick: () -> Void
    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Left side - Cider icon/branding
            Image(systemName: "cube.fill")
                .font(.system(size: 11 * textScale))
                .foregroundColor(CiderColors.tertiary)

            Spacer()

            // Right side - Actions and shortcuts
            HStack(spacing: Spacing.lg) {
                // Primary action hint
                FooterAction(label: "Open", shortcut: "↵")

                Divider()
                    .frame(height: 12 * textScale)
                    .opacity(0.3)

                // Actions menu
                FooterAction(label: "Actions", shortcut: "⌘K")

                Divider()
                    .frame(height: 12 * textScale)
                    .opacity(0.3)

                // Settings button
                Button(action: onSettingsClick) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11 * textScale))
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .background(Color.white.opacity(0.03))
    }
}

// MARK: - Footer Action

private struct FooterAction: View {
    let label: String
    let shortcut: String
    @Environment(\.textScale) private var textScale

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Text(label)
                .font(.system(size: 11 * textScale))
                .foregroundColor(CiderColors.secondary)

            Text(shortcut)
                .font(.system(size: 10 * textScale, weight: .medium))
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                )
        }
    }
}
