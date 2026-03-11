import SwiftUI

struct AIChatInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: () -> Void
    var onNewChat: (() -> Void)?
    var onClear: (() -> Void)?

    @FocusState private var isFocused: Bool

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
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
            }

            // Text field
            TextField("Ask anything...", text: $text)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.primary)
                .focused($isFocused)
                .onSubmit {
                    if !isEmpty {
                        onSend()
                    }
                }

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
