import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        ZStack {
            // Background
            SettingsBackgroundView(cornerRadius: SettingsDesign.cornerRadius)

            VStack(spacing: 0) {
                // Title bar area
                SettingsTitleBar()

                // Tab bar
                SettingsTabBar(selectedTab: $selectedTab)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.md)

                Divider()
                    .padding(.horizontal, 1.5)
                    .opacity(0.3)

                // Content area
                ScrollView {
                    selectedTabContent
                        .padding(Spacing.xl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .clipShape(RoundedRectangle(cornerRadius: SettingsDesign.cornerRadius, style: .continuous))
        }
        .frame(width: SettingsDesign.width, height: SettingsDesign.height)
        .environmentObject(viewModel)
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .general:
            GeneralSettingsView()
        case .pinnedApps:
            PinnedAppsSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .advanced:
            AdvancedSettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable {
    case general = "General"
    case pinnedApps = "Pinned Apps"
    case appearance = "Appearance"
    case advanced = "Advanced"
    case about = "About"

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .pinnedApps: return "square.grid.2x2"
        case .appearance: return "paintbrush"
        case .advanced: return "slider.horizontal.3"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Design Constants

enum SettingsDesign {
    static let width: CGFloat = 750
    static let height: CGFloat = 580
    static let cornerRadius: CGFloat = Radius.lg
    static let shadowPadding: CGFloat = 45
}

// MARK: - Title Bar

private struct SettingsTitleBar: View {
    var body: some View {
        HStack {
            // Close button
            Button(action: {
                NotificationCenter.default.post(name: .dismissSettings, object: nil)
            }) {
                Circle()
                    .fill(Color.red.opacity(0.9))
                    .frame(width: 12, height: 12)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.black.opacity(0.5))
                            .opacity(0) // Hidden by default, could show on hover
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
            .padding(.leading, Spacing.md)

            Spacer()

            Text("Cider Settings")
                .font(.headline)
                .foregroundColor(CiderColors.primary)

            Spacer()

            Color.clear.frame(width: 44)
        }
        .frame(height: 44)
    }
}

// MARK: - Tab Bar

private struct SettingsTabBar: View {
    @Binding var selectedTab: SettingsTab

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                SettingsTabButton(
                    tab: tab,
                    isSelected: selectedTab == tab,
                    action: { selectedTab = tab }
                )
            }
        }
    }
}

private struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                    .frame(height: 22)

                Text(tab.rawValue)
                    .font(.caption)
            }
            .foregroundColor(isSelected ? CiderColors.primary : CiderColors.secondary)
            .frame(width: 90, height: 58)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle()) // Make entire area clickable
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Background

struct SettingsBackgroundView: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            opaqueBackground
        } else {
            acrylicBackground
        }
    }

    @ViewBuilder
    private var acrylicBackground: some View {
        ZStack {
            // Shadow layer
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
                .blur(radius: 18)
                .offset(y: 18)
                .opacity(0.7)

            // Main content
            ZStack {
                VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                Color.black.opacity(0.45)
                Color.white.opacity(0.03)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - 0.75, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1.5)
                    .padding(0.75)
            )
        }
    }

    @ViewBuilder
    private var opaqueBackground: some View {
        Color(nsColor: NSColor.windowBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius - 0.75, style: .continuous)
                    .stroke(CiderColors.separator.opacity(0.5), lineWidth: 1.5)
                    .padding(0.75)
            )
    }
}
