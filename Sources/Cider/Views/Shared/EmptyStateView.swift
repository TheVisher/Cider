import SwiftUI

/// Shared empty state for tabs, folders, and panels.
///
/// Standard layout: vertically centered icon + title, with optional subtitle and action button.
/// Fills available space by default.
///
/// Usage:
/// ```
/// EmptyStateView(icon: "note.text", title: "No notes yet")
///
/// EmptyStateView(
///     icon: "note.text",
///     title: "No notes yet",
///     actionLabel: "Create New Note",
///     action: { createNote() }
/// )
/// ```
struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: icon)
                .font(CiderFont.emptyStateIcon)
                .foregroundColor(CiderColors.tertiary)

            Text(title)
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.secondary)

            if let subtitle {
                Text(subtitle)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .multilineTextAlignment(.center)
            }

            if let actionLabel, let action {
                Button(actionLabel, action: action)
                    .buttonStyle(.plain)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.controlAccent)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
