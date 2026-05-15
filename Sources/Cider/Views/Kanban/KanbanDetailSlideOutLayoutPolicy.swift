import SwiftUI

struct KanbanDetailSlideOutLayoutPolicy {
    struct State: Equatable {
        var width: CGFloat
        var sourceNotesVisible: Bool
        var metadataVisible: Bool
    }

    static let dashboardMinimumWidth: CGFloat = 420
    static let sourceNotesMinimumWidth: CGFloat = 360

    private static let contentHorizontalPadding = Spacing.xl * 2
    private static let contentColumnSpacing = Spacing.xl
    private static let shellChromeWidth = SlideOutDesign.dragHandleWidth

    static func minimumWidth(sourceNotesVisible: Bool, metadataVisible: Bool) -> CGFloat {
        var width = dashboardMinimumWidth + contentHorizontalPadding + shellChromeWidth

        if sourceNotesVisible {
            width += contentColumnSpacing + sourceNotesMinimumWidth
        }

        if metadataVisible {
            width += BookmarksDesign.detailsSidebarFixedWidth
        }

        return max(BookmarksDesign.detailsSlideOutMinWidth, ceil(width))
    }

    static func fittingState(
        for width: CGFloat,
        sourceNotesVisible: Bool,
        metadataVisible: Bool
    ) -> State {
        let clampedWidth = max(BookmarksDesign.detailsSlideOutMinWidth, width)
        var nextSourceNotesVisible = sourceNotesVisible
        var nextMetadataVisible = metadataVisible

        if nextMetadataVisible,
           clampedWidth < minimumWidth(
            sourceNotesVisible: nextSourceNotesVisible,
            metadataVisible: nextMetadataVisible
           ) {
            nextMetadataVisible = false
        }

        if nextSourceNotesVisible,
           clampedWidth < minimumWidth(
            sourceNotesVisible: nextSourceNotesVisible,
            metadataVisible: nextMetadataVisible
           ) {
            nextSourceNotesVisible = false
        }

        return State(
            width: max(
                clampedWidth,
                minimumWidth(
                    sourceNotesVisible: nextSourceNotesVisible,
                    metadataVisible: nextMetadataVisible
                )
            ),
            sourceNotesVisible: nextSourceNotesVisible,
            metadataVisible: nextMetadataVisible
        )
    }

    static func expandedWidth(
        currentWidth: CGFloat,
        maxWidth: CGFloat,
        sourceNotesVisible: Bool,
        metadataVisible: Bool
    ) -> CGFloat {
        min(
            maxWidth,
            max(
                currentWidth,
                minimumWidth(
                    sourceNotesVisible: sourceNotesVisible,
                    metadataVisible: metadataVisible
                )
            )
        )
    }
}
