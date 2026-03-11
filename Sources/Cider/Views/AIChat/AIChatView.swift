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
                ForEach(AIModelOption.builtIn) { model in
                    modelPill(model)
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
            }
            .foregroundColor(isSelected ? CiderColors.controlAccent : CiderColors.secondary)
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
        .help(model.id == "shell" ? "Plain shell" : "Launch \(model.name)")
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.sm) {
                    ForEach(viewModel.messages) { message in
                        AIChatBubbleView(message: message)
                            .id(message.id)
                    }
                }
                .padding(Spacing.md)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastID = viewModel.messages.last?.id {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
