import SwiftUI

/// View modifier that binds hover state to a `@State` Bool.
///
/// Respects Reduce Motion: when an animation is specified and Reduce Motion is on,
/// the animation is replaced with `.none` (instant).
///
/// Usage:
/// ```
/// // Plain — use when the view already has .animation(_, value: isHovered)
/// .hoverState($isHovered)
///
/// // Animated — wraps state change in withAnimation(.snappy)
/// .hoverState($isHovered, animation: .snappy)
/// ```
private struct HoverStateModifier: ViewModifier {
    @Binding var isHovered: Bool
    var animation: Animation?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if let animation {
                withAnimation(reduceMotion ? .none : animation) {
                    isHovered = hovering
                }
            } else {
                isHovered = hovering
            }
        }
    }
}

extension View {
    /// Binds hover state to a `@State` Bool.
    ///
    /// - Parameters:
    ///   - isHovered: Binding to the hover state.
    ///   - animation: Optional animation for the state change (default: `nil`).
    ///     Pass `.snappy` for animated hover. Pass `nil` when the view already
    ///     has `.animation(_, value: isHovered)` applied.
    func hoverState(
        _ isHovered: Binding<Bool>,
        animation: Animation? = nil
    ) -> some View {
        modifier(HoverStateModifier(isHovered: isHovered, animation: animation))
    }
}
