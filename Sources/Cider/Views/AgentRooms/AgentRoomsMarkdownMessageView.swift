import SwiftUI

struct AgentRoomsMarkdownMessageView: View {
    let document: AgentRoomsMarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(document.blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            AgentRoomsSafeLinkPolicy.isAllowed(url) ? .systemAction(url) : .discarded
        })
    }

    @ViewBuilder
    private func blockView(_ block: AgentRoomsMarkdownBlock) -> some View {
        switch block.kind {
        case .paragraph:
            richText(block.content, font: CiderFont.label)
        case .heading(let level):
            richText(block.content, font: headingFont(level))
                .padding(.top, Spacing.xs)
        case .unorderedListItem(let depth):
            listRow(marker: "•", depth: depth, content: block.content)
        case .orderedListItem(let depth, let ordinal):
            listRow(marker: "\(ordinal).", depth: depth, content: block.content)
        case .code(let language, let isComplete):
            codeBlock(language: language, code: block.plainText, isComplete: isComplete)
        }
    }

    private func richText(_ content: AttributedString, font: Font) -> some View {
        Text(content)
            .font(font)
            .foregroundColor(CiderColors.primary)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listRow(marker: String, depth: Int, content: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(marker)
                .font(CiderFont.labelMedium)
                .foregroundColor(CiderColors.secondary)
                .frame(minWidth: 16, alignment: .trailing)
                .accessibilityHidden(true)
            richText(content, font: CiderFont.label)
        }
        .padding(.leading, CGFloat(min(depth, 4)) * Spacing.lg)
        .accessibilityElement(children: .combine)
    }

    private func codeBlock(language: String?, code: String, isComplete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language {
                HStack(spacing: Spacing.sm) {
                    Text(language)
                        .font(CiderFont.captionMonospacedMedium)
                    if !isComplete {
                        Text("Streaming")
                            .font(CiderFont.microMedium)
                    }
                }
                .foregroundColor(CiderColors.tertiary)
                .padding(.horizontal, Spacing.sm)
                .padding(.top, Spacing.xs)
            }
            ScrollView(.horizontal) {
                Text(code)
                    .font(CiderFont.labelMonospaced)
                    .foregroundColor(CiderColors.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(Spacing.sm)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm).fill(CiderColors.surfaceInput))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isComplete ? "Code block" : "Streaming code block")
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: CiderFont.titleMedium
        case 2: CiderFont.headingSemibold
        default: CiderFont.subheadingSemibold
        }
    }
}
