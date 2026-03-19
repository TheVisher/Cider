import SwiftUI

/// A single message bubble in the AI chat.
struct AIAssistantBubbleView: View {
    let message: AIAssistantMessage
    var isStreaming = false

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            if message.role == .user {
                Spacer(minLength: Spacing.xxxl)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
                Text(message.content)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if isStreaming {
                    BouncingDotsView()
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            if message.role == .assistant {
                Spacer(minLength: Spacing.xxxl)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                CiderColors.accentSubtle
            } else {
                CiderColors.surfaceElevated
            }
        }
    }
}

// MARK: - Bouncing Dots

/// Three dots that bounce at staggered intervals.
struct BouncingDotsView: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(CiderColors.tertiary)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -4 : 0)
                    .animation(
                        reduceMotion ? .none :
                            .spring(duration: 0.4, bounce: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.top, Spacing.xxs)
        .onAppear { animating = true }
    }
}
