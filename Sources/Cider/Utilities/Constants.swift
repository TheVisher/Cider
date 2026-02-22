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

// MARK: - Notification Names

extension Notification.Name {
    static let openCiderSettings = Notification.Name("cider.openCiderSettings")
    static let settingsNavigate = Notification.Name("cider.settingsNavigate")
    static let dismissSettings = Notification.Name("cider.dismissSettings")
    static let ciderConfigChanged = Notification.Name("cider.ciderConfigChanged")
    static let showBookmarkCaptureToast = Notification.Name("cider.showBookmarkCaptureToast")
    static let showBookmarkClipboardReviewToast = Notification.Name("cider.showBookmarkClipboardReviewToast")
    static let toggleCiderPanel = Notification.Name("cider.toggleCiderPanel")
    static let dismissCiderPanel = Notification.Name("cider.dismissCiderPanel")
    static let toggleCiderPanelCollapse = Notification.Name("cider.toggleCiderPanelCollapse")
    static let maximizeCiderPanel = Notification.Name("cider.maximizeCiderPanel")
    static let showDetailPopover = Notification.Name("cider.showDetailPopover")
    static let dismissDetailPopover = Notification.Name("cider.dismissDetailPopover")
    static let expandCiderPanelForDetailModal = Notification.Name("cider.expandCiderPanelForDetailModal")
    static let restoreCiderPanelAfterDetailModal = Notification.Name("cider.restoreCiderPanelAfterDetailModal")
    static let showBookmarkAddForm = Notification.Name("cider.showBookmarkAddForm")
    static let triggerNewNoteInTab = Notification.Name("cider.triggerNewNoteInTab")
    static let showFolderCreationField = Notification.Name("cider.showFolderCreationField")
    static let showUndoToast = Notification.Name("cider.showUndoToast")
    static let pauseUndoToastDismiss = Notification.Name("cider.pauseUndoToastDismiss")
    static let resumeUndoToastDismiss = Notification.Name("cider.resumeUndoToastDismiss")
    static let toggleNoteEditor = Notification.Name("cider.toggleNoteEditor")
    static let editorRequestClose = Notification.Name("cider.editorRequestClose")
    static let captureBookmark = Notification.Name("cider.captureBookmark")
    static let trashContentsChanged = Notification.Name("cider.trashContentsChanged")
    static let openExternalSourceAndSelectFile = Notification.Name("cider.openExternalSourceAndSelectFile")
}

enum CiderBorder {
    static let innerStrokeWidth: CGFloat = 1.5
    static let innerStrokeInset: CGFloat = 0.75
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

    // Shadow padding - extra space in window for shadow to render
    static let shadowPaddingHorizontal: CGFloat = 70
    static let shadowPaddingTop: CGFloat = 20
    static let shadowPaddingBottom: CGFloat = 70
}

enum NotesDesign {
    static let defaultWidth: CGFloat = 400
    static let defaultHeight: CGFloat = 520
    static let minWidth: CGFloat = 300
    static let minHeight: CGFloat = 300
    static let cornerRadius: CGFloat = Radius.lg
    static let shadowPadding: CGFloat = 40
    static let titleBarHeight: CGFloat = 40
    static let toolbarHeight: CGFloat = 36
    static let findBarHeight: CGFloat = 36
    static let toolbarButtonSize: CGFloat = 28
    static let toolbarIconSize: CGFloat = 11
    static let toolbarDividerHeight: CGFloat = 16
    static let panelTopPadding: CGFloat = 20
    static let panelBottomPadding: CGFloat = 15
    static let panelCollapsedBottomPadding: CGFloat = panelTopPadding
    static let collapsedContentHeight: CGFloat = titleBarHeight
    static let trafficLightDiameter: CGFloat = 12
    static let trafficLightTapTarget: CGFloat = Spacing.lg
    static let trafficLightSpacing: CGFloat = Spacing.xs
    static let trafficLightSymbolSize: CGFloat = 7
    static let collapseToggleAnimationDuration: TimeInterval = 0.18

    static var panelDefaultWidth: CGFloat {
        defaultWidth + shadowPadding * 2
    }

