import SwiftUI
import os

private let logger = Logger(subsystem: "com.cider.app", category: "CaptureMode")

struct UtilityPanelCaptureView: View {
    @State private var inputText = ""
    @State private var savedMessage: String?
    @FocusState private var isInputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            Image(systemName: "arrow.down.doc")
                .font(.system(size: 32))
                .foregroundColor(CiderColors.tertiary)

            Text("Quick Capture")
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.secondary)

            Text("Paste a URL to save a bookmark, or type text to create a note")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)

            TextField("URL or note...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.primary)
                .padding(Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.innerStrokeWidth)
                )
                .padding(.horizontal, Spacing.lg)
                .focused($isInputFocused)
                .onSubmit { save() }
                .lineLimit(1...5)

            Button { save() } label: {
                Text("Save")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.textOnColor)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CiderColors.controlAccent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let savedMessage {
                Text(savedMessage)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.success)
                    .transition(.opacity)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isInputFocused = true }
    }

    private func save() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if looksLikeURL(trimmed) {
            let urlString = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
            VaultBookmarkService.shared.add(urlString: urlString, title: URL(string: urlString)?.host ?? trimmed)
            savedMessage = "Bookmark saved"
            logger.debug("Captured bookmark: \(urlString)")
        } else {
            let note = NotesStorage.shared.createNew(initialContent: trimmed)
            savedMessage = "Note created"
            logger.debug("Captured note: \(note.title)")
        }

        inputText = ""

        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation(reduceMotion ? .none : .snappy) {
                    savedMessage = nil
                }
            }
        }
    }

    private func looksLikeURL(_ text: String) -> Bool {
        if text.hasPrefix("http://") || text.hasPrefix("https://") { return true }
        if !text.contains(" ") && text.contains(".") {
            let parts = text.split(separator: ".")
            if parts.count >= 2, let last = parts.last, last.count >= 2 { return true }
        }
        return false
    }
}
