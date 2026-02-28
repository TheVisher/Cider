import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: Spacing.xxl) {
            Spacer()

            // App icon and name
            VStack(spacing: Spacing.md) {
                Group {
                    if let iconURL = Bundle.main.url(forResource: "cider-icon", withExtension: "png"),
                       let nsImage = NSImage(contentsOf: iconURL) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                    } else {
                        Image(systemName: "cube.fill")
                            .font(CiderFont.appIcon)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                }

                Text("Cider")
                    .font(CiderFont.displayBold)
                    .foregroundColor(CiderColors.primary)

                Text("Version \(appVersion)")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
            }

            // Description
            Text("A floating workspace for saving\nand organizing anything on macOS.")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)

            // Links
            HStack(spacing: Spacing.xl) {
                AboutLink(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: "https://github.com/TheVisher/Cider")
                AboutLink(title: "Feedback", icon: "bubble.left.and.exclamationmark.bubble.right", url: "https://github.com/TheVisher/Cider/issues")
                AboutLink(title: "Releases", icon: "arrow.down.circle", url: "https://github.com/TheVisher/Cider/releases")
            }

            // Onboarding re-trigger
            Button("Show Welcome Guide") {
                NotificationCenter.default.post(name: .showOnboarding, object: nil)
            }
            .buttonStyle(.plain)
            .font(CiderFont.labelMedium)
            .foregroundColor(CiderColors.controlAccent)

            Spacer()

            // Copyright
            Text("Made with care for macOS")
                .font(CiderFont.caption)
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
                    .font(CiderFont.caption)
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
