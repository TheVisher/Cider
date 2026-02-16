import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // App icon and name
            VStack(spacing: Spacing.md) {
                Image(systemName: "cube.fill")
                    .font(CiderFont.appIcon)
                    .foregroundColor(CiderColors.controlAccent)

                Text("Cider")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(CiderColors.primary)

                Text("Version \(appVersion)")
                    .font(.body)
                    .foregroundColor(CiderColors.secondary)
            }

            // Description
            Text("A command palette for macOS that replaces\nDock, Stage Manager, and Spotlight.")
                .font(.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)

            // Links
            HStack(spacing: Spacing.xl) {
                AboutLink(title: "Website", icon: "globe", url: "https://github.com")
                AboutLink(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com")
                AboutLink(title: "Twitter", icon: "at", url: "https://twitter.com")
            }

            Spacer()

            // Copyright
            Text("Made with care for macOS")
                .font(.caption)
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - About Link

private struct AboutLink: View {
    let title: String
    let icon: String
    let url: String

    var body: some View {
        Button(action: openURL) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.title)

                Text(title)
                    .font(.caption)
            }
            .foregroundColor(CiderColors.secondary)
            .frame(width: 70, height: 50)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
        }
        .buttonStyle(.plain)
        .help(url)
    }

    private func openURL() {
        if let url = URL(string: url) {
            NSWorkspace.shared.open(url)
        }
    }
}
