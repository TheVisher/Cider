import SwiftUI

/// Semantic font tokens for all Cider UI text.
///
/// Every `.font(.system(size:weight:))` declaration in the codebase should use
/// one of these tokens. When the brand identity is finalized, changing typography
/// means editing this one file.
///
/// For textScale-responsive views (BookmarksBrowserView, BookmarksPanelView),
/// use the `(scale:)` function variants.
enum CiderFont {
    private nonisolated(unsafe) static var _cachedScale: CGFloat = CiderConfig.load().textSize.scale
    private static var globalScale: CGFloat { _cachedScale }
    private static func scaled(_ size: CGFloat) -> CGFloat { size * globalScale }
    /// Expose the current global scale for callers that need to scale raw CGFloat sizes.
    static var scale: CGFloat { _cachedScale }

    /// Call once after saving config so all font tokens reflect the new text size.
    static func invalidateScale() {
        _cachedScale = CiderConfig.load().textSize.scale
    }

    // MARK: - Body (11pt) — Primary text size

    /// 11pt regular — body text, descriptions, metadata
    static var body: Font { Font.system(size: scaled(11)) }
    /// 11pt medium — emphasized body, item labels, secondary info
    static var bodyMedium: Font { Font.system(size: scaled(11), weight: .medium) }
    /// 11pt semibold — section headers, folder names, icon labels
    static var bodySemibold: Font { Font.system(size: scaled(11), weight: .semibold) }
    /// 11pt regular italic — empty note placeholder
    static var bodyItalic: Font { Font.system(size: scaled(11)).italic() }

    // MARK: - Caption (10pt) — Secondary text

    /// 10pt regular — metadata, timestamps, word counts
    static var caption: Font { Font.system(size: scaled(10)) }
    /// 10pt medium — secondary labels, sidebar counts
    static var captionMedium: Font { Font.system(size: scaled(10), weight: .medium) }
    /// 10pt semibold — small emphasized labels, separators
    static var captionSemibold: Font { Font.system(size: scaled(10), weight: .semibold) }
    /// 10pt bold — folder item badges
    static var captionBold: Font { Font.system(size: scaled(10), weight: .bold) }

    // MARK: - Label (12pt) — Form labels, emphasized secondary

    /// 12pt regular — form text, editor content
    static var label: Font { Font.system(size: scaled(12)) }
    /// 12pt medium — form labels, action labels
    static var labelMedium: Font { Font.system(size: scaled(12), weight: .medium) }
    /// 12pt semibold — emphasized section headers
    static var labelSemibold: Font { Font.system(size: scaled(12), weight: .semibold) }

    // MARK: - Subheading (13pt) — Card titles, sub-section headers

    /// 13pt regular — search palette text
    static var subheading: Font { Font.system(size: scaled(13)) }
    /// 13pt medium — card titles, note titles
    static var subheadingMedium: Font { Font.system(size: scaled(13), weight: .medium) }
    /// 13pt semibold — bold card titles, view icons
    static var subheadingSemibold: Font { Font.system(size: scaled(13), weight: .semibold) }

    // MARK: - Heading (14pt) — Section titles

    /// 14pt medium — dashboard section headers, search categories
    static var headingMedium: Font { Font.system(size: scaled(14), weight: .medium) }
    /// 14pt semibold — settings section title
    static var headingSemibold: Font { Font.system(size: scaled(14), weight: .semibold) }

    // MARK: - Title (15–16pt) — Panel headers, search titles

    /// 15pt semibold — settings navigation title
    static var navTitle: Font { Font.system(size: scaled(15), weight: .semibold) }
    /// 16pt regular — search palette input, about version
    static var title: Font { Font.system(size: scaled(16)) }
    /// 16pt medium — panel headers, dashboard section titles
    static var titleMedium: Font { Font.system(size: scaled(16), weight: .medium) }

    // MARK: - Display (20pt) — Major headers

    /// 20pt regular — folder overview icon, settings icon
    static var display: Font { Font.system(size: scaled(20)) }
    /// 20pt semibold — settings panel title, dashboard heading
    static var displaySemibold: Font { Font.system(size: scaled(20), weight: .semibold) }
    /// 20pt bold — home dashboard title
    static var displayBold: Font { Font.system(size: scaled(20), weight: .bold) }

    // MARK: - Small (8–9pt) — Badges, micro labels

    /// 8pt bold — tab bar badge count
    static var badge: Font { Font.system(size: scaled(8), weight: .bold) }
    /// 9pt medium — resize icon, decorative labels
    static var microMedium: Font { Font.system(size: scaled(9), weight: .medium) }
    /// 9pt semibold — small sidebar chevrons
    static var micro: Font { Font.system(size: scaled(9), weight: .semibold) }
    /// 9pt bold — sidebar confirm/cancel icons
    static var microBold: Font { Font.system(size: scaled(9), weight: .bold) }

    // MARK: - Special display sizes

    /// 28pt bold — bookmark hero fallback letter
    static var heroFallback: Font { Font.system(size: scaled(28), weight: .bold) }
    /// 36pt regular — empty state icon
    static var emptyStateIcon: Font { Font.system(size: scaled(36)) }
    /// 64pt regular — about screen app icon
    static let appIcon = Font.system(size: 64)

    // MARK: - Responsive (textScale-based)

    /// Body at responsive scale — BookmarksBrowserView, BookmarksPanelView
    static func body(scale: CGFloat) -> Font { .system(size: 11 * scale) }
    static func bodyMedium(scale: CGFloat) -> Font { .system(size: 11 * scale, weight: .medium) }
    static func bodySemibold(scale: CGFloat) -> Font { .system(size: 11 * scale, weight: .semibold) }

    /// Caption at responsive scale
    static func caption(scale: CGFloat) -> Font { .system(size: 10 * scale) }
    static func captionMedium(scale: CGFloat) -> Font { .system(size: 10 * scale, weight: .medium) }
    static func captionSemibold(scale: CGFloat) -> Font { .system(size: 10 * scale, weight: .semibold) }

    /// Small at responsive scale
    static func micro(scale: CGFloat) -> Font { .system(size: 9 * scale, weight: .semibold) }

    /// Label at responsive scale
    static func label(scale: CGFloat) -> Font { .system(size: 12 * scale) }
    static func labelMedium(scale: CGFloat) -> Font { .system(size: 12 * scale, weight: .medium) }
    static func labelSemibold(scale: CGFloat) -> Font { .system(size: 12 * scale, weight: .semibold) }

    /// Subheading at responsive scale
    static func subheadingMedium(scale: CGFloat) -> Font { .system(size: 13 * scale, weight: .medium) }

    /// Title at responsive scale
    static func heroTitle(scale: CGFloat) -> Font { .system(size: 17 * scale, weight: .semibold) }
    static func heroDisplay(scale: CGFloat) -> Font { .system(size: 32 * scale) }
}
