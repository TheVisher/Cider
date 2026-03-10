import SwiftUI

struct AIChatInputView: View {
    @Binding var text: String
    let isEnabled: Bool
    let onSend: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask anything...", text: $text)
                .textFieldStyle(.plain)
                .font(CiderFont.label)
                .foregroundColor(CiderColors.primary)
                .focused($isFocused)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? CiderColors.tertiary
                            : CiderColors.controlAccent
                    )
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isEnabled)
            .help("Send message")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(isFocused ? CiderColors.borderHover : CiderColors.borderDefault, lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
    }
}
