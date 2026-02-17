import SwiftUI

// MARK: - Section Container

/// Static elevated container with rounded border — for sidebar columns, panel sections, folder cards.
///
/// Applies: `surfaceElevated` fill + `borderDefault` stroke + `innerStrokeWidth`.
///
/// Usage:
/// ```
/// folderSidebar
///     .sectionContainer()
/// ```
private struct SectionContainerModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(CiderColors.surfaceElevated))
            .overlay(shape.stroke(CiderColors.borderDefault, lineWidth: CiderBorder.innerStrokeWidth))
    }
}

extension View {
    /// Applies the standard elevated section container style (fill + border).
    func sectionContainer(cornerRadius: CGFloat = Radius.md) -> some View {
        modifier(SectionContainerModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Card Container

/// Hover-aware card container with background, border, clip, and content shape.
///
/// Applies: hover-responsive `surfaceElevated`/`surfaceHover` fill,
/// `borderSubtle`/`borderHover` stroke, clipShape, and contentShape.
///
/// Usage:
/// ```
/// cardContent
///     .cardContainer(isHovered: isHovered)
/// ```
private struct CardContainerModifier: ViewModifier {
    var isHovered: Bool
    var isSelected: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(shape.fill(isHovered ? CiderColors.surfaceHover : CiderColors.surfaceElevated))
            .overlay(shape.stroke(
                isSelected
                    ? CiderColors.selectedBorder
                    : isHovered ? CiderColors.borderHover : CiderColors.borderSubtle,
                lineWidth: isSelected ? CiderBorder.innerStrokeWidth : 1
            ))
            .clipShape(shape)
            .contentShape(shape)
    }
}

extension View {
    /// Applies the standard hover-aware card container style (fill + border + clip + contentShape).
    func cardContainer(
        isHovered: Bool,
        isSelected: Bool = false,
        cornerRadius: CGFloat = BookmarksDesign.cardCornerRadius
    ) -> some View {
        modifier(CardContainerModifier(isHovered: isHovered, isSelected: isSelected, cornerRadius: cornerRadius))
    }
}
