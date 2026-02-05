import SwiftUI

struct PinnedAppsSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            SettingsSection(title: "Pinned Apps") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Manage your pinned applications here.")
                        .font(.body)
                        .foregroundColor(CiderColors.secondary)

                    HStack(spacing: Spacing.md) {
                        Button(action: {}) {
                            Label("Add App", systemImage: "plus")
                        }
                        .buttonStyle(SettingsButtonStyle())

                        Button(action: {}) {
                            Label("Import from Dock", systemImage: "arrow.down.doc")
                        }
                        .buttonStyle(SettingsButtonStyle())
                    }
                }
            }

            SettingsSection(title: "Folders") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Create folders to organize your pinned apps.")
                        .font(.body)
                        .foregroundColor(CiderColors.secondary)

                    Button(action: {}) {
                        Label("Create Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(SettingsButtonStyle())
                }
            }

            Spacer()
        }
    }
}

// MARK: - Settings Button Style

struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundColor(CiderColors.primary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.08 : 0.05))
            )
    }
}
