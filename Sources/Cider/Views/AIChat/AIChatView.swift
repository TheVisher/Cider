import SwiftUI

struct AIChatView: View {
    @ObservedObject var viewModel: AIChatViewModel
    let isDocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputText = ""

    var body: some View {
        ZStack(alignment: .leading) {
            // Main chat area
            VStack(spacing: 0) {
                headerBar

                Divider()
                    .padding(.horizontal, Spacing.md + Spacing.xxs)

                messageList

                bottomBar
            }

            // Conversation sidebar overlay
            if viewModel.isSidebarOpen {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(reduceMotion ? .none : .snappy) {
                            viewModel.isSidebarOpen = false
                        }
                    }
                    .transition(.opacity)

                AIChatConversationSidebar(viewModel: viewModel)
                    .transition(.move(edge: .leading))
            }
        }
        .background {
            if !isDocked {
                AcrylicPanelBackground(cornerRadius: AIChatPanelDesign.cornerRadius)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: isDocked ? 0 : AIChatPanelDesign.cornerRadius, style: .continuous))
    }

    private var currentConversationTitle: String {
        if let id = viewModel.currentConversationID,
           let conversation = viewModel.conversations.first(where: { $0.id == id }) {
            return conversation.title
        }
        return "New Chat"
    }

    // MARK: - Header (minimal)

    private var headerBar: some View {
        HStack(spacing: Spacing.sm) {
            // Close button — only in floating mode
            if !isDocked {
                Button {
                    NotificationCenter.default.post(name: .dismissAIChatPanel, object: nil)
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.microBold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(
                            width: CiderPanelDesign.trafficLightTapTarget,
                            height: CiderPanelDesign.trafficLightTapTarget
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
            }

            // Sidebar toggle
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    viewModel.toggleSidebar()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(CiderFont.body)
                    .foregroundColor(viewModel.isSidebarOpen ? CiderColors.controlAccent : CiderColors.secondary)
                    .frame(
                        width: CiderPanelDesign.trafficLightTapTarget,
                        height: CiderPanelDesign.trafficLightTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Toggle conversations")

            Text(currentConversationTitle)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer()

            // Dock / Undock toggle
            Button {
                if isDocked {
                    NotificationCenter.default.post(name: .undockAIChat, object: nil)
                } else {
                    NotificationCenter.default.post(name: .dockAIChat, object: nil)
                }
            } label: {
                Image(systemName: isDocked ? "arrow.up.forward.square" : "arrow.down.backward.square")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .frame(
                        width: CiderPanelDesign.trafficLightTapTarget,
                        height: CiderPanelDesign.trafficLightTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isDocked ? "Pop out to floating panel" : "Dock into Cider panel")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AIChatPanelDesign.titleBarHeight)
    }

    // MARK: - Bottom Bar (model pills + input)

    private var bottomBar: some View {
        VStack(spacing: Spacing.sm) {
            // Model selector pills — left-anchored
            HStack(spacing: Spacing.xs) {
                ForEach(AIModelOption.aiModels) { model in
                    modelPill(model)
                }

                // Chevron to reveal Shell
                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        viewModel.toggleShellExpanded()
                    }
                } label: {
                    Image(systemName: viewModel.isShellExpanded ? "chevron.left" : "chevron.right")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(viewModel.isShellExpanded ? "Hide Shell" : "Show Shell")

                if viewModel.isShellExpanded {
                    modelPill(AIModelOption.shell)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.md)

            // Input field with new chat + clear inside
            AIChatInputView(
                text: $inputText,
                isEnabled: true,
                onSend: {
                    viewModel.sendMessage(inputText)
                    inputText = ""
                },
                onNewChat: {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        viewModel.newConversation()
                    }
                },
                onClear: {
                    viewModel.restart()
                }
            )
            .padding(.horizontal, Spacing.md)
        }
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Model Pill

    private func modelPill(_ model: AIModelOption) -> some View {
        let isSelected = viewModel.selectedModel.id == model.id
        let isInstalled = model.id == "shell" || viewModel.isModelInstalled(model)

        return Button {
            withAnimation(reduceMotion ? .none : .snappy) {
                viewModel.selectModel(model)
            }
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: model.icon)
                    .font(CiderFont.captionMedium)
                Text(model.name)
                    .font(CiderFont.captionMedium)
                if !isInstalled {
                    Circle()
                        .fill(CiderColors.tertiary.opacity(0.5))
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundColor(isSelected ? CiderColors.controlAccent : (isInstalled ? CiderColors.secondary : CiderColors.tertiary))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? CiderColors.accentSubtle : CiderColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .stroke(isSelected ? CiderColors.accentBorder : CiderColors.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(model.id == "shell" ? "Plain shell" : (isInstalled ? "Launch \(model.name)" : "\(model.name) — not installed"))
    }

    // MARK: - Message List

    /// Content fingerprint that changes when we should auto-scroll (new messages or streaming updates).
    private var scrollTrigger: String {
        let lastMessage = viewModel.messages.last
        let contentLen = lastMessage?.content.count ?? 0
        return "\(viewModel.messages.count)-\(contentLen)"
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: Spacing.sm) {
                    ForEach(viewModel.messages) { message in
                        AIChatBubbleView(message: message)
                            .id(message.id)
                    }
                    // Invisible anchor at the very bottom
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(Spacing.md)
            }
            .defaultScrollAnchor(.bottom)
            .onAppear {
                // Delay to let layout complete before scrolling
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.currentConversationID) { _, _ in
                // Scroll to bottom when switching conversations
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: scrollTrigger) { _, _ in
                withAnimation(reduceMotion ? .none : .snappy) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
