import SwiftUI

/// Renders a single chat message in a Claude session, styled by role.
struct ClaudeMessageBubble: View {
    let message: ClaudeSessionMessage
    @State private var isToolExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .toolUse, .toolResult:
            toolBubble
        case .system:
            systemBubble
        }
    }

    // MARK: - User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: Spacing.xxxl)
            Text(message.content)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.15))
                )
                .textSelection(.enabled)
        }
    }

    // MARK: - Assistant

    private var assistantBubble: some View {
        HStack {
            Text(message.content)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.primary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(CiderColors.surfaceElevated)
                )
                .textSelection(.enabled)
            Spacer(minLength: Spacing.xxxl)
        }
    }

    // MARK: - Tool

    private var toolBubble: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    isToolExpanded.toggle()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: message.role == .toolUse ? "wrench" : "checkmark.circle")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                    Text(message.toolName ?? "tool")
                        .font(CiderFont.monospacedBody)
                        .foregroundColor(CiderColors.secondary)
                    Spacer()
                    Image(systemName: isToolExpanded ? "chevron.up" : "chevron.down")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isToolExpanded {
                Text(message.content)
                    .font(CiderFont.monospacedBody)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(20)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceElevated.opacity(0.5))
        )
    }

    // MARK: - System

    private var systemBubble: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
            Spacer()
        }
    }
}
