import SwiftUI
import Foundation

// MARK: - Text Scale Environment Key

private struct TextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

// MARK: - Hide Card Footers Environment Key

private struct HideCardFootersKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var hideCardFooters: Bool {
        get { self[HideCardFootersKey.self] }
        set { self[HideCardFootersKey.self] = newValue }
    }
}

// MARK: - Show Card Details On Hover Environment Key

private struct ShowCardDetailsOnHoverKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var showCardDetailsOnHover: Bool {
        get { self[ShowCardDetailsOnHoverKey.self] }
        set { self[ShowCardDetailsOnHoverKey.self] = newValue }
    }
}

// MARK: - Card Environment Modifier

extension View {
    func ciderCardEnvironment(textScale: CGFloat, hideFooters: Bool, detailsOnHover: Bool) -> some View {
        self
            .environment(\.textScale, textScale)
            .environment(\.hideCardFooters, hideFooters)
            .environment(\.showCardDetailsOnHover, detailsOnHover)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let openCiderSettings = Notification.Name("cider.openCiderSettings")
    static let settingsNavigate = Notification.Name("cider.settingsNavigate")
    static let dismissSettings = Notification.Name("cider.dismissSettings")
    static let ciderConfigChanged = Notification.Name("cider.ciderConfigChanged")
    static let telegramBridgeConfigurationChanged = Notification.Name("cider.telegramBridgeConfigurationChanged")
    static let showBookmarkCaptureToast = Notification.Name("cider.showBookmarkCaptureToast")
    static let showBookmarkClipboardReviewToast = Notification.Name("cider.showBookmarkClipboardReviewToast")
    static let showImageClipboardReviewToast = Notification.Name("cider.showImageClipboardReviewToast")
    static let toggleCiderPanel = Notification.Name("cider.toggleCiderPanel")
    static let dismissCiderPanel = Notification.Name("cider.dismissCiderPanel")
    static let openCiderMainWindow = Notification.Name("cider.openCiderMainWindow")
    static let dismissCiderMainWindow = Notification.Name("cider.dismissCiderMainWindow")
    static let minimizeCiderMainWindow = Notification.Name("cider.minimizeCiderMainWindow")
    static let maximizeCiderMainWindow = Notification.Name("cider.maximizeCiderMainWindow")
    static let floatCiderSurface = Notification.Name("cider.floatCiderSurface")
    static let dockCiderSurface = Notification.Name("cider.dockCiderSurface")
    static let reanchorCiderSurface = Notification.Name("cider.reanchorCiderSurface")
    static let openCiderSurfaceInMainWindow = Notification.Name("cider.openCiderSurfaceInMainWindow")
    static let toggleCiderPanelCollapse = Notification.Name("cider.toggleCiderPanelCollapse")
    static let maximizeCiderPanel = Notification.Name("cider.maximizeCiderPanel")
    static let openBookmarkDetails = Notification.Name("cider.openBookmarkDetails")
    static let showFolderCreationField = Notification.Name("cider.showFolderCreationField")
    static let showUndoToast = Notification.Name("cider.showUndoToast")
    static let pauseUndoToastDismiss = Notification.Name("cider.pauseUndoToastDismiss")
    static let resumeUndoToastDismiss = Notification.Name("cider.resumeUndoToastDismiss")
    static let toggleNoteEditor = Notification.Name("cider.toggleNoteEditor")
    static let editorRequestClose = Notification.Name("cider.editorRequestClose")
    static let captureBookmark = Notification.Name("cider.captureBookmark")
    static let trashContentsChanged = Notification.Name("cider.trashContentsChanged")
    static let snapCiderPanel = Notification.Name("cider.snapCiderPanel")
    static let expandCiderPanelForSlideOut = Notification.Name("cider.expandCiderPanelForSlideOut")
    static let restoreCiderPanelAfterSlideOut = Notification.Name("cider.restoreCiderPanelAfterSlideOut")
    static let requestScreenCapture = Notification.Name("cider.requestScreenCapture")
    static let openNewItemPopover = Notification.Name("cider.openNewItemPopover")
    static let showOnboarding = Notification.Name("cider.showOnboarding")
    static let openDateCardFromNotification = Notification.Name("cider.openDateCardFromNotification")
    static let toggleClipboardViewer = Notification.Name("cider.toggleClipboardViewer")
    static let dismissClipboardPanel = Notification.Name("cider.dismissClipboardPanel")
    static let toggleClipboardPanelWidth = Notification.Name("cider.toggleClipboardPanelWidth")
    static let vaultFoldersChanged = Notification.Name("cider.vaultFoldersChanged")
    static let vaultFilesystemDidChange = Notification.Name("cider.vaultFilesystemDidChange")
    static let pinSessionToAIPanel = Notification.Name("cider.pinSessionToAIPanel")
    static let toggleAIAssistantPanel = Notification.Name("cider.toggleAIAssistantPanel")
    static let showAIAssistantPanel = Notification.Name("cider.showAIAssistantPanel")
    static let dismissAIAssistantPanel = Notification.Name("cider.dismissAIAssistantPanel")
    static let showCiderDropZone = Notification.Name("cider.showCiderDropZone")
    static let kanbanBoardsChanged = Notification.Name("cider.kanbanBoardsChanged")
}

// MARK: - Snap Target

enum SnapTarget: String, CaseIterable {
    case almostMaximized
    case leftHalf
    case rightHalf
    case leftEdge
    case rightEdge
}

enum CiderBorder {
    static let innerStrokeWidth: CGFloat = 1.5
    static let innerStrokeInset: CGFloat = 0.75
    /// Sub-pixel hairline stroke for subtle pill/card outlines
    static let hairlineStrokeWidth: CGFloat = 0.5
    /// Width of the selection ring on color-picker swatches
    static let colorPickerRingWidth: CGFloat = 2
    /// Thin 1pt stroke for subtle borders (e.g. unselected color pickers)
    static let thinStrokeWidth: CGFloat = 1
}

// MARK: - Safe URL Opening

/// Opens a URL in the system browser only if it uses http or https.
/// Prevents untrusted content from launching file:, app-specific, or OS deep-link schemes.
func openURLSafely(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else { return }
    NSWorkspace.shared.open(url)
}

// MARK: - Spacing Tokens

enum Spacing {
    static let hairline: CGFloat = 1
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

// MARK: - Kanban Design Tokens

enum KanbanDesign {
    /// Corner radius for the thin color accent bar on cards
    static let accentBarRadius: CGFloat = 2
    /// Height of the color accent bar on cards
    static let accentBarHeight: CGFloat = 3
    /// Width for standalone Kanban columns.
    static let columnWidth: CGFloat = 320
    /// Width for project-board columns, which need extra room for hierarchy and plan badges.
    static let projectColumnWidth: CGFloat = 368
    /// Capped height for columns inside project-board swimlanes.
    static let projectColumnHeight: CGFloat = 1000
    /// Height reserved for explicit horizontal scroll controls in project-board swimlanes.
    static let projectHorizontalScrollControlHeight: CGFloat = 28
    /// Vertical spacing between title, body, and context sections inside expanded card previews.
    static let cardPreviewSectionSpacing: CGFloat = 8
    /// Spacing before parent/plan context when it sits near the footer in expanded previews.
    static let cardPreviewContextFooterSpacing: CGFloat = 8
    /// Extra vertical spacing before the metadata footer in expanded card previews.
    static let cardPreviewFooterTopSpacing: CGFloat = 8
    /// Maximum number of lines for generated/fallback preview text in expanded cards.
    static let cardPreviewBodyLineLimit = 2
    /// Blue Kanban accent hue, separated from the system accent and purple family.
    static let kanbanBlueAccentHueDegrees: CGFloat = 204
    /// Purple Kanban accent hue, far enough from blue to remain distinct in dark UI.
    static let kanbanPurpleAccentHueDegrees: CGFloat = 278
    static let kanbanAccentSaturation: CGFloat = 0.82
    static let kanbanAccentBrightness: CGFloat = 0.92
    /// Indent applied to same-column child cards in hierarchy groups.
    static let childIndent: CGFloat = 18
    /// Width reserved for the child-card hierarchy connector.
    static let childConnectorWidth: CGFloat = 14
    /// Vertical offset that aims the child connector into the upper body of a card.
    static let childConnectorTopInset: CGFloat = 20
}

// MARK: - Animation Presets

enum CiderAnimation {
    static let snappy: Animation = .snappy
}

enum NotesDesign {
    static let toolbarHeight: CGFloat = 36
    static let findBarHeight: CGFloat = 36
    static let toolbarButtonSize: CGFloat = 28
    static let toolbarIconSize: CGFloat = 11
    static let toolbarDividerHeight: CGFloat = 16
    static let trafficLightDiameter: CGFloat = 12
    static let trafficLightTapTarget: CGFloat = Spacing.lg
    static let trafficLightSpacing: CGFloat = Spacing.xs
}

enum NoteEditorDesign {
    // MARK: - Popover widths
    /// Width of the text-style formatting popover
    static let textStylePopoverWidth: CGFloat = 248
    /// Width of the table insert/edit popover
    static let tablePopoverWidth: CGFloat = 200
    /// Width of the version-history (snapshot) popover
    static let snapshotPopoverWidth: CGFloat = 260
    /// Max scroll height of the snapshot list inside the popover
    static let snapshotScrollMaxHeight: CGFloat = 300

