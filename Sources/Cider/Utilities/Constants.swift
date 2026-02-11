import SwiftUI
import Foundation

extension Notification.Name {
    static let ciderMinimizedStateChanged = Notification.Name("ciderMinimizedStateChanged")
    static let dismissCommandPalette = Notification.Name("cider.dismissCommandPalette")
    static let toggleCommandPalette = Notification.Name("cider.toggleCommandPalette")
    static let openCiderSettings = Notification.Name("cider.openCiderSettings")
    static let dismissSettings = Notification.Name("cider.dismissSettings")
    static let ciderConfigChanged = Notification.Name("cider.ciderConfigChanged")
    static let ciderTileActionCompleted = Notification.Name("cider.tileActionCompleted")
    static let ciderDynamicTileGroupChanged = Notification.Name("cider.dynamicTileGroupChanged")
    static let toggleNotes = Notification.Name("cider.toggleNotes")
    static let dismissNotes = Notification.Name("cider.dismissNotes")
    static let openNoteInPanel = Notification.Name("cider.openNoteInPanel")
    static let toggleNotesCollapse = Notification.Name("cider.toggleNotesCollapse")
    static let moveNotesToNextDisplay = Notification.Name("cider.moveNotesToNextDisplay")
    static let toggleBookmarks = Notification.Name("cider.toggleBookmarks")
    static let dismissBookmarks = Notification.Name("cider.dismissBookmarks")
    static let showBookmarks = Notification.Name("cider.showBookmarks")
    static let toggleBookmarksCollapse = Notification.Name("cider.toggleBookmarksCollapse")
    static let showBookmarkCaptureToast = Notification.Name("cider.showBookmarkCaptureToast")
    static let showBookmarkClipboardReviewToast = Notification.Name("cider.showBookmarkClipboardReviewToast")
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

    // Dynamic tiling
    static let tileGap: CGFloat = 5

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
    static let detailsHeroFallbackLetterSize: CGFloat = 54
    static let detailsSheetPreferredWidthRatio: CGFloat = 0.96
    static let detailsSheetPreferredHeightRatio: CGFloat = 0.97
    static let detailsSheetURLMinHeight: CGFloat = 44
    static let detailsSheetNotesMinHeight: CGFloat = 120
    static let detailsSheetNotesHeight: CGFloat = 200
    static let detailsBackdropOpacity: CGFloat = 0.14
    static let detailsContentBlurRadius: CGFloat = 12
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
