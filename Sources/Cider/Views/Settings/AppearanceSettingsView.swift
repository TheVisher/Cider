import SwiftUI

struct AppearanceSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            // Text Size
            SettingsSection(title: "Text Size") {
                HStack(spacing: Spacing.md) {
                    ForEach(TextSize.allCases, id: \.self) { size in
                        SizeOptionButton(
                            title: size.displayName,
                            preview: "Aa",
                            previewSize: 14 * size.scale,
                            isSelected: viewModel.textSize == size,
                            action: { viewModel.textSize = size }
                        )
                    }
                }
            }

            // Window Size
            SettingsSection(title: "Window Size") {
                HStack(spacing: Spacing.md) {
                    ForEach(PaletteSize.allCases, id: \.self) { size in
                        SizeOptionButton(
                            title: size.displayName,
                            preview: nil,
                            previewSize: nil,
                            isSelected: viewModel.paletteSize == size,
                            action: { viewModel.paletteSize = size },
                            icon: windowIcon(for: size)
                        )
                    }
                }

                Text("Changes apply when you reopen the command palette")
                    .font(.caption)
                    .foregroundColor(CiderColors.tertiary)
            }

            // Sidebar
            SettingsSection(title: "Sidebar") {
                SettingsToggleRow(
                    title: "Enable sidebar",
                    subtitle: "Show the sidebar when hovering near screen edge",
                    isOn: $viewModel.sidebarEnabled
                )

                if viewModel.sidebarEnabled {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        Text("Position")
                            .font(.body)
                            .foregroundColor(CiderColors.primary)

                        HStack(spacing: Spacing.md) {
                            EdgeOptionButton(
                                title: "Left",
                                icon: "sidebar.left",
                                isSelected: viewModel.sidebarEdge == .left,
                                action: { viewModel.sidebarEdge = .left }
                            )

                            EdgeOptionButton(
                                title: "Right",
                                icon: "sidebar.right",
                                isSelected: viewModel.sidebarEdge == .right,
                                action: { viewModel.sidebarEdge = .right }
                            )
                        }
                    }
                }
            }

            // Menu Bar
            SettingsSection(title: "Menu Bar") {
                SettingsToggleRow(
                    title: "Show in menu bar",
                    subtitle: "Display Cider icon in the system menu bar",
                    isOn: $viewModel.showMenuBarIcon
                )
            }

            Spacer()
        }
    }

    private func windowIcon(for size: PaletteSize) -> String {
        switch size {
        case .small: return "rectangle.portrait"
        case .medium: return "rectangle"
        case .large: return "rectangle.expand.vertical"
        }
    }
}

// MARK: - Size Option Button

private struct SizeOptionButton: View {
    let title: String
    let preview: String?
    let previewSize: CGFloat?
    let isSelected: Bool
    let action: () -> Void
    var icon: String? = nil

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                if let preview, let previewSize {
                    Text(preview)
                        .font(.system(size: previewSize, weight: .medium))
                        .frame(width: 50, height: 32)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .frame(width: 50, height: 32)
                }

                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.controlAccent : Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edge Option Button

private struct EdgeOptionButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .frame(width: 50, height: 32)

                Text(title)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.08 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(isSelected ? CiderColors.controlAccent : Color.white.opacity(0.1), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
