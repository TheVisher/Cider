import SwiftUI

/// A card representing a single Claude Code session, with compact/expanded states.
struct ClaudeSessionCard: View {
    let session: ClaudeSession
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onStop: () -> Void
    let onDelete: () -> Void
    let onSendMessage: (String) -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isRunning: Bool {
        if case .working = session.status { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            compactHeader
                .padding(Spacing.md)

            if isExpanded {
                Divider()
                ClaudeSessionChatView(
                    session: session,
                    onSend: onSendMessage
                )
                .transition(.opacity)
            }
        }
        .cardContainer(isHovered: isHovered, cornerRadius: Radius.md)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
    }

    // MARK: - Compact Header

    private var compactHeader: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(session.name)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(session.projectPath)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                SessionStatusBadge(status: session.status)
            }

            // Last message preview (compact only)
            if !isExpanded, let lastMsg = session.messages.last(where: { $0.role == .assistant || $0.role == .user }) {
                Text(lastMsg.content)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(2)
            }

            // Action buttons
            HStack(spacing: Spacing.sm) {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Collapse" : "Expand")

                Spacer()

                if isRunning {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.destructive)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel response")
                }

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .help("Delete session")
            }
        }
    }
}
