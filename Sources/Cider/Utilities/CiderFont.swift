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

    // MARK: - Body (11pt) — Primary text size

    /// 11pt regular — body text, descriptions, metadata
    static let body = Font.system(size: 11)
    /// 11pt medium — emphasized body, item labels, secondary info
    static let bodyMedium = Font.system(size: 11, weight: .medium)
    /// 11pt semibold — section headers, folder names, icon labels
    static let bodySemibold = Font.system(size: 11, weight: .semibold)
    /// 11pt regular italic — empty note placeholder
    static let bodyItalic = Font.system(size: 11).italic()

    // MARK: - Caption (10pt) — Secondary text

    /// 10pt regular — metadata, timestamps, word counts
    static let caption = Font.system(size: 10)
    /// 10pt medium — secondary labels, sidebar counts
    static let captionMedium = Font.system(size: 10, weight: .medium)
    /// 10pt semibold — small emphasized labels, separators
    static let captionSemibold = Font.system(size: 10, weight: .semibold)
    /// 10pt bold — folder item badges
    static let captionBold = Font.system(size: 10, weight: .bold)

    // MARK: - Label (12pt) — Form labels, emphasized secondary

    /// 12pt regular — form text, editor content
    static let label = Font.system(size: 12)
    /// 12pt medium — form labels, action labels
    static let labelMedium = Font.system(size: 12, weight: .medium)
    /// 12pt semibold — emphasized section headers
    static let labelSemibold = Font.system(size: 12, weight: .semibold)

    // MARK: - Subheading (13pt) — Card titles, sub-section headers

    /// 13pt regular — search palette text
    static let subheading = Font.system(size: 13)
    /// 13pt medium — card titles, note titles
    static let subheadingMedium = Font.system(size: 13, weight: .medium)
    /// 13pt semibold — bold card titles, view icons
    static let subheadingSemibold = Font.system(size: 13, weight: .semibold)

    // MARK: - Heading (14pt) — Section titles

    /// 14pt medium — dashboard section headers, search categories
    static let headingMedium = Font.system(size: 14, weight: .medium)
    /// 14pt semibold — settings section title
    static let headingSemibold = Font.system(size: 14, weight: .semibold)

    // MARK: - Title (15–16pt) — Panel headers, search titles

    /// 15pt semibold — settings navigation title
    static let navTitle = Font.system(size: 15, weight: .semibold)
    /// 16pt regular — search palette input, about version
    static let title = Font.system(size: 16)
    /// 16pt medium — panel headers, dashboard section titles
    static let titleMedium = Font.system(size: 16, weight: .medium)

    // MARK: - Display (20pt) — Major headers

    /// 20pt regular — folder overview icon, settings icon
    static let display = Font.system(size: 20)
    /// 20pt semibold — settings panel title, dashboard heading
    static let displaySemibold = Font.system(size: 20, weight: .semibold)
    /// 20pt bold — home dashboard title
    static let displayBold = Font.system(size: 20, weight: .bold)

    // MARK: - Small (8–9pt) — Badges, micro labels

    /// 8pt bold — tab bar badge count
    static let badge = Font.system(size: 8, weight: .bold)
    /// 9pt medium — resize icon, decorative labels
    static let microMedium = Font.system(size: 9, weight: .medium)
    /// 9pt semibold — small sidebar chevrons
    static let micro = Font.system(size: 9, weight: .semibold)
    /// 9pt bold — sidebar confirm/cancel icons
    static let microBold = Font.system(size: 9, weight: .bold)

    // MARK: - Special display sizes

    /// 28pt bold — bookmark hero fallback letter
    static let heroFallback = Font.system(size: 28, weight: .bold)
    /// 36pt regular — empty state icon
    static let emptyStateIcon = Font.system(size: 36)
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
