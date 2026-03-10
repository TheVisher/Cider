import SwiftUI

struct AIChatView: View {
    @ObservedObject var viewModel: AIChatViewModel
    let isDocked: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()
                .padding(.horizontal, Spacing.md + Spacing.xxs)

            // Messages
            messageList

            // Input
            AIChatInputView(
                text: $inputText,
                isEnabled: viewModel.isProcessRunning
            ) {
                viewModel.sendMessage(inputText)
                inputText = ""
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
        .background {
            if !isDocked {
                AcrylicPanelBackground(cornerRadius: AIChatPanelDesign.cornerRadius)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
                .padding(.horizontal, Spacing.md + Spacing.xxs)
            modelSelector
        }
    }

    private var titleBar: some View {
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

            Image(systemName: "sparkles")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)

            Text("AI Chat")
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)

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

            // Restart
            Button {
                viewModel.restart()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .frame(
                        width: CiderPanelDesign.trafficLightTapTarget,
                        height: CiderPanelDesign.trafficLightTapTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Restart session")
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: AIChatPanelDesign.titleBarHeight)
    }

    // MARK: - Model Selector

    private var modelSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(AIModelOption.builtIn) { model in
                    modelPill(model)
                }
            }
            .padding(.horizontal, Spacing.md)
        }
        .frame(height: AIChatPanelDesign.modelSelectorHeight)
        .padding(.vertical, Spacing.xs)
    }

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
                // Scroll to latest message
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