    // MARK: - Popover row layout
    /// Width of icon column in popover rows (checkmark, symbol, clock)
    static let popoverRowIconWidth: CGFloat = 16
    /// Vertical padding for each popover menu row (xs + 1px optical correction)
    static let popoverRowVerticalPadding: CGFloat = Spacing.xs + 1

    // MARK: - Table grid picker
    /// Size of each table-picker cell in the grid
    static let tableCellSize: CGFloat = 18
    /// Spacing between cells in the table picker grid (= Spacing.xxs)
    static let tableCellSpacing: CGFloat = Spacing.xxs
    /// Corner radius of each table picker cell
    static let tableCellRadius: CGFloat = Radius.xs

    // MARK: - Highlight swatch bar (in toolbar)
    /// Width of the color swatch underline bar on the highlight button
    static let highlightSwatchWidth: CGFloat = 14
    /// Height of the color swatch underline bar on the highlight button
    static let highlightSwatchHeight: CGFloat = 3
    /// Corner radius of the swatch underline bar (hairline rounding)
    static let highlightSwatchRadius: CGFloat = Spacing.hairline
    /// Y offset to nudge the swatch bar toward the bottom of the icon
    static let highlightSwatchYOffset: CGFloat = Spacing.hairline
    /// Diameter of the color-choice dot inside the highlight submenu
    static let highlightColorDotSize: CGFloat = 10

