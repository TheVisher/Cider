import SwiftUI

/// Root view for the AI Assistant floating panel.
struct AIAssistantPanelView: View {
    @ObservedObject var viewModel: AIAssistantViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AcrylicPanelBackground(
                cornerRadius: AIAssistantPanelDesign.cornerRadius
            )

            VStack(spacing: 0) {
                titleBar
                Divider().background(CiderColors.separator)
                messageList
                Divider().background(CiderColors.separator)
                AIAssistantInputView(
                    isStreaming: viewModel.isStreaming,
                    onSend: { viewModel.send($0) },
                    onStop: { viewModel.stopStreaming() }
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: AIAssistantPanelDesign.cornerRadius, style: .continuous))
        }
        .overlay {
            PanelEdgeResizeView(horizontalResizeEnabled: true)
        }
        .background {
            Button("") {
                NotificationCenter.default.post(name: .dismissAIAssistantPanel, object: nil)
            }
            .keyboardShortcut(.escape, modifiers: [])
            .hidden()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                NotificationCenter.default.post(name: .dismissAIAssistantPanel, object: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
            }
            .buttonStyle(.plain)
            .help("Close")

            Image(systemName: "sparkles")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)

            Text("AI Assistant")
                .font(CiderFont.navTitle)
                .foregroundColor(CiderColors.primary)

            if !viewModel.context.isEmpty {
                contextBadge
            }

            Spacer()

            if !viewModel.messages.isEmpty {
                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        viewModel.clearConversation()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear conversation")
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AIAssistantPanelDesign.titleBarHeight)
    }

    private var contextBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "link")
                .font(.system(size: 9))
            Text("Context")
                .font(CiderFont.captionMedium)
        }
        .foregroundColor(CiderColors.controlAccent)
        .padding(.horizontal, Spacing.xs)
        .padding(.vertical, Spacing.xxs)
        .background(
            Capsule(style: .continuous)
                .fill(CiderColors.accentSubtle)
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty && !viewModel.isStreaming {
                    emptyState
                } else {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(viewModel.messages) { message in
                            AIAssistantBubbleView(message: message)
                                .id(message.id)
                        }

                        if viewModel.isStreaming {
                            AIAssistantBubbleView(
                                message: AIAssistantMessage(
                                    role: .assistant,
                                    content: viewModel.displayedStreamingText.isEmpty
                                        ? "…" : viewModel.displayedStreamingText
                                ),
                                isStreaming: true
                            )
                            .id("streaming")
                        }

                        // Invisible anchor at the very bottom
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(Spacing.md)
                }
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.displayedStreamingText) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(CiderColors.quaternary)

            Text("Ask me anything")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)

            if viewModel.isAvailable {
                Text("Powered by \(viewModel.providerName)")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
            } else {
                Text("Apple Intelligence is not available on this device")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.destructive)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? .none : .snappy) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}
