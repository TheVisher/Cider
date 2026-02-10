import SwiftUI
import AppKit

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
                SettingsPickerRow(
                    title: "Option key activation",
                    subtitle: "How to open the command palette",
                    selection: $viewModel.activationMode,
                    options: ActivationMode.allCases,
                    label: { $0.displayName }
                )

                if viewModel.activationMode == .doubleTap {
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

            // Window tiling section
            SettingsSection(title: "Window Tiling") {
                SettingsToggleRow(
                    title: "Tiling hotkeys (Ctrl+Option)",
                    subtitle: "Rectangle-style shortcuts to tile windows",
                    isOn: $viewModel.enableTilingHotkeys
                )

                SettingsToggleRow(
                    title: "Dynamic tiling",
                    subtitle: "Auto-pair windows when tiling to half zones",
                    isOn: $viewModel.enableDynamicTiling
                )
            }

            // Notes section
            SettingsSection(title: "Notes") {
                SettingsToggleRow(
                    title: "Option+N to open notes",
                    subtitle: "Quick-launch floating notes panel",
                    isOn: $viewModel.enableNotesHotkey
                )

                SettingsToggleRow(
                    title: "Remember note window position",
                    subtitle: "Reopen each note where you last closed it",
                    isOn: $viewModel.rememberNotesPanelPositionPerNote
                )

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notes directory")
                            .font(.body)
                            .foregroundColor(CiderColors.primary)

                        Text(viewModel.notesDirectory)
                            .font(.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button("Choose...") {
                        chooseNotesDirectory()
                    }
                    .controlSize(.small)
                }
            }

            // Palette behavior section
            SettingsSection(title: "Palette Behavior") {
                SettingsToggleRow(
                    title: "Remember palette state",
                    subtitle: "Keep folders open between palette sessions",
                    isOn: $viewModel.rememberPaletteState
                )
            }

            Spacer()
        }
    }

    private func chooseNotesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Select a directory for Cider notes"

        if panel.runModal() == .OK, let url = panel.url {
            // Store with tilde for home directory
            let path = url.path
            let home = NSHomeDirectory()
            if path.hasPrefix(home) {
                viewModel.notesDirectory = "~" + path.dropFirst(home.count)
            } else {
                viewModel.notesDirectory = path
            }
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

struct SettingsPickerRow<T: Hashable>: View {
    let title: String
    let subtitle: String?
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    init(title: String, subtitle: String? = nil, selection: Binding<T>, options: [T], label: @escaping (T) -> String) {
        self.title = title
        self.subtitle = subtitle
        self._selection = selection
        self.options = options
        self.label = label
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

            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: 140)
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