    // MARK: - Status bar
    /// Height of the editor status bar at the bottom of the notes pane
    static let statusBarHeight: CGFloat = 24
    /// Width of the label column in the notes metadata info grid ("Created", "Modified", etc.)
    static let infoGridLabelWidth: CGFloat = 72

    // MARK: - Note card accent bar
    /// Width of the left accent bar on note cards
    static let accentBarWidth: CGFloat = 2
    /// Corner radius of the left accent bar on note cards
    static let accentBarRadius: CGFloat = Spacing.hairline

    // MARK: - Note card grid layout
    /// Extra height added to the card content preview height to form the grid card minimum height
    static let gridMinHeightPadding: CGFloat = 60
    /// Opacity of the hover footer overlay on note cards (semi-opaque surface)
    static let hoverOverlayOpacity: CGFloat = 0.95

    // MARK: - Fonts (non-standard variants not expressible through CiderFont tokens)
    /// "Aa" text-style button label — 12pt semibold rounded (toolbar branding treatment)
    static var textStyleButtonFont: Font {
        .system(size: 12 * CiderFont.scale, weight: .semibold, design: .rounded)
    }
    /// AppKit NSFont for the find bar text field (12pt regular)
    static var findBarNSFont: NSFont { .systemFont(ofSize: 12 * CiderFont.scale) }
    /// Inline toggle letter label for Bold (13pt bold)
    static var inlineToggleBoldFont: Font { .system(size: 13 * CiderFont.scale, weight: .bold) }
    /// Inline toggle letter label for Italic (13pt regular serif italic)
    static var inlineToggleItalicFont: Font {
        .system(size: 13 * CiderFont.scale, weight: .regular, design: .serif).italic()
    }
    /// Inline toggle letter label for Underline/Strikethrough (13pt medium)
    static var inlineToggleMediumFont: Font { .system(size: 13 * CiderFont.scale, weight: .medium) }
}

enum BookmarksDesign {
    static let thumbnailHeightGrid: CGFloat = 140
    static let thumbnailHeightMasonryMin: CGFloat = 120
    static let thumbnailHeightMasonryMax: CGFloat = 360
    static let thumbnailHeightMasonryFallback: CGFloat = 180
    static let thumbnailShimmerDuration: TimeInterval = 1.7
    static let thumbnailShimmerBandWidthRatio: CGFloat = 0.55
    static let thumbnailShimmerBandMinWidth: CGFloat = 120
    static let thumbnailHeightList: CGFloat = 52
    static let thumbnailWidthList: CGFloat = 72
    static let thumbnailIconOverlaySizeList: CGFloat = 22
    static let thumbnailIconOverlaySizeGrid: CGFloat = 52
    static let thumbnailIconCandidateMinDimension: CGFloat = 12
    static let thumbnailIconCandidateMaxDimension: CGFloat = 96
    static let thumbnailIconURLHintMaxDimension: CGFloat = 256
    static let thumbnailIconCandidateMaxAspectDelta: CGFloat = 0.28
    static let cardMinWidth: CGFloat = 220
    static let cardContentSpacing: CGFloat = Spacing.sm
    static let cardCornerRadius: CGFloat = Radius.md
    static let folderSidebarWidth: CGFloat = 224
    static let folderSidebarRowMinHeight: CGFloat = 30
    static let folderSidebarIndent: CGFloat = 14
    static let detailsFloatingLiftBlur: CGFloat = 8
    static let detailsFloatingLiftYOffset: CGFloat = 3
    static let detailsSidebarFixedWidth: CGFloat = 300
    static let detailsSlideOutMinWidth: CGFloat = 600
    static let detailsSlideOutFloatInset: CGFloat = Spacing.md
    static let detailsSlideOutExpandedPanelMinWidth: CGFloat = 900
    static let cardFallbackLetterSize: CGFloat = 26
    static let listFallbackLetterSize: CGFloat = 16
    static let detailsHeroFallbackLetterSize: CGFloat = 54
    static let detailsSheetURLMinHeight: CGFloat = 44
    static let detailsSheetNotesMinHeight: CGFloat = 120
    static let detailsSheetNotesHeight: CGFloat = 200
    static let detailsContentBlurRadius: CGFloat = 12
    static let folderShelfDragStateTimeout: TimeInterval = 8.0
    static let dragPreviewWidth: CGFloat = 188
    static let dragPreviewThumbnailHeight: CGFloat = 96
    static let dragPreviewScale: CGFloat = 0.86
    static let dragPreviewRotation: CGFloat = -2.5
    static let dragPreviewXOffset: CGFloat = 30
    static let dragPreviewYOffset: CGFloat = -14
    static let multiDragFanRotationStep: Double = 6
    static let multiDragFanXStep: CGFloat = 16
    static let multiDragFanYStep: CGFloat = 8
    static let buttonTapTarget: CGFloat = 28
    static let dragPreviewPaddingBleed: CGFloat = 40
    /// Carousel navigation arrow icon size
    static let carouselArrowIconSize: CGFloat = 10
    /// Carousel navigation arrow button hit-target (icon + padding)
    static let carouselArrowButtonSize: CGFloat = 22
    /// Carousel page-indicator dot diameter
    static let carouselDotSize: CGFloat = 5
    /// Hero carousel navigation arrow icon size (larger surface)
    static let carouselHeroArrowIconSize: CGFloat = 14
    /// Hero carousel navigation arrow button hit-target
    static let carouselHeroArrowButtonSize: CGFloat = 28
    /// Carousel inline delete-button (×) hit-target
    static let carouselDeleteButtonSize: CGFloat = 16
    /// Width of the label column in the properties info grid
    static let propertyLabelWidth: CGFloat = 72
    /// Tag color indicator dot in menus and pickers
    static let tagColorDotSize: CGFloat = 8
    /// Hero carousel page-indicator dot diameter (larger surface, slightly bigger than card dot)
    static let carouselHeroDotSize: CGFloat = 6
    /// Color swatch width in AI dominant-colors section
    static let colorSwatchWidth: CGFloat = 44
    /// Color swatch height in AI dominant-colors section
    static let colorSwatchHeight: CGFloat = 22
    /// Color swatch label row height (hex / checkmark row)
    static let colorSwatchLabelHeight: CGFloat = 12
    /// Related-items row thumbnail width
    static let relatedItemThumbnailWidth: CGFloat = 32
    /// Related-items row thumbnail height
    static let relatedItemThumbnailHeight: CGFloat = 24
}

enum BookmarksToastDesign {
    static let width: CGFloat = 320
    static let height: CGFloat = 56
    static let reviewHeight: CGFloat = 96
    static let cornerRadius: CGFloat = Radius.md
    static let shadowPadding: CGFloat = 0
    static let topInset: CGFloat = Spacing.xxxl
    static let autoHideDuration: TimeInterval = 1.8
    static let reviewAutoHideDuration: TimeInterval = 5.0
    static let reviewProgressHeight: CGFloat = Spacing.xxs
    static let reviewProgressTickInterval: TimeInterval = 1.0 / 30.0

