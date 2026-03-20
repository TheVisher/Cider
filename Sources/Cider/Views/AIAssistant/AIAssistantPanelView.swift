import SwiftUI

/// Root view for the AI Assistant floating panel.
struct AIAssistantPanelView: View {
    @ObservedObject var viewModel: AIAssistantViewModel

    @ObservedObject private var conversationStorage = AIConversationStorage.shared
    @ObservedObject private var modelManager = MLXModelManager.shared
    @State private var showConversationList = false
    @State private var showModelPicker = false
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

            // Model selector pill
            Button {
                showModelPicker.toggle()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(viewModel.isUsingLocalModel ? Color.green : CiderColors.controlAccent)
                        .frame(width: 6, height: 6)
                    Text(viewModel.isUsingLocalModel ? "Local" : "Apple")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(CiderColors.tertiary)
                }
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule(style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
            }
            .buttonStyle(.plain)
            .help("Switch AI model")
            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                modelPickerPopover
            }

            Spacer()

            // Context usage indicator
            if viewModel.contextUsage > 0.1 {
                contextUsageIndicator
            }

            // New conversation
            Button {
                withAnimation(reduceMotion ? .none : .snappy) {
                    viewModel.newConversation()
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")

            // Conversation history
            if !conversationStorage.conversations.isEmpty {
                Button {
                    showConversationList.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Conversation history")
                .popover(isPresented: $showConversationList, arrowEdge: .bottom) {
                    conversationListPopover
                }
            }

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

    private var contextUsageIndicator: some View {
        let usage = viewModel.contextUsage
        let color: Color = usage > 0.85 ? CiderColors.destructive :
                           usage > 0.6 ? CiderColors.warning : CiderColors.tertiary
        return HStack(spacing: Spacing.xxs) {
            // Thin progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(CiderColors.surfaceInput)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: geo.size.width * usage)
                }
            }
            .frame(width: 32, height: 3)

            Text("\(Int(usage * 100))%")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(color)
        }
        .help("Context window usage — \(Int(usage * 100))% of \(4096) tokens. Clears automatically when full.")
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

                        if modelManager.isDownloading || modelManager.isLoading {
                            modelLoadingView
                                .id("loading")
                        } else if viewModel.isStreaming {
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

    // MARK: - Model Loading View

    private var modelLoadingView: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.sm) {
                    ProgressView()
                        .controlSize(.small)
                    Text(modelManager.isDownloading ? "Downloading AI model..." : "Loading AI model...")
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                }

                if modelManager.isDownloading {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ProgressView(value: modelManager.downloadProgress)
                            .tint(.green)

                        Text("\(Int(modelManager.downloadProgress * 100))% — \(String(format: "%.1f", modelManager.recommendedTier.downloadSizeGB)) GB total")
                            .font(.system(size: 10))
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Text("First-time setup. The model is stored locally and works offline after this.")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(CiderColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

            Spacer(minLength: Spacing.xxxl)
        }
    }

    // MARK: - Model Picker Popover

    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("AI Model")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)

            // Apple Intelligence option
            Button {
                viewModel.switchProvider(useLocalModel: false)
                showModelPicker = false
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "apple.logo")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 14, alignment: .center)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Apple Intelligence")
                            .font(CiderFont.label)
                            .foregroundColor(CiderColors.primary)
                        Text("On-device, 4K context")
                            .font(.system(size: 10))
                            .foregroundColor(CiderColors.tertiary)
                    }
                    Spacer()
                    if !viewModel.isUsingLocalModel {
                        Image(systemName: "checkmark")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, Spacing.md)

            // Local model option
            Button {
                viewModel.switchProvider(useLocalModel: true)
                showModelPicker = false
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "desktopcomputer")
                        .font(CiderFont.caption)
                        .foregroundColor(.green)
                        .frame(width: 14, alignment: .center)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Local Model")
                            .font(CiderFont.label)
                            .foregroundColor(CiderColors.primary)
                        Text(localModelSubtitle)
                            .font(.system(size: 10))
                            .foregroundColor(CiderColors.tertiary)
                    }
                    Spacer()
                    if viewModel.isUsingLocalModel {
                        Image(systemName: "checkmark")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Download progress
            if modelManager.isDownloading {
                VStack(spacing: Spacing.xxs) {
                    ProgressView(value: modelManager.downloadProgress)
                        .tint(.green)
                    Text("Downloading model... \(Int(modelManager.downloadProgress * 100))%")
                        .font(.system(size: 10))
                        .foregroundColor(CiderColors.tertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)
            }

            if let error = modelManager.loadError {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.destructive)
                    .padding(.horizontal, Spacing.md)
                    .padding(.bottom, Spacing.xs)
            }
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 240)
    }

    private var localModelSubtitle: String {
        if modelManager.isModelLoaded {
            return "32K context, loaded"
        } else if modelManager.isLoading {
            return "Loading..."
        } else {
            let tier = modelManager.recommendedTier
            return "32K context, ~\(String(format: "%.1f", tier.downloadSizeGB)) GB download"
        }
    }

    // MARK: - Conversation List Popover

    private var conversationListPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.sm)
                .padding(.bottom, Spacing.xs)

            ScrollView {
                LazyVStack(spacing: Spacing.xxs) {
                    ForEach(conversationStorage.conversations) { conv in
                        conversationRow(conv)
                    }
                }
                .padding(.horizontal, Spacing.xs)
            }
            .frame(maxHeight: 300)
        }
        .padding(.vertical, Spacing.xs)
        .frame(width: 260)
    }

    private func conversationRow(_ conv: AIConversationSummary) -> some View {
        let isActive = viewModel.currentConversationID == conv.id
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated

        return Button {
            viewModel.loadConversation(conv.id)
            showConversationList = false
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(conv.title)
                        .font(CiderFont.label)
                        .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: Spacing.xs) {
                        Text(formatter.localizedString(for: conv.updated, relativeTo: Date()))
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)

                        Text("·")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)

                        Text("\(conv.messageCount) msgs")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isActive ? CiderColors.accentSubtle : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                if let md = AIConversationStorage.shared.exportAsMarkdown(conversationID: conv.id) {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "md")!]
                    panel.nameFieldStringValue = "\(conv.title).md"
                    if panel.runModal() == .OK, let url = panel.url {
                        try? md.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
            } label: {
                Label("Export as Markdown", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button("Delete", role: .destructive) {
                viewModel.deleteConversation(conv.id)
            }
        }
    }
}
