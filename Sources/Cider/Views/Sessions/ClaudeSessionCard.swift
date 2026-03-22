import SwiftUI

/// A card representing a single Claude Code agent, with compact/expanded states.
///
/// Compact: name, project path, status badge, last message preview, action row.
/// Expanded: full-width card with chat view that fills available space.
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
            // Header — always visible
            cardHeader
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.md)
                .padding(.bottom, isExpanded ? Spacing.sm : Spacing.md)

            if isExpanded {
                Divider()
                ClaudeSessionChatView(
                    session: session,
                    onSend: onSendMessage
                )
                .transition(.opacity)
            } else {
                // Compact content
                compactContent
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.md)
            }
        }
        .cardContainer(isHovered: isHovered, cornerRadius: Radius.md)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .onTapGesture {
            if !isExpanded { onToggleExpand() }
        }
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
    }

    // MARK: - Card Header (shared between compact and expanded)

    private var cardHeader: some View {
        HStack(spacing: Spacing.sm) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: Spacing.sm, height: Spacing.sm)

            Text(session.name)
                .font(isExpanded ? CiderFont.headingSemibold : CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Text(session.projectPath.components(separatedBy: "/").suffix(2).joined(separator: "/"))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .lineLimit(1)
                .truncationMode(.head)

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

            if isExpanded {
                Button(action: onToggleExpand) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .help("Collapse")
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete agent")
        }
    }

    // MARK: - Compact Content

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if isRunning, let lastMsg = session.messages.last(where: { $0.role == .assistant }) {
                // Working: show streaming preview
                HStack(spacing: Spacing.xs) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(lastMsg.content.suffix(80))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                }
            } else if let lastMsg = session.messages.last(where: { $0.role == .assistant || $0.role == .user }) {
                // Idle: show last message preview
                Text(lastMsg.content)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(2)
            } else {
                // No messages yet
                Text("Click to start chatting")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.tertiary)
                    .italic()
            }
        }
    }

    private var statusColor: Color {
        switch session.status {
        case .idle: CiderColors.tertiary
        case .working: CiderColors.success
        case .waitingForApproval: CiderColors.warning
        case .error: CiderColors.destructive
        case .stopped: CiderColors.tertiary
        }
    }
}