    static var panelWidth: CGFloat {
        width + shadowPadding * 2
    }

    static var panelHeight: CGFloat {
        height + shadowPadding * 2
    }

    static var reviewPanelHeight: CGFloat {
        reviewHeight + shadowPadding * 2
    }
}

enum ToastPosition: String, Codable, CaseIterable {
    case topCenterScreen
    case bottomRightPanel
    case bottomLeftPanel
    case topRightPanel
    case topLeftPanel

    var displayName: String {
        switch self {
        case .topCenterScreen: return "Top center (screen)"
        case .bottomRightPanel: return "Bottom right (panel)"
        case .bottomLeftPanel: return "Bottom left (panel)"
        case .topRightPanel: return "Top right (panel)"
        case .topLeftPanel: return "Top left (panel)"
        }
    }
}

enum UndoToastDesign {
    static let width: CGFloat = 360
    static let height: CGFloat = 56
    static let cornerRadius: CGFloat = Radius.md
    static let shadowPadding: CGFloat = 0
    static let autoHideDuration: TimeInterval = 5.0
    static let panelEdgeInset: CGFloat = Spacing.md

    static var panelWidth: CGFloat {
        width + shadowPadding * 2
    }

    static var panelHeight: CGFloat {
        height + shadowPadding * 2
    }
}

/// NSColor design tokens for ScreenCaptureService's CoreGraphics overlay drawing.
/// These are AppKit/CGColor-based because the draw(_ dirtyRect:) method uses
/// CoreGraphics directly — SwiftUI Color cannot be used there.
enum ScreenCaptureOverlayDesign {
    /// Full-screen dim tint drawn outside the active selection rectangle.
    static let screenDimColor = NSColor.black.withAlphaComponent(0.35)
    /// Selection rectangle border stroke color.
    static let selectionBorderColor = NSColor.white.withAlphaComponent(0.9)
    /// Selection rectangle border line width.
    static let selectionBorderWidth: CGFloat = CiderBorder.innerStrokeWidth
    /// Corner handle fill color (solid white squares).
    static let cornerHandleColor = NSColor.white
    /// Corner handle size (width and height of each square handle).
    static let cornerHandleSize: CGFloat = 6
    /// Dimensions label text color.
    static let labelTextColor = NSColor.white
    /// Dimensions label pill background color.
    static let labelBackgroundColor = NSColor.black.withAlphaComponent(0.55)
    /// Horizontal padding between label text and pill edge.
    static let labelPadding: CGFloat = Spacing.xs
    /// Gap between selection edge and dimensions label pill.
    static let labelGap: CGFloat = Spacing.sm
}

enum ScreenCaptureToastDesign {
    static let width: CGFloat = 360
    static let height: CGFloat = 112
    static let cornerRadius: CGFloat = Radius.md
    static let shadowPadding: CGFloat = 0
    static let autoHideDuration: TimeInterval = 8.0
    static let progressTickInterval: TimeInterval = 1.0 / 30.0
    static let panelEdgeInset: CGFloat = Spacing.md