    static var panelDefaultHeight: CGFloat {
        defaultHeight + panelTopPadding + shadowPadding + panelBottomPadding
    }

    static var panelMinWidth: CGFloat {
        minWidth + shadowPadding * 2
    }

    static var panelMinHeight: CGFloat {
        minHeight + panelTopPadding + shadowPadding + panelBottomPadding
    }

    static var panelCollapsedHeight: CGFloat {
        collapsedContentHeight + panelTopPadding + panelCollapsedBottomPadding
    }
}

enum BookmarksDesign {
    static let panelWidth: CGFloat = 760
    static let panelHeight: CGFloat = 620
    static let panelMinWidth: CGFloat = 520
    static let panelMinHeight: CGFloat = 420
    static let panelCornerRadius: CGFloat = Radius.lg
    static let panelShadowPadding: CGFloat = 40
    static let panelTopPadding: CGFloat = 20
    static let panelBottomPadding: CGFloat = 15
    static let panelCollapsedBottomPadding: CGFloat = panelTopPadding

    static let toolbarHeight: CGFloat = 40
    static let collapsedContentHeight: CGFloat = toolbarHeight
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
    static let thumbnailIconCandidateMaxAspectDelta: CGFloat = 0.28
    static let cardMinWidth: CGFloat = 220
    static let cardContentSpacing: CGFloat = Spacing.sm
    static let cardCornerRadius: CGFloat = Radius.md
    static let cardSizePickerMaxWidth: CGFloat = 168
    static let folderSidebarWidth: CGFloat = 224
    static let folderSidebarRowMinHeight: CGFloat = 30
    static let folderSidebarIndent: CGFloat = 14
    static let detailsRequiredPanelWidth: CGFloat = 980
    static let detailsSheetMinWidth: CGFloat = 760
    static let detailsSheetMaxWidth: CGFloat = 1540
    static let detailsSheetMinHeight: CGFloat = 460
    static let detailsSheetMaxHeight: CGFloat = 940
    static let detailsCanvasCornerRadius: CGFloat = Radius.md
    static let detailsCanvasInset: CGFloat = Spacing.sm
    static let detailsFloatingLiftBlur: CGFloat = 8
    static let detailsFloatingLiftYOffset: CGFloat = 3
    static let detailsSidebarMinWidth: CGFloat = 300
    static let detailsSidebarMaxWidth: CGFloat = 440
    static let detailsSidebarWidthRatio: CGFloat = 0.34
    static let detailsHeroMinHeight: CGFloat = 280
    static let detailsHeroMaxHeight: CGFloat = 520
    static let cardFallbackLetterSize: CGFloat = 26
    static let listFallbackLetterSize: CGFloat = 16
    static let detailsHeroFallbackLetterSize: CGFloat = 54
    static let detailsSheetPreferredWidthRatio: CGFloat = 0.96
    static let detailsSheetPreferredHeightRatio: CGFloat = 0.97
    static let detailsSheetURLMinHeight: CGFloat = 44
    static let detailsSheetNotesMinHeight: CGFloat = 120
    static let detailsSheetNotesHeight: CGFloat = 200
    static let detailsBackdropOpacity: CGFloat = 0.14
    static let detailsContentBlurRadius: CGFloat = 12
    static let folderShelfMinHeight: CGFloat = 132
    static let folderShelfCardWidth: CGFloat = 168
    static let folderShelfCardHeight: CGFloat = 88
    static let folderShelfPreviewGridDimension: Int = 2
    static let folderShelfPreviewGridSpacing: CGFloat = 2
    static let folderShelfPreviewCornerRadius: CGFloat = Radius.xs
    static let folderShelfPreviewCellWidth: CGFloat = 24
    static let folderShelfPreviewCellHeight: CGFloat = 18
    static let folderShelfPreviewLetterSize: CGFloat = 10
    static let folderShelfDragStateTimeout: TimeInterval = 8.0
    static let folderShelfRailHeight: CGFloat = 34
    static let folderShelfRailChipMinWidth: CGFloat = 112
    static let folderFlyoutMenuWidth: CGFloat = 280
    static let folderFlyoutRowHeight: CGFloat = 30
    static let folderFlyoutMaxHeight: CGFloat = 200
    static let folderFlyoutRowIndent: CGFloat = 14
    static let folderFlyoutVerticalGap: CGFloat = Spacing.sm
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
    static let layoutPickerMaxWidth: CGFloat = 320
    static let collapseToggleAnimationDuration: TimeInterval = 0.18

