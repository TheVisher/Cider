import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            // Startup section
            SettingsSection(title: "Startup") {
                SettingsToggleRow(
                    title: "Launch Cider at login",
                    subtitle: "Automatically start Cider when you log in",
                    isOn: $viewModel.launchAtLogin
                )
            }

            // Hotkey section
            SettingsSection(title: "Activation") {
                SettingsToggleRow(
                    title: "Double-tap Option to open",
                    subtitle: "Quickly access the command palette",
                    isOn: $viewModel.hotkeyEnabled
                )

                if viewModel.hotkeyEnabled {
                    SettingsSliderRow(
                        title: "Double-tap speed",
                        value: $viewModel.hotkeyDoubleTapInterval,
                        range: 0.2...0.5,
                        labels: ("Fast", "Slow")
                    )
                }
            }

            // Window cycling section
            SettingsSection(title: "Window Cycling") {
                SettingsToggleRow(
                    title: "Option+Tab to cycle windows",
                    subtitle: "Quick window switching like Cmd+Tab",
                    isOn: $viewModel.enableOptionTabCycling
                )

                if viewModel.enableOptionTabCycling {
                    SettingsToggleRow(
                        title: "Cycle windows on all screens",
                        subtitle: "Include windows from all displays",
                        isOn: $viewModel.optionTabCycleAllScreens
                    )
                }
            }

            Spacer()
        }
    }
}

// MARK: - Reusable Settings Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(CiderColors.secondary)

            VStack(alignment: .leading, spacing: Spacing.md) {
                content
            }
        }
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(CiderColors.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}

struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let labels: (String, String)

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(.body)
                .foregroundColor(CiderColors.primary)

            HStack(spacing: Spacing.md) {
                Text(labels.0)
                    .font(.caption)
                    .foregroundColor(CiderColors.tertiary)

                Slider(value: $value, in: range)
                    .tint(CiderColors.controlAccent)

                Text(labels.1)
                    .font(.caption)
                    .foregroundColor(CiderColors.tertiary)
            }
        }
    }
}