    static var panelWidth: CGFloat { width + shadowPadding * 2 }
    static var panelHeight: CGFloat { height + shadowPadding * 2 }
}

enum SearchPaletteDesign {
    static let paletteWidth: CGFloat = 560
    static let resultsMaxHeight: CGFloat = 400
    static let searchFieldHeight: CGFloat = 52
    static let recentBookmarkCount = 3
    static let recentNoteCount = 2
    static let recentDateCardCount = 2
    static let recentContactCount = 2
    /// Maximum number of subfolder name pills shown in a folder section header
    static let folderSectionMaxSubfolderPills = 3
    /// Base color for the floating drop-shadow shape beneath the palette
    static let shadowColor: Color = .black
    /// Blur radius for the palette floating drop-shadow
    static let shadowBlurRadius: CGFloat = 24
    /// Y-axis offset for the palette floating drop-shadow
    static let shadowYOffset: CGFloat = 12
    /// Opacity of the palette floating drop-shadow
    static let shadowOpacity: CGFloat = 0.7
    /// Fraction of the screen height at which the palette is positioned from the top
    static let topOffsetFactor: CGFloat = 0.22
}

enum CiderPanelDesign {
    static let defaultWidth: CGFloat = 780
    static let defaultHeight: CGFloat = 640
    static let minWidth: CGFloat = 400
    static let minHeight: CGFloat = 440
    static let cornerRadius: CGFloat = Radius.lg
    static let shadowPadding: CGFloat = 0
    static let topPadding: CGFloat = 0
    static let bottomPadding: CGFloat = 0
    static let collapsedBottomPadding: CGFloat = topPadding
    static let titleBarHeight: CGFloat = 40
    static let tabBarHeight: CGFloat = 34
    static let collapsedContentHeight: CGFloat = titleBarHeight
    static let trafficLightDiameter: CGFloat = 12
    static let trafficLightTapTarget: CGFloat = Spacing.lg
    static let trafficLightSpacing: CGFloat = Spacing.xs
    static let trafficLightSymbolSize: CGFloat = 7
    static let collapseToggleAnimationDuration: TimeInterval = 0.18
    static let tabBadgePadding: CGFloat = Spacing.xs
    static let tabHorizontalPadding: CGFloat = Spacing.xs
    static let tabSpacing: CGFloat = Spacing.xxs

    static var panelContentWidth: CGFloat {
        defaultWidth + shadowPadding * 2
    }

    static var panelContentHeight: CGFloat {
        defaultHeight + topPadding + shadowPadding + bottomPadding
    }

    static var panelMinWidth: CGFloat {
        minWidth + shadowPadding * 2
    }

    static var panelMinHeight: CGFloat {
        minHeight + topPadding + shadowPadding + bottomPadding
    }

    static var panelCollapsedHeight: CGFloat {
        collapsedContentHeight + topPadding + collapsedBottomPadding
    }

