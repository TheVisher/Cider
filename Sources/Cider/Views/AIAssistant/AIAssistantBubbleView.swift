import SwiftUI

/// A single message bubble in the AI chat.
struct AIAssistantBubbleView: View {
    let message: AIAssistantMessage
    var isStreaming = false

    @State private var showCopied = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                if message.role == .user {
                    Spacer(minLength: Spacing.xxxl)
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xxs) {
                    if message.role == .assistant {
                        MarkdownContentView(text: message.content)
                    } else {
                        Text(message.content)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.primary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isStreaming {
                        BouncingDotsView()
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))

                if message.role == .assistant {
                    Spacer(minLength: Spacing.xxxl)
                }
            }

            // Timestamp + copy button
            HStack(spacing: Spacing.xs) {
                Text(Self.timeFormatter.string(from: message.timestamp))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.content, forType: .string)
                    showCopied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        showCopied = false
                    }
                } label: {
                    Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        .font(CiderFont.caption)
                        .foregroundColor(showCopied ? CiderColors.successMuted : CiderColors.quaternary)
                }
                .buttonStyle(.plain)
                .help("Copy message")
            }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                CiderColors.accentSubtle
            } else {
                CiderColors.surfaceElevated
            }
        }
    }
}

// MARK: - Markdown Content View

/// Renders markdown text with support for code blocks, inline formatting, and lists.
struct MarkdownContentView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .codeBlock(let language, let code):
                    codeBlockView(language: language, code: code)
                case .text(let content):
                    if !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        markdownText(content)
                    }
                }
            }
        }
    }

    // MARK: - Inline Markdown (bold, italic, code, links)

    private func markdownText(_ content: String) -> some View {
        let attributed = markdownAttributedString(content)
        return Text(attributed)
            .font(CiderFont.body)
            .foregroundColor(CiderColors.primary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func markdownAttributedString(_ text: String) -> AttributedString {
        // Try parsing as markdown; fall back to plain text
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
    }

    // MARK: - Code Block View

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.xs)
            }

            Text(code)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(CiderColors.primary)
                .textSelection(.enabled)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
    }

    // MARK: - Block Parser

    private enum ContentBlock {
        case text(String)
        case codeBlock(language: String, code: String)
    }

    /// Splits markdown text into alternating text and fenced code blocks.
    private func parseBlocks(_ input: String) -> [ContentBlock] {
        var blocks: [ContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""

        let lines = input.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Closing fence
                    blocks.append(.codeBlock(language: codeLanguage, code: codeContent.trimmingCharacters(in: .newlines)))
                    codeLanguage = ""
                    codeContent = ""
                    inCodeBlock = false
                } else {
                    // Opening fence — flush accumulated text
                    if !currentText.isEmpty {
                        blocks.append(.text(currentText))
                        currentText = ""
                    }
                    codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    inCodeBlock = true
                }
            } else if inCodeBlock {
                if !codeContent.isEmpty { codeContent += "\n" }
                codeContent += line
            } else {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            }
        }

        // Flush remaining
        if inCodeBlock {
            // Unclosed code block — treat as text
            if !codeContent.isEmpty {
                currentText += "\n```\(codeLanguage)\n\(codeContent)"
            }
        }
        if !currentText.isEmpty {
            blocks.append(.text(currentText))
        }

        return blocks
    }
}

// MARK: - Bouncing Dots

/// Three dots that bounce at staggered intervals.
struct BouncingDotsView: View {
    @State private var animating = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(CiderColors.tertiary)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -4 : 0)
                    .animation(
                        reduceMotion ? .none :
                            .spring(duration: 0.4, bounce: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.top, Spacing.xxs)
        .onAppear { animating = true }
    }
}
