import SwiftUI

struct PaletteFooterBar: View {
    let onSettingsClick: () -> Void
    @Environment(\.textScale) private var textScale

    @State private var isShowingShortcuts = false

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

                // Keyboard shortcuts button
                Image(systemName: "keyboard")
                    .font(.system(size: 11 * textScale))
                    .foregroundColor(CiderColors.secondary)
                    .onHover { hovering in
                        isShowingShortcuts = hovering
                    }
                    .popover(isPresented: $isShowingShortcuts, arrowEdge: .top) {
                        TilingShortcutsPopover()
                    }
                    .accessibilityLabel("Tiling shortcuts")

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
                .accessibilityLabel("Settings")
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

// MARK: - Tiling Shortcuts Popover

private struct TilingShortcutsPopover: View {
    private struct ShortcutEntry {
        let keys: String
        let label: String
    }

    private struct ShortcutSection {
        let title: String
        let entries: [ShortcutEntry]
    }

    private let sections: [ShortcutSection] = [
        ShortcutSection(title: "Halves", entries: TilePosition.halves.map {
            ShortcutEntry(keys: $0.shortcutLabel, label: $0.displayName)
        }),
        ShortcutSection(title: "Quarters", entries: TilePosition.quarters.map {
            ShortcutEntry(keys: $0.shortcutLabel, label: $0.displayName)
        }),
        ShortcutSection(title: "Thirds", entries: TilePosition.thirds.map {
            ShortcutEntry(keys: $0.shortcutLabel, label: $0.displayName)
        }),
        ShortcutSection(title: "Two-Thirds", entries: TilePosition.twoThirds.map {
            ShortcutEntry(keys: $0.shortcutLabel, label: $0.displayName)
        }),
        ShortcutSection(title: "Other", entries: TilePosition.other.map {
            ShortcutEntry(keys: $0.shortcutLabel, label: $0.displayName)
        }),
        ShortcutSection(title: "Actions", entries: [
            ShortcutEntry(keys: "⌃⌥=", label: "Larger"),
            ShortcutEntry(keys: "⌃⌥-", label: "Smaller"),
            ShortcutEntry(keys: "⌃⌥⌫", label: "Restore"),
            ShortcutEntry(keys: "⌃⌥⌘→", label: "Next Display"),
            ShortcutEntry(keys: "⌃⌥⌘←", label: "Prev Display"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Tiling Shortcuts")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(CiderColors.primary)

            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(section.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CiderColors.tertiary)

                    ForEach(Array(section.entries.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.keys)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(CiderColors.tertiary)
                                .frame(width: 60, alignment: .leading)
                            Text(entry.label)
                                .font(.system(size: 11))
                                .foregroundColor(CiderColors.secondary)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .frame(width: 200)
    }
}