    static let resizeEdgeThickness: CGFloat = 6
    static let resizeCornerSize: CGFloat = 20
    static let sidebarCompactThreshold: CGFloat = 680
    static let sidebarBackgroundOpacity: CGFloat = 0.04
    static let sidebarDividerOpacity: CGFloat = 0.2
}

enum ClipboardPanelDesign {
    static let narrowWidth: CGFloat = 360
    static let wideWidth: CGFloat = 720
    static let minHeight: CGFloat = 300
    static let defaultHeight: CGFloat = 500
    static let cornerRadius: CGFloat = Radius.lg
    static let draggableHeaderHeight: CGFloat = 48
    /// Width threshold above which the viewer switches to two-column layout
    static let wideLayoutThreshold: CGFloat = 500
}

enum TodoDesign {
    /// Minimum card height in grid mode — prevents tiny cards for short todos
    static let cardGridMinHeight: CGFloat = 130
}

enum VaultFileDesign {
    /// Height of the thumbnail/placeholder area in grid cards (non-image files)
    static let cardThumbnailHeight: CGFloat = 120
    /// Fallback height for image cards before thumbnail loads
    static let imageFallbackHeight: CGFloat = 160
    /// Height of the placeholder area in the detail panel
    static let detailPlaceholderHeight: CGFloat = 180
    /// Min/max preview heights for PDF and video in detail view
    static let detailPreviewMinHeight: CGFloat = 200
    static let detailPreviewMaxHeight: CGFloat = 500
    /// Audio player fixed height
    static let audioPlayerHeight: CGFloat = 60
    /// Audio player max height (same as fixed, for API parity)
    static let audioPlayerMaxHeight: CGFloat = 60
}

enum SnapMenuDesign {
    /// Width of the snap-target popover
    static let popoverWidth: CGFloat = 210
}

enum NewItemPopoverDesign {
    /// Height of each item-type card in the picker grid
    static let typeCardHeight: CGFloat = 62
}

enum LibraryTableDesign {
    /// Width of the leading checkbox column
    static let checkboxColumnWidth: CGFloat = 40
    /// Width of the trailing overflow-menu column
    static let menuColumnWidth: CGFloat = 40
    /// Height of each data row
    static let rowHeight: CGFloat = 40
    /// Height of the sticky header bar
    static let headerHeight: CGFloat = 32
    /// Width of the separator line between columns
    static let columnSeparatorWidth: CGFloat = 1
    /// Width of the invisible drag hit area on each column separator
    static let columnDragHitWidth: CGFloat = 10
    /// Width of the column-visibility picker popover
    static let columnPickerPopoverWidth: CGFloat = 160
    /// Minimum column width (referenced via TableColumnID.minWidth — kept here for symmetry)
    static let minColumnWidth: CGFloat = 60
}

enum CiderTabDesign {
    /// Minimum width of the rename text field inside a tab
    static let renameFieldMinWidth: CGFloat = 40
    /// Maximum width of the rename text field inside a tab
    static let renameFieldMaxWidth: CGFloat = 120
    /// Minimum width of the add-tab popover
    static let addTabPopoverMinWidth: CGFloat = 200
}

enum ClipboardDesign {
    /// Width of the collapsed-section chevron icon frame
    static let sectionChevronWidth: CGFloat = 12
    /// Width/height of the favicon thumbnail frame
    static let faviconSize: CGFloat = 16
    /// Max height of the image preview in a clipboard card
    static let imagePreviewMaxHeight: CGFloat = 120
    /// Height of the async placeholder while image loads
    static let imagePlaceholderHeight: CGFloat = 60
}

enum DetailToolbarDesign {
    /// Width/height of toolbar icon buttons (close, hero mode, etc.)
    static let iconButtonSize: CGFloat = 24
    /// Width/height of the larger toolbar buttons (e.g. info toggle, sidebar toggle)
    static let largeButtonSize: CGFloat = 28
}

enum FolderSidebarItemDesign {
    /// Width/height of the folder icon in sidebar rows
    static let folderIconSize: CGFloat = 20
    /// Width/height of the folder icon in sub-folder rows
    static let subFolderIconSize: CGFloat = 14
    /// Width of the metadata icon column in VaultFileDetailView meta rows
    static let metaIconWidth: CGFloat = 14
}

enum FolderDetailDesign {
    /// Minimum card width in the sub-folder grid
    static let subFolderCardMinWidth: CGFloat = 140
    /// Maximum card width in the sub-folder grid
    static let subFolderCardMaxWidth: CGFloat = 200
    /// Fixed width for the child-folder label column in the Subfolders preview rows
    static let subfolderPreviewLabelWidth: CGFloat = 168
}

enum TagColorPickerDesign {
    /// Width/height of a color swatch circle
    static let swatchSize: CGFloat = 24
    /// Width/height of the selection ring indicator inside a swatch
    static let selectionRingSize: CGFloat = 18
    /// Minimum GridItem adaptive cell width for a swatch color-picker grid (swatchSize + breathing room)
    static let gridCellMinWidth: CGFloat = 28
}

enum TagDotDesign {
    /// Diameter of the color dot in tag pills (TagPillView, SidebarTagPill, CompactTagPill)
    static let pillDotSize: CGFloat = 6
    /// Diameter of the color dot in the tag manager card header
    static let cardDotSize: CGFloat = 12
    /// Diameter of the color dot in the unused-tags hygiene list
    static let unusedDotSize: CGFloat = 8
    /// Diameter of the color dot in the filtered-tag header pill
    static let filterHeaderDotSize: CGFloat = 10
    /// Diameter of color dots inside similar-group rows
    static let groupRowDotSize: CGFloat = 6
    /// Diameter of color dots in merge-target popover rows
    static let mergeRowDotSize: CGFloat = 8
}

enum NewItemPopoverFormDesign {
    /// Overall popover panel width
    static let panelWidth: CGFloat = 264
    /// Back/close button frame size
    static let headerButtonSize: CGFloat = 28
    /// Primary action button height
    static let actionButtonHeight: CGFloat = 32
    /// Todo mode-picker row icon column width
    static let todoModeIconWidth: CGFloat = 20
    /// Tag swatch circle inside the creation form
    static let tagSwatchSize: CGFloat = 24
    /// Tag swatch selection ring inside the creation form
    static let tagSelectionRingSize: CGFloat = 18
}

enum TagPopoverDesign {
    /// Max height of the scrollable merge-target list
    static let mergeListMaxHeight: CGFloat = 300
    /// Width of the merge-target popover
    static let mergePopoverWidth: CGFloat = 240
    /// Width of the tag-color picker popover
    static let colorPickerWidth: CGFloat = 200
    /// Width of the inline tag creation form
    static let creationFormWidth: CGFloat = 220
    /// Max height of the tag-filter scroll section in ViewOptionsDropdown
    static let filterScrollMaxHeight: CGFloat = 120
    /// Minimum adaptive grid card width in the tag manager card grid
    static let managerCardMinWidth: CGFloat = 180
}

enum SelectionCheckmarkDesign {
    /// Diameter of the checkmark circle badge
    static let circleSize: CGFloat = 20
}

enum ClipboardViewerTableDesign {
    /// CompactTagPill color dot diameter
    static let tagDotSize: CGFloat = 5
}

enum TagPillDesign {
    /// Background fill opacity for colored tag pills (applied to dynamic label color)
    static let fillOpacity: CGFloat = 0.12
    /// Stroke border opacity for colored tag pills (applied to dynamic label color)
    static let strokeOpacity: CGFloat = 0.2
}

enum ViewOptionsDesign {
    /// Width of the view-options popover panel
    static let popoverWidth: CGFloat = 210
    /// Width × height of the segmented group-by icon button
    static let segmentButtonWidth: CGFloat = 32
    static let segmentButtonHeight: CGFloat = 28
}

enum GenericItemDetailDesign {
    /// Maximum width of the editable title text field
    static let titleFieldMaxWidth: CGFloat = 200
}

enum HomeDesign {
    /// Height of each row in the Continue section
    static let continueRowHeight: CGFloat = Spacing.xxxl
    /// Width of the leading icon column in Continue rows
    static let continueRowIconWidth: CGFloat = Spacing.lg
    /// Minimum width of a Coming Up card in the horizontal scroll strip
    static let comingUpCardMinWidth: CGFloat = BookmarksDesign.cardMinWidth
}

enum HomeOverviewDesign {
    static let maxContentWidth: CGFloat = 1560
    static let telemetryTopPadding: CGFloat = Spacing.xs
    static let rowSpacing: CGFloat = Spacing.md
    static let columnSpacing: CGFloat = Spacing.md
    static let fullLayoutTrackWeights: [CGFloat] = [1.2, 2.55, 1.9, 1.35]
    static let fullLayoutTopRowHeight: CGFloat = 270
    static let activityTimelinePanelHeight: CGFloat = 252
    static let fullLayoutMiddleRowHeight: CGFloat = 460
    static let fullLayoutBottomRowHeight: CGFloat = 292
    static let topRowMinHeight: CGFloat = 160
    static let overviewPanelFixedHeight: CGFloat = 270
    static let profilePanelFixedHeight: CGFloat = 222
    static let attentionMetricTileHeight: CGFloat = 76
    static let embeddedAttentionMetricTileHeight: CGFloat = 72
    static let quickActionButtonHeight: CGFloat = 36
    static let recentActivityBaseHeight: CGFloat = 160
    static let recentActivityRowHeightEstimate: CGFloat = 34
    static let upcomingPanelFixedHeight: CGFloat = 244
    static let closedTabsBaseMinHeight: CGFloat = 124
    static let closedTabsPanelMinHeight: CGFloat = 292
    static let closedTabsVisibleRowCount: Int = 2
    static let closedTabsFullColumnCount: Int = 4
    static let closedTabsCompactColumnCount: Int = 3
    static let closedTabsSingleColumnCount: Int = 2
    static let closedTabCardHeight: CGFloat = 102
    static let resurfacePanelMinHeight: CGFloat = 208
    static let resurfacePanelRowHeightEstimate: CGFloat = 120
    static let resurfaceCardHeight: CGFloat = 72
    static let telemetryInset: CGFloat = Spacing.sm
    static let dayChipMinWidth: CGFloat = 58
    static let compactLayoutThreshold: CGFloat = 1120
    static let singleColumnLayoutThreshold: CGFloat = 760
}

enum AIAssistantPanelDesign {
    static let defaultWidth: CGFloat = 380
    static let defaultHeight: CGFloat = 520
    static let minWidth: CGFloat = 320
    static let minHeight: CGFloat = 340
    static let cornerRadius: CGFloat = Radius.lg
    static let titleBarHeight: CGFloat = 40
    static let draggableHeaderHeight: CGFloat = 44
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
    static let warning = Color(.systemYellow)

