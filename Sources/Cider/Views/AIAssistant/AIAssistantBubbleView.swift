import SwiftUI

/// A single message bubble in the AI chat.
struct AIAssistantBubbleView: View {
    let message: AIAssistantMessage
    var presentationStyle: AIAssistantPresentationStyle = .floatingPanel
    var maxBubbleWidth: CGFloat? = nil
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
                    if isStreaming {
                        HStack(alignment: .center, spacing: Spacing.xs) {
                            Text(message.content)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)
                                .fixedSize(horizontal: false, vertical: true)

                            BouncingDotsView()
                        }
                    } else if !message.content.isEmpty {
                        if message.role == .assistant {
                            MarkdownContentView(text: message.content)
                        } else {
                            Text(message.content)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if !message.attachments.isEmpty {
                        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: Spacing.xs) {
                            ForEach(message.attachments) { attachment in
                                AIAssistantAttachmentView(
                                    attachment: attachment,
                                    maxWidth: imageMaxWidth
                                )
                            }
                        }
                        .padding(.top, message.content.isEmpty ? 0 : Spacing.xs)
                    }
                }
                .frame(maxWidth: maxContentWidth, alignment: message.role == .user ? .trailing : .leading)
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
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var maxContentWidth: CGFloat? {
        shouldHugContent ? nil : maxBubbleWidth
    }

    private var shouldHugContent: Bool {
        guard message.attachments.isEmpty else { return false }
        if isStreaming { return true }
        guard message.role == .user else { return false }
        return message.content.count <= 220 && longestLineLength <= 96
    }

    private var longestLineLength: Int {
        message.content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(\.count)
            .max() ?? 0
    }

    private var imageMaxWidth: CGFloat {
        min(maxBubbleWidth ?? 520, 520)
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                CiderColors.accentSubtle
            } else if presentationStyle == .floatingPanel {
                CiderColors.surfaceElevated
            } else {
                CiderColors.surfaceSubtle
            }
        }
    }
}

// MARK: - Attachments

private struct AIAssistantAttachmentView: View {
    let attachment: AIAssistantAttachment
    let maxWidth: CGFloat

    var body: some View {
        switch attachment.kind {
        case .image:
            imageView
        }
    }

    @ViewBuilder
    private var imageView: some View {
        if let localFilePath = attachment.localFilePath,
           let image = AIAssistantImageCache.shared.image(path: localFilePath) {
            renderedImage(Image(nsImage: image))
        } else if let remoteURL = attachment.remoteURL,
                  let url = URL(string: remoteURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    attachmentPlaceholder("Loading image...")
                case .success(let image):
                    renderedImage(image)
                case .failure:
                    attachmentPlaceholder("Image unavailable")
                @unknown default:
                    attachmentPlaceholder("Image unavailable")
                }
            }
        } else {
            attachmentPlaceholder("Image attachment")
        }
    }

    private func renderedImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .frame(maxWidth: maxWidth, maxHeight: 360)
            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
            )
    }

    private func attachmentPlaceholder(_ title: String) -> some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: "photo")
            Text(title)
        }
        .font(CiderFont.captionMedium)
        .foregroundColor(CiderColors.tertiary)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceInput)
        )
    }
}

private final class AIAssistantImageCache: @unchecked Sendable {
    static let shared = AIAssistantImageCache()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 80
    }

    func image(path: String) -> NSImage? {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

// MARK: - Markdown Content View

/// Renders markdown text with support for code blocks, inline formatting, and lists.
struct MarkdownContentView: View {
    private let blocks: [MarkdownContentBlock]

    init(text: String) {
        blocks = MarkdownContentCache.shared.blocks(for: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(blocks) { block in
                switch block {
                case .codeBlock(_, let language, let code):
                    codeBlockView(language: language, code: code)
                case .text(_, let content):
                    markdownText(content)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Inline Markdown (bold, italic, code, links)

    private func markdownText(_ content: AttributedString) -> some View {
        Text(content)
            .font(CiderFont.body)
            .foregroundColor(CiderColors.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Code Block View

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                Text(language)
                    .font(CiderFont.captionMonospacedMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .padding(.horizontal, Spacing.sm)
                    .padding(.top, Spacing.xs)
            }

            Text(code)
                .font(CiderFont.labelMonospaced)
                .foregroundColor(CiderColors.primary)
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
}

// MARK: - Markdown Rendering Cache

private enum MarkdownContentBlock: Identifiable {
    case text(Int, AttributedString)
    case codeBlock(Int, language: String, code: String)

    var id: Int {
        switch self {
        case .text(let id, _), .codeBlock(let id, _, _):
            return id
        }
    }
}

private final class MarkdownContentCacheEntry: NSObject {
    let blocks: [MarkdownContentBlock]

    init(blocks: [MarkdownContentBlock]) {
        self.blocks = blocks
    }
}

private final class MarkdownContentCache: @unchecked Sendable {
    static let shared = MarkdownContentCache()

    private let cache = NSCache<NSString, MarkdownContentCacheEntry>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 6 * 1024 * 1024
    }

    func blocks(for input: String) -> [MarkdownContentBlock] {
        let key = input as NSString
        if let cached = cache.object(forKey: key) {
            return cached.blocks
        }

        let blocks = parseBlocks(input)
        cache.setObject(MarkdownContentCacheEntry(blocks: blocks), forKey: key, cost: input.utf8.count)
        return blocks
    }

    private func parseBlocks(_ input: String) -> [MarkdownContentBlock] {
        var blocks: [MarkdownContentBlock] = []
        var currentText = ""
        var inCodeBlock = false
        var codeLanguage = ""
        var codeContent = ""
        var nextID = 0

        func appendText(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            blocks.append(.text(nextID, markdownAttributedString(text)))
            nextID += 1
        }

        func appendCodeBlock(language: String, code: String) {
            blocks.append(.codeBlock(
                nextID,
                language: language,
                code: code.trimmingCharacters(in: .newlines)
            ))
            nextID += 1
        }

        let lines = input.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCodeBlock {
                    // Closing fence
                    appendCodeBlock(language: codeLanguage, code: codeContent)
                    codeLanguage = ""
                    codeContent = ""
                    inCodeBlock = false
                } else {
                    // Opening fence — flush accumulated text
                    if !currentText.isEmpty {
                        appendText(currentText)
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
            appendText(currentText)
        }

        return blocks
    }

    private func markdownAttributedString(_ text: String) -> AttributedString {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attributed
        }
        return AttributedString(text)
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
        .onAppear { animating = true }
    }
}