    static var panelContentWidth: CGFloat {
        panelWidth + panelShadowPadding * 2
    }

    static var panelContentHeight: CGFloat {
        panelHeight + panelTopPadding + panelShadowPadding + panelBottomPadding
    }

    static var panelCollapsedHeight: CGFloat {
        collapsedContentHeight + panelTopPadding + panelCollapsedBottomPadding
    }
}

enum BookmarksToastDesign {
    static let width: CGFloat = 320
    static let height: CGFloat = 56
    static let reviewHeight: CGFloat = 96
    static let cornerRadius: CGFloat = Radius.md
    static let shadowPadding: CGFloat = 24
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
    static let shadowPadding: CGFloat = 24
    static let autoHideDuration: TimeInterval = 5.0
    static let panelEdgeInset: CGFloat = Spacing.md

    static var panelWidth: CGFloat {
        width + shadowPadding * 2
    }

    static var panelHeight: CGFloat {
        height + shadowPadding * 2
    }
}

enum SearchPaletteDesign {
    static let paletteWidth: CGFloat = 560
    static let paletteMaxHeight: CGFloat = 480
    static let resultsMaxHeight: CGFloat = 400
    static let searchFieldHeight: CGFloat = 52
    static let backdropOpacity: CGFloat = 0.28
    static let paletteVerticalOffset: CGFloat = 60
    static let recentBookmarkCount = 3
    static let recentNoteCount = 2
}

enum CiderPanelDesign {
    static let defaultWidth: CGFloat = 780
    static let defaultHeight: CGFloat = 640
    static let minWidth: CGFloat = 540
    static let minHeight: CGFloat = 440
    static let cornerRadius: CGFloat = Radius.lg
    static let shadowPadding: CGFloat = 40
    static let topPadding: CGFloat = 28
    static let bottomPadding: CGFloat = 15
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
    /// Subtle backdrop for in-panel overlays (details sheets)
    static let backdropSubtle = Color.black.opacity(0.14)
    /// Hero preview stage gradient (dark end)
    static let stageGradientStart = Color.black.opacity(0.34)
    /// Hero preview stage gradient (light end)
    static let stageGradientEnd = Color.black.opacity(0.22)

    // MARK: - Text on Color

    /// Bright text on gradient/colored backgrounds
    static let textOnColor = Color.white.opacity(0.9)

    // MARK: - Shimmer Animation

    /// Peak brightness of shimmer band
    static let shimmerPeak = Color.white.opacity(0.22)

    // MARK: - Additional Borders

    /// Settings selected-row border / progress track
    static let borderSelected = Color.white.opacity(0.14)

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

    /// Faint destructive background (button rest state)
    static let destructiveSubtle = destructive.opacity(0.08)
    /// Light destructive background (button hover/fill)
    static let destructiveLight = destructive.opacity(0.14)

    // MARK: - Success Fills

    /// Muted success indicator
    static let successMuted = success.opacity(0.7)

    // MARK: - Gradient Tint

    /// Palette/thumbnail gradient tint opacity
    static let gradientTint: CGFloat = 0.8

    // MARK: - View Opacity (for Divider/element dimming)

    /// Primary settings divider opacity
    static let dividerPrimaryOpacity: CGFloat = 0.28
    /// Secondary settings divider opacity (lighter)
    static let dividerSecondaryOpacity: CGFloat = 0.22

    // MARK: - Shadow Shape Opacity (custom blurred shadow technique)

    /// Full/expanded panel shadow shape opacity
    static let shadowShapeFullOpacity: CGFloat = 0.7
    /// Compact/collapsed panel shadow shape opacity
    static let shadowShapeCompactOpacity: CGFloat = 0.52

    // MARK: - View State Opacity

    /// Disabled element opacity
    static let disabledOpacity: CGFloat = 0.55
}
