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
        let showThinking = message.isStreaming && (message.content.isEmpty || message.hideWhileStreaming)

        return HStack {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if showThinking {
                    ThinkingDotsView()
                } else {
                    Text(message.content)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.primary)
                        .textSelection(.enabled)

                    if message.isStreaming {
                        ThinkingDotsView()
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
}

// MARK: - Animated Thinking Dots

struct ThinkingDotsView: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(CiderColors.tertiary)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -3 : 1)
                    .animation(
                        reduceMotion ? .none :
                            .spring(response: 0.4, dampingFraction: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.vertical, Spacing.xxs)
        .onAppear {
            animating = true
        }
    }
}
