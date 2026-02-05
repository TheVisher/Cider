import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @State private var showOnScreen: ShowOnScreenOption = .mouseScreen

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Window Behavior") {
                SettingsToggleRow(
                    title: "Auto-hide inactive apps",
                    subtitle: "Hide other apps when focusing a window (like Stage Manager)",
                    isOn: $viewModel.autoHideApps
                )
            }

            SettingsSection(title: "Display") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Show Cider on")
                        .font(.body)
                        .foregroundColor(CiderColors.primary)

                    Picker("", selection: $showOnScreen) {
                        ForEach(ShowOnScreenOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 250)
                }
            }

            SettingsSection(title: "Accessibility") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Button(action: openAccessibilityPreferences) {
                        Label("Open Accessibility Settings", systemImage: "hand.raised")
                    }
                    .buttonStyle(SettingsButtonStyle())

                    Text("Cider requires accessibility permissions to manage windows.")
                        .font(.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            SettingsSection(title: "Reset") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Button(action: {}) {
                        Label("Reset All Settings", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(SettingsDestructiveButtonStyle())

                    Text("This will reset all settings to their default values.")
                        .font(.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
            }

            Spacer()
        }
    }

    private func openAccessibilityPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Show On Screen Option

enum ShowOnScreenOption: String, CaseIterable {
    case mouseScreen = "Screen containing mouse"
    case mainScreen = "Main screen"
    case lastUsedScreen = "Last used screen"
}

// MARK: - Destructive Button Style

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
