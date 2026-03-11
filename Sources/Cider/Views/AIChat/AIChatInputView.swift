import SwiftUI

struct AIChatInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: () -> Void
    var onNewChat: (() -> Void)?
    var onClear: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var textHeight: CGFloat = 20

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var clampedHeight: CGFloat {
        min(max(textHeight, 20), 100)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Spacing.sm) {
            // Plus menu (new conversation, future: attach files, etc.)
            if let onNewChat {
                Menu {
                    Button {
                        onNewChat()
                    } label: {
                        Label("New Conversation", systemImage: "square.and.pencil")
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(CiderColors.tertiary)
                            .frame(width: 20, height: 20)
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More actions")
                .padding(.bottom, 6)
            }

            // Multiline text editor — Enter sends, Shift+Enter inserts newline
            MultilineInputField(text: $text, textHeight: $textHeight, isFocused: $isFocused, onSend: {
                if !isEmpty {
                    onSend()
                }
            })
            .frame(height: clampedHeight)

            // Clear chat button
            if let onClear {
                Button {
                    onClear()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear current chat")
                .padding(.bottom, 6)
            }

            // Send button
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isEmpty ? CiderColors.tertiary : CiderColors.controlAccent)
            }
            .buttonStyle(.plain)
            .disabled(isEmpty || !isEnabled)
            .help("Send message")
            .padding(.bottom, 4)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(isFocused ? CiderColors.borderHover : CiderColors.borderDefault, lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}

// MARK: - NSTextView-backed multiline field (Enter sends, Shift+Enter newline)

struct MultilineInputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var textHeight: CGFloat
    var isFocused: FocusState<Bool>.Binding
    var onSend: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.verticalScrollElasticity = .none
        scrollView.scrollerStyle = .overlay

        let textView = InputNSTextView()
        textView.delegate = context.coordinator
        textView.onSend = onSend
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = NSFont.systemFont(ofSize: 12 * CiderFont.scale)
        textView.textColor = NSColor(CiderColors.primary)
        textView.insertionPointColor = NSColor(CiderColors.primary)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.placeholderString = "Ask anything..."

        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? InputNSTextView else { return }
        if textView.string != text {
            context.coordinator.isUpdating = true
            textView.string = text
            context.coordinator.isUpdating = false
            // Defer height recalc to avoid modifying state during view update
            DispatchQueue.main.async {
                context.coordinator.recalcHeight()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MultilineInputField
        weak var textView: InputNSTextView?
        weak var scrollView: NSScrollView?
        /// Guard to prevent writing state back during updateNSView
        var isUpdating = false

        init(_ parent: MultilineInputField) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalcHeight()
        }

        func recalcHeight() {
            guard let textView, let container = textView.textContainer,
                  let layoutManager = textView.layoutManager else { return }
            layoutManager.ensureLayout(for: container)
            let usedRect = layoutManager.usedRect(for: container)
            let newHeight = usedRect.height + textView.textContainerInset.height * 2
            parent.textHeight = newHeight
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = true
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.isFocused.wrappedValue = false
        }
    }
}

/// Custom NSTextView that intercepts Enter to send, Shift+Enter for newline.
final class InputNSTextView: NSTextView {
    var onSend: (() -> Void)?
    var placeholderString: String?

    override func keyDown(with event: NSEvent) {
        // Enter without Shift → send
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Draw placeholder when empty
        if string.isEmpty, let placeholder = placeholderString {
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor(CiderColors.tertiary),
                .font: font ?? NSFont.systemFont(ofSize: 12),
            ]
            let inset = textContainerInset
            let rect = NSRect(
                x: inset.width + 5,
                y: inset.height,
                width: bounds.width - inset.width * 2 - 5,
                height: bounds.height - inset.height * 2
            )
            NSString(string: placeholder).draw(in: rect, withAttributes: attrs)
        }
    }
}
