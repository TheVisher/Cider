import AppKit
import SwiftUI
import os.log

enum AIAssistantPresentationStyle {
    case floatingPanel
    case embedded
    case floatingSurface
}

/// Root view for the AI Assistant floating panel.
struct AIAssistantPanelView: View {
    @ObservedObject var viewModel: AIAssistantViewModel
    var onClose: (() -> Void)?
    var onFloat: (() -> Void)?
    var showsResizeOverlay = true
    var presentationStyle: AIAssistantPresentationStyle = .floatingPanel

    @ObservedObject private var conversationStorage = AIConversationStorage.shared
    @ObservedObject private var modelManager = MLXModelManager.shared
    @State private var showConversationList = false
    @State private var showModelPicker = false
    @State private var visibleMessageLimit = 12
    @State private var composerHeight: CGFloat = 64
    @State private var showStreamingIndicator = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let hermesSyncTimer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()
    private static let renderLogger = Logger(subsystem: "com.cider.app", category: "AIAssistantRender")

    var body: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                titleBar
                messageList
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

            if showConversationList, usesCenteredChatLayout {
                chatDrawerOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            if showsResizeOverlay, presentationStyle == .floatingPanel {
                PanelEdgeResizeView(horizontalResizeEnabled: true)
            }
        }
        .background {
            Button("") {
                close()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .hidden()
        }
        .onAppear {
            if viewModel.runtimeSelection == .hermes, viewModel.messages.isEmpty {
                viewModel.syncHermesConversation()
            }
        }
        .onReceive(hermesSyncTimer) { _ in
            if viewModel.runtimeSelection == .hermes {
                viewModel.syncHermesConversation()
            }
        }
        .onChange(of: viewModel.currentConversationID) { _, _ in
            visibleMessageLimit = 12
        }
        .onChange(of: viewModel.isStreaming) { _, isStreaming in
            if isStreaming {
                showStreamingIndicator = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    if viewModel.isStreaming {
                        showStreamingIndicator = true
                        viewModel.requestScrollToBottom()
                    }
                }
            } else {
                showStreamingIndicator = false
            }
        }
        .animation(reduceMotion ? .none : .snappy, value: showConversationList)
    }

    @ViewBuilder
    private var backgroundLayer: some View {
        switch presentationStyle {
        case .floatingPanel:
            AcrylicPanelBackground(cornerRadius: AIAssistantPanelDesign.cornerRadius)
        case .embedded:
            CiderColors.opaqueBackground.opacity(0.001)
        case .floatingSurface:
            AcrylicPanelBackground(cornerRadius: AIAssistantPanelDesign.cornerRadius)
        }
    }

    private var cornerRadius: CGFloat {
        switch presentationStyle {
        case .floatingPanel, .floatingSurface:
            AIAssistantPanelDesign.cornerRadius
        case .embedded:
            0
        }
    }

    private var inputBarMaxWidth: CGFloat {
        usesCenteredChatLayout ? 800 : .infinity
    }

    private var usesCenteredChatLayout: Bool {
        presentationStyle == .embedded || presentationStyle == .floatingSurface
    }

    // MARK: - Title Bar

    @ViewBuilder
    private var titleBar: some View {
        switch presentationStyle {
        case .embedded:
            EmptyView()
        case .floatingSurface:
            floatingSurfaceTitleBar
        case .floatingPanel:
            floatingTitleBar
        }
    }

    private var floatingSurfaceTitleBar: some View {
        HStack(alignment: .top, spacing: CiderPanelDesign.trafficLightSpacing) {
            PanelTrafficLightButton(color: .systemRed, symbol: "xmark", help: "Close chat", action: close)
            PanelTrafficLightButton(color: .systemYellow, symbol: "minus", help: "Hide chat", action: close)
            PanelTrafficLightButton(color: .systemGreen, symbol: "plus", help: "Zoom", action: zoomWindow)

            Spacer()
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
        .frame(height: AIAssistantPanelDesign.titleBarHeight)
    }

    private var floatingTitleBar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                close()
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

            Text(titleText)
                .font(CiderFont.navTitle)
                .foregroundColor(CiderColors.primary)

            if !viewModel.context.isEmpty {
                contextBadge
            }

            Button {
                showModelPicker.toggle()
            } label: {
                HStack(spacing: Spacing.xxs) {
                    Circle()
                        .fill(runtimePillColor)
                        .frame(width: 6, height: 6)
                    Text(runtimePillTitle)
                        .font(CiderFont.captionMedium)
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

            if viewModel.contextUsage > 0.1 {
                contextUsageIndicator
            }

            if viewModel.runtimeSelection == .hermes {
                hermesStatusControl
            }

            if let onFloat {
                Button {
                    onFloat()
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                }
                .buttonStyle(.plain)
                .help("Pop out")
            }

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

    private var titleText: String {
        switch presentationStyle {
        case .embedded, .floatingSurface:
            return viewModel.currentChatTitle
        case .floatingPanel:
            return runtimePillTitle
        }
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            NotificationCenter.default.post(name: .dismissAIAssistantPanel, object: nil)
        }
    }

    private func minimizeWindow() {
        NSApp.keyWindow?.miniaturize(nil)
    }

    private func zoomWindow() {
        NSApp.keyWindow?.zoom(nil)
    }

    private var chatDrawerOverlay: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        showConversationList = false
                    }
                }

            chatDrawer
                .frame(width: 320)
                .frame(maxHeight: .infinity)
                .background(
                    ZStack {
                        VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                        CiderColors.surfaceSubtle.opacity(0.92)
                    }
                )
                .overlay(alignment: .leading) {
                    CiderColors.separator
                        .frame(width: Spacing.hairline)
                }
                .shadow(color: .black.opacity(0.22), radius: 22, x: -8, y: 0)
        }
    }

    private var chatDrawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Chat")
                        .font(CiderFont.navTitle)
                        .foregroundColor(CiderColors.primary)
                    Text(titleText)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }

                Spacer()

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        showConversationList = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                }
                .buttonStyle(.plain)
                .help("Close chat details")
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.top, Spacing.lg)
            .padding(.bottom, Spacing.sm)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    drawerCurrentSection
                    drawerActionsSection
                    drawerHistorySection
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private var drawerCurrentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            drawerSectionTitle("Current")

            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack(spacing: Spacing.xs) {
                    Circle()
                        .fill(runtimePillColor)
                        .frame(width: 7, height: 7)
                    Text(titleText)
                        .font(CiderFont.labelMedium)
                        .foregroundColor(CiderColors.primary)
                    Text(runtimePillTitle)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                    Spacer()
                }

                if viewModel.runtimeSelection == .hermes {
                    Button {
                        performHermesStatusAction()
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: hermesSyncIcon)
                                .font(CiderFont.caption)
                            Text(viewModel.hermesStatusTitle)
                                .font(CiderFont.captionMedium)
                                .lineLimit(1)
                            Spacer()
                            Text(viewModel.hermesSessionLabel)
                                .font(CiderFont.microMonospaced)
                                .foregroundColor(CiderColors.quaternary)
                        }
                        .foregroundColor(hermesStatusColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isStreaming)
                }

                HStack(spacing: Spacing.xs) {
                    Text("\(viewModel.messages.count) messages")
                        .font(CiderFont.caption)
                    Spacer()
                    if let id = viewModel.currentConversationID {
                        Text(String(id.uuidString.prefix(8)))
                            .font(CiderFont.microMonospaced)
                    } else {
                        Text("unsaved")
                            .font(CiderFont.microMonospaced)
                    }
                }
                .foregroundColor(CiderColors.tertiary)
            }
            .padding(Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
        }
    }

    private var drawerActionsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            drawerSectionTitle("Actions")

            drawerActionButton(title: "New chat", systemImage: "square.and.pencil") {
                withAnimation(reduceMotion ? .none : .snappy) {
                    viewModel.newConversation()
                    visibleMessageLimit = 12
                    showConversationList = false
                }
            }

            if let onFloat {
                drawerActionButton(title: presentationStyle == .floatingSurface ? "Dock chat" : "Pop out chat", systemImage: "rectangle.on.rectangle") {
                    showConversationList = false
                    onFloat()
                }
            }

            if viewModel.runtimeSelection == .hermes {
                drawerActionButton(title: "New Hermes chat", systemImage: "bubble.left.and.text.bubble.right") {
                    promptForNewHermesChat()
                    visibleMessageLimit = 12
                    showConversationList = false
                }

                drawerActionButton(title: "Attach latest Telegram", systemImage: "link") {
                    viewModel.attachLatestHermesTelegramSession()
                    showConversationList = false
                }

                drawerActionButton(title: "Choose existing session", systemImage: "text.cursor") {
                    promptForHermesSession()
                    showConversationList = false
                }

                drawerActionButton(title: "Start fresh Hermes session", systemImage: "plus.message") {
                    viewModel.startFreshHermesSession()
                    visibleMessageLimit = 12
                    showConversationList = false
                }

                drawerActionButton(title: "Relink session", systemImage: "arrow.triangle.2.circlepath") {
                    viewModel.relinkMainBrainToActiveHermesSession()
                    showConversationList = false
                }

                drawerActionButton(title: "Sync now", systemImage: hermesSyncIcon) {
                    viewModel.syncHermesConversation()
                    showConversationList = false
                }

                if viewModel.hermesConversationState != nil {
                    drawerActionButton(title: "Copy Telegram resume command", systemImage: "doc.on.doc") {
                        viewModel.copyTelegramResumeCommandForCurrentHermesChat()
                        showConversationList = false
                    }
                }

                if isHermesIssueVisible {
                    drawerActionButton(title: "Clear Hermes error", systemImage: "xmark.circle") {
                        viewModel.clearHermesError()
                        showConversationList = false
                    }
                }
            }

            if !viewModel.messages.isEmpty {
                drawerActionButton(title: "Clear current chat", systemImage: "trash", role: .destructive) {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        viewModel.clearConversation()
                        visibleMessageLimit = 12
                        showConversationList = false
                    }
                }
            }
        }
    }

    private var drawerHistorySection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                drawerSectionTitle("Chats")
                Spacer()
                Text("\(drawerChatCount)")
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.tertiary)
            }

            if drawerChatCount == 0 {
                Text("No saved chats yet")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.vertical, Spacing.xs)
            } else {
                LazyVStack(spacing: Spacing.xxs) {
                    if viewModel.runtimeSelection == .hermes {
                        ForEach(viewModel.hermesChats, id: \.stableID) { chat in
                            hermesChatRow(chat)
                        }
                    } else {
                        ForEach(conversationStorage.conversations) { conv in
                            conversationRow(conv)
                        }
                    }
                }
            }
        }
    }

    private var drawerChatCount: Int {
        viewModel.runtimeSelection == .hermes
            ? viewModel.hermesChats.count
            : conversationStorage.conversations.count
    }

    private func drawerSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(CiderFont.captionSemibold)
            .foregroundColor(CiderColors.tertiary)
            .textCase(.uppercase)
    }

    private func drawerActionButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: systemImage)
                    .font(CiderFont.caption)
                    .frame(width: 14)
                Text(title)
                    .font(CiderFont.label)
                Spacer()
            }
            .foregroundColor(role == .destructive ? CiderColors.destructive : CiderColors.primary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
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
                .font(CiderFont.microMonospaced)
                .foregroundColor(color)
        }
        .help("Context window usage — \(Int(usage * 100))% of \(4096) tokens. Clears automatically when full.")
    }

    private var contextBadge: some View {
        HStack(spacing: Spacing.xxs) {
            Image(systemName: "link")
                .font(CiderFont.micro)
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

    private var hermesStatusControl: some View {
        Button {
            performHermesStatusAction()
        } label: {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: hermesSyncIcon)
                    .font(CiderFont.caption)
                Text(viewModel.hermesStatusTitle)
                    .font(CiderFont.caption)
                    .lineLimit(1)
                Text(viewModel.hermesSessionLabel)
                    .font(CiderFont.microMonospaced)
                    .foregroundColor(CiderColors.quaternary)
            }
            .foregroundColor(hermesStatusColor)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStreaming)
        .help(viewModel.hermesConversationState == nil ? "Attach latest Hermes session" : "Sync Hermes session")
    }

    private var isHermesIssueVisible: Bool {
        switch viewModel.hermesSyncStatus {
        case .error, .staleSession, .disconnected:
            return true
        default:
            return false
        }
    }

    private func performHermesStatusAction() {
        if viewModel.hermesConversationState == nil {
            viewModel.attachLatestHermesTelegramSession()
        } else {
            viewModel.syncHermesConversation()
        }
    }

    private func promptForHermesSession() {
        let alert = NSAlert()
        alert.messageText = "Choose Hermes Session"
        alert.informativeText = "Paste an existing Hermes session ID."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Attach")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "20260501_120144_e3d994"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let sessionID = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionID.isEmpty else { return }
        viewModel.attachHermesSession(id: sessionID)
    }

    private func promptForNewHermesChat() {
        let alert = NSAlert()
        alert.messageText = "New Hermes Chat"
        alert.informativeText = "Name this Cider/Hermes chat. Telegram can resume it later by this title."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.placeholderString = "Cider Dashboard Worktree"
        alert.accessoryView = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        viewModel.createNamedHermesChat(title: title, scope: "cider")
    }

    // MARK: - Message List

    private var messageList: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let columnWidth = messageColumnWidth(for: width)

            ScrollViewReader { proxy in
                ScrollView {
                    if viewModel.messages.isEmpty && !viewModel.isStreaming {
                        emptyState
                    } else {
                        LazyVStack(spacing: Spacing.lg) {
                            if hiddenMessageCount > 0 {
                                loadEarlierButton
                            }

                            ForEach(visibleMessages) { message in
                                AIAssistantBubbleView(
                                    message: message,
                                    presentationStyle: presentationStyle,
                                    maxBubbleWidth: maxBubbleWidth(for: message, contentWidth: columnWidth)
                                )
                                .id(AIAssistantRenderInvalidation.messageKey(message))
                                .id(message.id)
                            }

                            if modelManager.isDownloading || modelManager.isLoading {
                                modelLoadingView
                                    .id("loading")
                            } else if viewModel.isStreaming && showStreamingIndicator && !viewModel.hasLiveHermesResponseForActiveSend {
                                AIAssistantBubbleView(
                                    message: AIAssistantMessage(
                                        role: .assistant,
                                        content: viewModel.displayedStreamingText.isEmpty
                                            ? streamingWaitingText : viewModel.displayedStreamingText
                                    ),
                                    presentationStyle: presentationStyle,
                                    maxBubbleWidth: maxBubbleWidth(
                                        for: AIAssistantMessage(role: .assistant, content: ""),
                                        contentWidth: columnWidth
                                    ),
                                    isStreaming: true
                                )
                                .id("streaming")
                            }

                            // Keep the scroll target at the true bottom, including space for the floating composer.
                            Color.clear
                                .frame(height: composerHeight + Spacing.xl)
                                .id("bottom")
                        }
                        .id(listLayoutKey(for: width))
                        .frame(width: columnWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, Spacing.lg)
                    }
                }
                .defaultScrollAnchor(.bottom)
                .overlay(alignment: .bottom) {
                    floatingComposer
                        .frame(maxWidth: inputBarMaxWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, usesCenteredChatLayout ? Spacing.xxl : Spacing.md)
                        .padding(.bottom, usesCenteredChatLayout ? Spacing.lg : Spacing.sm)
                        .padding(.top, Spacing.sm)
                        .background(
                            LinearGradient(
                                colors: [
                                    CiderColors.opaqueBackground.opacity(0),
                                    CiderColors.opaqueBackground.opacity(0.72)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .allowsHitTesting(false)
                        )
                        .readHeight { setComposerHeight($0) }
                }
                .onChange(of: viewModel.isStreaming) { _, isStreaming in
                    Self.renderLogger.debug("streaming changed isStreaming=\(isStreaming) messages=\(viewModel.messages.count) visible=\(visibleMessages.count)")
                    if isStreaming {
                        scrollToBottomBurst(proxy: proxy, animated: false)
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    Self.renderLogger.debug("message count changed total=\(viewModel.messages.count) visible=\(visibleMessages.count) hidden=\(hiddenMessageCount)")
                    scrollToBottomBurst(proxy: proxy)
                }
                .onChange(of: viewModel.displayedStreamingText) { _, _ in
                    scrollToBottom(proxy: proxy, delay: 0.05)
                }
                .onChange(of: viewModel.scrollToBottomSignal) { _, _ in
                    Self.renderLogger.debug("scroll-to-bottom signal total=\(viewModel.messages.count) visible=\(visibleMessages.count)")
                    scrollToBottomBurst(proxy: proxy, animated: false)
                }
                .onChange(of: showStreamingIndicator) { _, isVisible in
                    if isVisible {
                        scrollToBottomBurst(proxy: proxy, animated: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var streamingWaitingText: String {
        "\(runtimePillTitle) is working"
    }

    private var floatingComposer: some View {
        AIAssistantInputView(
            isStreaming: viewModel.isStreaming,
            agentTitle: runtimePillTitle,
            runtimeTitle: runtimePillTitle,
            runtimeColor: runtimePillColor,
            onSend: { viewModel.send($0) },
            onStop: { viewModel.stopStreaming() },
            onFloat: usesCenteredChatLayout ? onFloat : nil,
            onOpenDrawer: {
                withAnimation(reduceMotion ? .none : .snappy) {
                    showConversationList.toggle()
                }
            },
            agentPickerContent: AnyView(modelPickerPopover),
            showAgentPicker: $showModelPicker
        )
    }

    private func messageColumnWidth(for width: CGFloat) -> CGFloat {
        let sidePadding = usesCenteredChatLayout ? Spacing.xl : Spacing.md
        let availableWidth = max(width - (sidePadding * 2), 1)
        guard usesCenteredChatLayout else { return availableWidth }
        return min(availableWidth, 800)
    }

    private func maxBubbleWidth(for message: AIAssistantMessage, contentWidth: CGFloat) -> CGFloat {
        guard usesCenteredChatLayout else { return contentWidth * 0.92 }
        let ratio: CGFloat = message.role == .user ? 0.72 : 0.86
        return min(contentWidth * ratio, message.role == .user ? 560 : 680)
    }

    private func listLayoutKey(for width: CGFloat) -> String {
        AIAssistantRenderInvalidation.listLayoutKey(
            messages: visibleMessages,
            width: width
        )
    }

    private var visibleMessages: [AIAssistantMessage] {
        Array(viewModel.messages.suffix(visibleMessageLimit))
    }

    private var hiddenMessageCount: Int {
        max(viewModel.messages.count - visibleMessageLimit, 0)
    }

    private var loadEarlierButton: some View {
        Button {
            visibleMessageLimit += 12
            Self.renderLogger.info("load earlier messages total=\(viewModel.messages.count) visibleLimit=\(visibleMessageLimit) hidden=\(hiddenMessageCount)")
        } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Load earlier messages")
                Text("\(hiddenMessageCount)")
                    .font(CiderFont.captionMonospacedMedium)
                    .foregroundColor(CiderColors.tertiary)
            }
            .font(CiderFont.captionMedium)
            .foregroundColor(CiderColors.secondary)
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule(style: .continuous)
                    .fill(CiderColors.surfaceInput)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: "sparkles")
.font(CiderFont.settingsEmptyIcon)
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

    private func setComposerHeight(_ height: CGFloat) {
        guard abs(composerHeight - height) > 0.5 else { return }
        DispatchQueue.main.async {
            guard abs(composerHeight - height) > 0.5 else { return }
            Self.renderLogger.debug("composer height changed old=\(composerHeight) new=\(height)")
            composerHeight = height
        }
    }

    private func scrollToBottom(
        proxy: ScrollViewProxy,
        animated: Bool = true,
        delay: TimeInterval = 0
    ) {
        let action: @MainActor () -> Void = {
            if reduceMotion || !animated || viewModel.messages.count > visibleMessageLimit {
                proxy.scrollTo("bottom", anchor: .bottom)
            } else {
                withAnimation(.snappy) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        let actionBox = MainActorActionBox(action)

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated {
                    actionBox.perform()
                }
            }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    actionBox.perform()
                }
            }
        }
    }

    private func scrollToBottomBurst(proxy: ScrollViewProxy, animated: Bool = true) {
        for delay in [0, 0.04, 0.12, 0.28, 0.55] {
            scrollToBottom(proxy: proxy, animated: animated && delay == 0.12, delay: delay)
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
                            .tint(CiderColors.success)

                        Text("\(Int(modelManager.downloadProgress * 100))% — \(String(format: "%.1f", modelManager.recommendedTier.downloadSizeGB)) GB total")
                            .font(CiderFont.caption)
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
                viewModel.switchRuntime(to: .appleIntelligence)
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
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    Spacer()
                    if viewModel.runtimeSelection == .appleIntelligence {
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
                viewModel.switchRuntime(to: .localModel)
                showModelPicker = false
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "desktopcomputer")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.success)
                        .frame(width: 14, alignment: .center)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Local Model")
                            .font(CiderFont.label)
                            .foregroundColor(CiderColors.primary)
                        Text(localModelSubtitle)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    Spacer()
                    if viewModel.runtimeSelection == .localModel {
                        Image(systemName: "checkmark")
                            .font(CiderFont.captionSemibold)
                            .foregroundColor(CiderColors.success)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, Spacing.md)

            Button {
                viewModel.switchRuntime(to: .hermes)
                showModelPicker = false
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 14, alignment: .center)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Hermes")
                            .font(CiderFont.label)
                            .foregroundColor(CiderColors.primary)
                        Text(hermesSubtitle)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }
                    Spacer()
                    if viewModel.runtimeSelection == .hermes {
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

            // Download progress
            if modelManager.isDownloading {
                VStack(spacing: Spacing.xxs) {
                    ProgressView(value: modelManager.downloadProgress)
                        .tint(CiderColors.success)
                    Text("Downloading model... \(Int(modelManager.downloadProgress * 100))%")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.xs)
            }

            if let error = modelManager.loadError {
                Text(error)
                    .font(CiderFont.caption)
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

    private var hermesSubtitle: String {
        if viewModel.hermesConversationState != nil {
            return "Attached to \(viewModel.hermesSessionLabel)"
        }
        if viewModel.isAvailable {
            return "Attach latest Hermes session"
        }
        return "Hermes state not found"
    }

    private var runtimePillTitle: String {
        switch viewModel.runtimeSelection {
        case .appleIntelligence:
            return "Apple"
        case .localModel:
            return "Local"
        case .hermes:
            return "Hermes"
        }
    }

    private var runtimePillColor: Color {
        switch viewModel.runtimeSelection {
        case .appleIntelligence:
            return CiderColors.controlAccent
        case .localModel:
            return CiderColors.success
        case .hermes:
            return hermesStatusColor
        }
    }

    private var hermesStatusColor: Color {
        switch viewModel.hermesSyncStatus {
        case .idle, .syncing, .sending, .running(_, _):
            return viewModel.hermesConversationState == nil ? CiderColors.warning : CiderColors.success
        case .notAttached, .waitingForApproval(_), .staleSession(_), .disconnected(_):
            return CiderColors.warning
        case .error:
            return CiderColors.destructive
        }
    }

    private var hermesSyncIcon: String {
        switch viewModel.hermesSyncStatus {
        case .notAttached:
            return "link"
        case .idle:
            return "arrow.clockwise"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .sending:
            return "paperplane"
        case .running(_, _):
            return "play.circle"
        case .waitingForApproval(_):
            return "checkmark.seal"
        case .staleSession(_):
            return "wrench.and.screwdriver"
        case .disconnected(_):
            return "wifi.slash"
        case .error:
            return "exclamationmark.triangle"
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
            visibleMessageLimit = 12
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
                        let overwrite: CiderExportOverwriteIntent = FileManager.default.fileExists(atPath: url.path)
                            ? .replaceExisting
                            : .prohibit
                        try? CiderExportWritePolicy().writeText(md, to: url, overwrite: overwrite)
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

    private func hermesChatRow(_ chat: CiderAgentChatRecord) -> some View {
        let isActive = viewModel.currentConversationID == chat.conversationID
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let messageCount = conversationStorage
            .conversations
            .first(where: { $0.id == chat.conversationID })?
            .messageCount ?? 0

        return Button {
            viewModel.loadHermesChat(stableID: chat.stableID)
            showConversationList = false
            visibleMessageLimit = 12
        } label: {
            HStack(spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(chat.title)
                            .font(CiderFont.label)
                            .foregroundColor(isActive ? CiderColors.controlAccent : CiderColors.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if chat.defaultInCider {
                            Text("Main")
                                .font(CiderFont.micro)
                                .foregroundColor(CiderColors.tertiary)
                        }
                    }

                    HStack(spacing: Spacing.xs) {
                        Text(formatter.localizedString(for: chat.updatedAt, relativeTo: Date()))
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)

                        Text("·")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)

                        Text("\(messageCount) msgs")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)

                        if !chat.activeRuntimeSessionID.isEmpty {
                            Text(String(chat.activeRuntimeSessionID.suffix(8)))
                                .font(CiderFont.microMonospaced)
                                .foregroundColor(CiderColors.quaternary)
                        }
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
            Button("Copy Telegram Resume Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    CiderAgentChatRegistry.telegramResumeCommand(for: chat),
                    forType: .string
                )
            }
        }
    }
}

enum AIAssistantRenderInvalidation {
    static func listLayoutKey(
        messages: [AIAssistantMessage],
        width: CGFloat
    ) -> String {
        let widthBucket = Int(width / 80)
        let firstVisibleID = messages.first?.id.uuidString ?? "empty"
        let lastVisibleID = messages.last?.id.uuidString ?? "empty"
        return "\(widthBucket):\(messages.count):\(firstVisibleID):\(lastVisibleID)"
    }

    static func messageKey(_ message: AIAssistantMessage) -> String {
        [
            message.id.uuidString,
            message.role.rawValue,
            String(stableDigest(message.content)),
            message.sourceID ?? "",
            message.sourceSessionID ?? "",
            String(message.attachments.count)
        ].joined(separator: ":")
    }

    private static func stableDigest(_ value: String) -> UInt64 {
        value.utf8.reduce(14_695_981_039_346_656_037) { partial, byte in
            (partial ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

private struct HeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private final class MainActorActionBox: @unchecked Sendable {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor
    func perform() {
        action()
    }
}

private extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: HeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(HeightPreferenceKey.self, perform: onChange)
    }
}
