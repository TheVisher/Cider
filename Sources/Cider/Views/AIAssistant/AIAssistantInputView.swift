import SwiftUI
import AppKit

private enum AIAssistantInputMetrics {
    static let minEditorHeight: CGFloat = 20
    static let maxEditorHeight: CGFloat = 208
}

/// Text input area for the AI assistant chat.
struct AIAssistantInputView: View {
    let isStreaming: Bool
    let agentTitle: String
    let runtimeTitle: String
    let runtimeColor: Color
    let onSend: (String) -> Void
    let onStop: () -> Void
    let onFloat: (() -> Void)?
    let onOpenDrawer: () -> Void
    let agentPickerContent: AnyView

    @Binding var showAgentPicker: Bool
    @State private var inputText = ""
    @State private var editorHeight: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            ZStack(alignment: .topLeading) {
                AIAssistantPromptEditor(
                    text: $inputText,
                    measuredHeight: $editorHeight,
                    onSend: sendMessage
                )
                .frame(height: min(
                    max(editorHeight, AIAssistantInputMetrics.minEditorHeight),
                    AIAssistantInputMetrics.maxEditorHeight
                ))
                .layoutPriority(1)
                .clipped()

                if inputText.isEmpty {
                    Text("Ask anything...")
                        .font(CiderFont.label)
                        .foregroundColor(CiderColors.tertiary)
                        .allowsHitTesting(false)
                }
            }

            HStack(alignment: .center, spacing: Spacing.sm) {
                Button {
                    NotificationCenter.default.post(name: .focusAIAssistantComposer, object: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Add context or attachment")

                Button {
                    inputText = inputText.isEmpty ? "/" : inputText + " /"
                    NotificationCenter.default.post(name: .focusAIAssistantComposer, object: nil)
                } label: {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(CiderFont.caption)
                        Text("Full access")
                            .font(CiderFont.captionMedium)
                        Image(systemName: "chevron.down")
                            .font(CiderFont.micro)
                    }
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(height: DetailToolbarDesign.iconButtonSize)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Agent access")

                Spacer(minLength: Spacing.md)

                agentSwitcher

                if let onFloat {
                    Button {
                        onFloat()
                    } label: {
                        Image(systemName: "rectangle.on.rectangle")
                            .font(CiderFont.bodyMedium)
                            .foregroundColor(CiderColors.secondary)
                            .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Pop out chat")
                }

                Button {
                    onOpenDrawer()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Chat details")

                Button {} label: {
                    Image(systemName: "mic")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.quaternary)
                        .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Speech to text coming later")

                trailingAction
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .padding(.bottom, Spacing.xs)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(CiderColors.opaqueBackground.opacity(0.32))
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(CiderColors.surfaceInput)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(CiderColors.borderDefault, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
    }

    private var agentSwitcher: some View {
        Button {
            showAgentPicker.toggle()
        } label: {
            HStack(spacing: Spacing.xxs) {
                Circle()
                    .fill(runtimeColor)
                    .frame(width: 6, height: 6)
                Text(agentTitle)
                    .font(CiderFont.captionMedium)
                    .lineLimit(1)
                if runtimeTitle != agentTitle {
                    Text(runtimeTitle)
                        .font(CiderFont.micro)
                        .foregroundColor(CiderColors.quaternary)
                        .lineLimit(1)
                }
            }
            .foregroundColor(CiderColors.tertiary)
            .frame(height: DetailToolbarDesign.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showAgentPicker, arrowEdge: .bottom) {
            agentPickerContent
        }
        .help("Switch AI agent")
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isStreaming {
            Button {
                onStop()
            } label: {
                Image(systemName: "stop.circle.fill")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.destructive)
                    .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Stop generating")
        } else if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Button {} label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.quaternary)
                    .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(true)
            .help("Send message")
        } else {
            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Send message")
        }
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        inputText = ""
    }
}

private extension Notification.Name {
    static let focusAIAssistantComposer = Notification.Name("focusAIAssistantComposer")
}

private struct AIAssistantPromptEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    let onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.scrollerStyle = .overlay

        let textView = ChatPromptTextView()
        textView.delegate = context.coordinator
        textView.onSend = onSend
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: max(scrollView.contentSize.width, 1),
            height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.scheduleHeightUpdate()

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.focusComposer),
            name: .focusAIAssistantComposer,
            object: nil
        )

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ChatPromptTextView else { return }
        textView.onSend = onSend
        if textView.string != text {
            textView.string = text
        }
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.scheduleHeightUpdate()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, measuredHeight: $measuredHeight)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        @Binding private var measuredHeight: CGFloat
        weak var textView: ChatPromptTextView?
        weak var scrollView: NSScrollView?
        private var isHeightUpdateScheduled = false

        init(text: Binding<String>, measuredHeight: Binding<CGFloat>) {
            _text = text
            _measuredHeight = measuredHeight
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            updateHeight()
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        @objc func focusComposer() {
            textView?.window?.makeFirstResponder(textView)
        }

        func updateHeight() {
            guard let textView else { return }
            let rawHeight = ceil(measuredTextHeight(for: textView))
            let nextHeight = min(
                max(rawHeight, AIAssistantInputMetrics.minEditorHeight),
                AIAssistantInputMetrics.maxEditorHeight
            )
            updateTextContainer(for: textView, rawHeight: rawHeight, visibleHeight: nextHeight)
            if abs(measuredHeight - nextHeight) > 0.5 {
                measuredHeight = nextHeight
            }
        }

        func scheduleHeightUpdate() {
            guard !isHeightUpdateScheduled else { return }
            isHeightUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isHeightUpdateScheduled = false
                self.updateHeight()
            }
        }

        private func updateTextContainer(
            for textView: NSTextView,
            rawHeight: CGFloat,
            visibleHeight: CGFloat
        ) {
            let width = measuredTextWidth(for: textView)
            textView.textContainer?.containerSize = NSSize(
                width: width,
                height: CGFloat.greatestFiniteMagnitude
            )

            let documentHeight = max(rawHeight, visibleHeight)
            let nextSize = NSSize(width: width, height: documentHeight)
            if abs(textView.frame.width - nextSize.width) > 0.5
                || abs(textView.frame.height - nextSize.height) > 0.5 {
                textView.setFrameSize(nextSize)
            }

            scrollView?.hasVerticalScroller = rawHeight > AIAssistantInputMetrics.maxEditorHeight
        }

        private func measuredTextHeight(for textView: NSTextView) -> CGFloat {
            let font = textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let content = textView.string.isEmpty ? " " : textView.string
            let width = measuredTextWidth(for: textView)
            let attributed = NSAttributedString(
                string: content,
                attributes: [.font: font]
            )
            let rect = attributed.boundingRect(
                with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return rect.height + 2
        }

        private func measuredTextWidth(for textView: NSTextView) -> CGFloat {
            if let scrollView, scrollView.contentSize.width > 1 {
                return scrollView.contentSize.width
            }
            if textView.bounds.width > 1 {
                return textView.bounds.width
            }
            if let container = textView.textContainer,
               container.containerSize.width.isFinite,
               container.containerSize.width > 1 {
                return container.containerSize.width
            }
            return 640
        }
    }
}

private final class ChatPromptTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if isReturn, modifiers.contains(.shift) {
            insertNewline(nil)
            return
        }

        if isReturn, modifiers.isDisjoint(with: [.shift, .option, .command, .control]) {
            onSend?()
            return
        }

        super.keyDown(with: event)
    }
}
