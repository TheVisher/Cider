import SwiftUI
import Foundation

extension Notification.Name {
    static let ciderMinimizedStateChanged = Notification.Name("ciderMinimizedStateChanged")
    static let dismissCommandPalette = Notification.Name("cider.dismissCommandPalette")
    static let toggleCommandPalette = Notification.Name("cider.toggleCommandPalette")
    static let openCiderSettings = Notification.Name("cider.openCiderSettings")
    static let dismissSettings = Notification.Name("cider.dismissSettings")
    static let ciderConfigChanged = Notification.Name("cider.ciderConfigChanged")
}

enum CiderBorder {
    static let innerStrokeWidth: CGFloat = 1.5
    static let innerStrokeInset: CGFloat = 0.75
}

// MARK: - Spacing Tokens

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
}

// MARK: - Corner Radius Tokens

enum Radius {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
    static let xl: CGFloat = 20
}

// MARK: - Animation Presets

enum CiderAnimation {
    static let smooth: Animation = .smooth
    static let snappy: Animation = .snappy
    static let bouncy: Animation = .bouncy

    // Reduce Motion: 0.2s opacity crossfade per DESIGN_SYSTEM.md
    static let reduceMotion: Animation = .linear(duration: 0.2)

    // Custom springs
    static let hoverMagnify = Animation.spring(duration: 0.25, bounce: 0.05)
    static let listReorder = Animation.spring(duration: 0.3, bounce: 0.08)
}

// MARK: - Design System

enum CiderDesign {
    // Components
    static let cornerRadius: CGFloat = Radius.xl
    static let componentSpacing: CGFloat = Spacing.sm
    static let iconSize: CGFloat = 44
    static let iconCornerRadius: CGFloat = Radius.lg

    // Compact mode
    static let compactIconSize: CGFloat = 20

    // Specific visual elements
    static let runningIndicatorSize: CGFloat = 6
    static let runningIndicatorOffset: CGFloat = 6

    // Edge detection
    static let edgeDetectionThreshold: CGFloat = 3

    // Hover weights
    static let hoverExpandWeight: CGFloat = 2.5
    static let hoverContractWeight: CGFloat = 0.55

    // Shadow padding - extra space in window for shadow to render
    static let shadowPaddingHorizontal: CGFloat = 70
    static let shadowPaddingTop: CGFloat = 20
    static let shadowPaddingBottom: CGFloat = 70
}

enum CiderColors {
    static let primary = Color.primary
    static let secondary = Color.secondary
    static let tertiary = Color(.tertiaryLabelColor)
    static let quaternary = Color(.quaternaryLabelColor)
    static let separator = Color(.separatorColor)
    static let controlAccent = Color(.controlAccentColor)
    static let label = Color(.labelColor)
    static let selectedContent = Color(.selectedContentBackgroundColor)
    static let success = Color.green
    static let destructive = Color(.systemRed)

    // Backgrounds
    static let opaqueBackground = Color(.windowBackgroundColor)
}
