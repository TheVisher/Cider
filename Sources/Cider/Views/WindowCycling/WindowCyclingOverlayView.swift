import SwiftUI

struct WindowCyclingOverlayView: View {
    @ObservedObject var cyclingManager: WindowCyclingManager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let itemWidth: CGFloat = 100
    private let itemHeight: CGFloat = 80
    private let iconSize: CGFloat = 48
    private let cornerRadius: CGFloat = Radius.lg

    var body: some View {
        if cyclingManager.isActive && !cyclingManager.windows.isEmpty {
            ZStack {
                // Background
                CyclingBackgroundView(cornerRadius: cornerRadius)

                // Window items
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(Array(cyclingManager.windows.enumerated()), id: \.element.id) { index, window in
                                WindowCyclingItem(
                                    window: window,
                                    isSelected: index == cyclingManager.selectedIndex
                                )
                                .id(index)
                            }
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.md)
                    }
                    .onChange(of: cyclingManager.selectedIndex) { _, newIndex in
                        withAnimation(reduceMotion ? .none : CiderAnimation.snappy) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
            .frame(maxWidth: calculateWidth())
            .fixedSize(horizontal: true, vertical: true)
        }
    }

    private func calculateWidth() -> CGFloat {
        let count = CGFloat(cyclingManager.windows.count)
        let contentWidth = count * itemWidth + (count - 1) * Spacing.md + Spacing.lg * 2
        let maxWidth: CGFloat = 800
        return min(contentWidth, maxWidth)
    }
}

// MARK: - Window Cycling Item

private struct WindowCyclingItem: View {
    let window: WindowInfo
    let isSelected: Bool

    private let iconSize: CGFloat = 48
    private let itemWidth: CGFloat = 100
    private let cornerRadius: CGFloat = Radius.md

    var body: some View {
        VStack(spacing: Spacing.xs) {
            // App icon
            AppIconView(bundleIdentifier: window.bundleIdentifier, size: iconSize)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            // Window title
            Text(window.displayTitle)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 28)
        }
        .frame(width: itemWidth)
        .padding(.vertical, Spacing.sm)
        .padding(.horizontal, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.3) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - App Icon View

private struct AppIconView: View {
    let bundleIdentifier: String
    let size: CGFloat

    var body: some View {
        if let icon = appIcon {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "app.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(.secondary)
        }
    }

    private var appIcon: NSImage? {
        guard !bundleIdentifier.isEmpty else { return nil }

        // Try to get the app's icon
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        return nil
    }
}

// MARK: - Background View

private struct CyclingBackgroundView: View {
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
                .offset(y: 12)
                .opacity(0.6)

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