    // Backgrounds
    static let opaqueBackground = Color(.windowBackgroundColor)

    // MARK: - Surfaces (white-based fills)

    /// Acrylic shimmer layer
    static let surfaceHighlight = Color.white.opacity(0.03)
    /// Empty states, faint section backgrounds
    static let surfaceSubtle = Color.white.opacity(0.04)
    /// Cards, sidebar rows, raised surfaces
    static let surfaceElevated = Color.white.opacity(0.06)
    /// Buttons, pills, input fields, list row hover
    static let surfaceInput = Color.white.opacity(0.08)
    /// Hover state for elevated surfaces
    static let surfaceHover = Color.white.opacity(0.1)

    // MARK: - Borders (white-based strokes)

    /// Faint borders (note card default)
    static let borderSubtle = Color.white.opacity(0.08)
    /// Standard element borders
    static let borderDefault = Color.white.opacity(0.12)
    /// Border on hover
    static let borderHover = Color.white.opacity(0.18)
    /// Emphasized borders (detail sheets)
    static let borderStrong = Color.white.opacity(0.2)
    /// Outer panel stroke
    static let borderPanel = Color.white.opacity(0.25)

    // MARK: - Backdrops & Overlays (black-based)

    /// Dimming behind overlays and compact sidebar
    static let backdrop = Color.black.opacity(0.28)
    /// Main panel acrylic dark tint
    static let acrylicTint = Color.black.opacity(0.45)
    /// Overlay/palette acrylic tint (lighter than main)
    static let acrylicOverlayTint = Color.black.opacity(0.38)
    /// Traffic light hover icon color
    static let trafficLightSymbol = Color.black.opacity(0.65)

    // MARK: - Shadows (for .shadow() modifiers)

    /// Subtle icon/element shadow
    static let shadowLight = Color.black.opacity(0.2)
    /// Standard card/sheet shadow
    static let shadowMedium = Color.black.opacity(0.28)
    /// Deep floating palette/modal shadow
    static let shadowHeavy = Color.black.opacity(0.4)

    // MARK: - Overlays

    /// Dark overlay on drag preview / thumbnail
    static let overlayDark = Color.black.opacity(0.72)
    /// Badge/counter pill background on thumbnails
    static let overlayBadge = Color.black.opacity(0.55)
    /// Hover gradient overlay on thumbnail footers
    static let gradientOverlay = Color.black.opacity(0.6)
    /// Delete/action button circle background on hover
    static let overlayButton = Color.black.opacity(0.7)
    /// Subtle backdrop for in-panel overlays (details sheets)
    static let backdropSubtle = Color.black.opacity(0.14)
    /// Hero preview stage gradient (dark end)
    static let stageGradientStart = Color.black.opacity(0.34)
    /// Hero preview stage gradient (light end)
    static let stageGradientEnd = Color.black.opacity(0.22)
    /// Label pill background for folder cover image reposition hint
    static let coverBannerLabel = Color.black.opacity(0.5)

