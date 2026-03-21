import SwiftUI

/// Chat UI inside an expanded Claude session card.
struct ClaudeSessionChatView: View {
    let session: ClaudeSession
    let onSend: (String) -> Void

    @State private var inputText = ""

    private var isWorking: Bool {
        if case .working = session.status { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.sm) {
                        ForEach(session.messages) { msg in
                            ClaudeMessageBubble(message: msg)
                                .id(msg.id)
                        }

                        if isWorking {
                            HStack(spacing: Spacing.xs) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Thinking...")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                            .id("working-indicator")
                        }
                    }
                    .padding(Spacing.sm)
                }
                .frame(maxHeight: SessionsDesign.chatMaxHeight)
                .onChange(of: session.messages.count) { _, _ in
                    if let lastID = session.messages.last?.id {
                        withAnimation(.snappy) {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input bar
            HStack(spacing: Spacing.sm) {
                TextField("Message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(CiderFont.body)
                    .frame(minHeight: SessionsDesign.inputFieldMinHeight)
                    .onSubmit { send() }
                    .disabled(isWorking)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(CiderFont.heading)
                        .foregroundColor(canSend ? CiderColors.controlAccent : CiderColors.tertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
        }
    }

    private var canSend: Bool {
        !isWorking && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isWorking else { return }
        onSend(trimmed)
        inputText = ""
    }
}
