import SwiftUI

struct AIChatBubbleView: View {
    let message: AIChatMessage

    var body: some View {
        switch message.role {
        case .user:
            userBubble
        case .assistant:
            assistantBubble
        case .system:
            systemBubble
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 60)
            Text(message.content)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.primary)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(CiderColors.accentSubtle)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.accentBorder, lineWidth: 1)
                )
        }
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if message.content.isEmpty && message.isStreaming {
                    streamingIndicator
                } else {
                    Text(message.content)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.primary)
                        .textSelection(.enabled)

                    if message.isStreaming {
                        streamingIndicator
                    }
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.borderDefault, lineWidth: 1)
            )

            Spacer(minLength: 60)
        }
    }

    // MARK: - System Bubble

    private var systemBubble: some View {
        HStack {
            Spacer()
            Text(message.content)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.vertical, Spacing.xs)
    }

    // MARK: - Streaming Indicator

    private var streamingIndicator: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(CiderColors.tertiary)
                    .frame(width: 4, height: 4)
                    .opacity(0.6)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}