    // MARK: - Text on Color

    /// Bright text on gradient/colored backgrounds
    static let textOnColor = Color.white.opacity(0.9)
    /// Dimmed secondary text on gradient/colored backgrounds
    static let textOnColorDim = Color.white.opacity(0.7)
    /// Subtle (inactive) indicator on gradient/colored backgrounds — carousel page dots
    static let textOnColorSubtle = Color.white.opacity(0.4)

    // MARK: - Shimmer Animation

    /// Peak brightness of shimmer band
    static let shimmerPeak = Color.white.opacity(0.22)

    // MARK: - Additional Borders

    /// Settings selected-row border / progress track
    static let borderSelected = Color.white.opacity(0.14)
    /// Selection ring on color picker swatches (solid white ring)
    static let colorPickerSelectionRing = Color.white

    // MARK: - Selection & Drop Targets (accent-based)

    /// Selected row/card fill
    static let selectedFill = controlAccent.opacity(0.14)
    /// Selected row/card border
    static let selectedBorder = controlAccent.opacity(0.48)
    /// Drag-over highlight fill
    static let dropTargetFill = controlAccent.opacity(0.2)
    /// Drag-over border
    static let dropTargetBorder = controlAccent.opacity(0.72)
    /// Strong drop target indicator
    static let dropTargetBorderStrong = controlAccent.opacity(0.65)

    // MARK: - Accent Tints

    /// Barely-tinted accent backgrounds
    static let accentSubtle = controlAccent.opacity(0.08)
    /// Light accent (pressed states, subtle selection)
    static let accentLight = controlAccent.opacity(0.12)
    /// Accent-colored text and labels
    static let accentText = controlAccent.opacity(0.8)
    /// Selected interactive element (view option toggle)
    static let accentSelected = controlAccent.opacity(0.18)
    /// Medium accent fill (avatar circles)
    static let accentMedium = controlAccent.opacity(0.2)
    /// Accent-colored border (sidebar drop target)
    static let accentBorder = controlAccent.opacity(0.3)
    /// Dimmed accent fill (note card left accent bar)
    static let accentDim = controlAccent.opacity(0.55)
    /// Near-solid accent (progress bar fill)
    static let accentSolid = controlAccent.opacity(0.88)

    // MARK: - Separator-based Fills (neutral gray scale)

    /// Faint neutral fill (home sections, button rest states)
    static let separatorSubtle = separator.opacity(0.2)
    /// Light neutral fill (tab badge, search bar background)
    static let separatorLight = separator.opacity(0.25)
    /// Medium neutral fill (selected list row, tab border)
    static let separatorMedium = separator.opacity(0.3)
    /// Firm neutral fill (selected tab badge, hover button)
    static let separatorFirm = separator.opacity(0.4)
    /// Strong neutral border (panel inner stroke, settings sections)
    static let separatorStrong = separator.opacity(0.5)
    /// Solid neutral fill (toolbar divider, active indicator)
    static let separatorSolid = separator.opacity(0.7)

    // MARK: - Destructive Fills

    /// Faint warning background (due-today badges)
    static let warningSubtle = warning.opacity(0.08)
    /// Faint destructive background (button rest state)
    static let destructiveSubtle = destructive.opacity(0.08)
    /// Light destructive background (button hover/fill)
    static let destructiveLight = destructive.opacity(0.14)

    // MARK: - Success Fills

    /// Muted success indicator
    static let successMuted = success.opacity(0.7)
    /// Faint success background (saved-item pill rest state)
    static let successSubtle = success.opacity(0.08)

    // MARK: - Sidecar Tag Colors

    /// Faint tinted background for AI/vault sidecar tag pills
    static let sidecarTagFill = primary.opacity(0.06)
    /// Hairline border for AI/vault sidecar tag pills
    static let sidecarTagBorder = primary.opacity(0.08)

    // MARK: - Gradient Tint

    /// Palette/thumbnail gradient tint opacity
    static let gradientTint: CGFloat = 0.8

    // MARK: - View Opacity (for Divider/element dimming)

    /// Primary settings divider opacity
    static let dividerPrimaryOpacity: CGFloat = 0.28
    /// Secondary settings divider opacity (lighter)
    static let dividerSecondaryOpacity: CGFloat = 0.22

    // MARK: - Shadow Shape Opacity (custom blurred shadow technique)

    // MARK: - Editor Highlight Colors

    /// Note editor text highlight swatches
    static let highlightYellow = Color.yellow
    static let highlightGreen = Color.green
    static let highlightBlue = Color.blue
    static let highlightPink = Color.pink
    static let highlightOrange = Color.orange
    static let highlightPurple = Color.purple

    // MARK: - View State Opacity

    /// Disabled element opacity
    static let disabledOpacity: CGFloat = 0.55
}


// MARK: - Color helpers

extension Color {
    /// Initialize from a CSS hex string like `"#RRGGBB"` or `"#RGB"`.
    init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
