import SwiftUI

struct SourceCardView: View {
    let file: ExternalFile
    let width: CGFloat
    var isSelected: Bool = false
    var onOpen: () -> Void = {}
    var onDelete: () -> Void = {}

    @State private var isHovered = false
    @State private var contentPreview: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(file.title)
                .font(CiderFont.subheadingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(2)

            if !contentPreview.isEmpty {
                Text(contentPreview)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(4)
            }

            Spacer(minLength: 0)

            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder.badge.gear")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)

                Text(file.sourceName)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)

                Text("·")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)

                Text(file.modifiedAt, style: .relative)
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(Spacing.md)
        .frame(width: width, alignment: .leading)
        .cardContainer(isHovered: isHovered, isSelected: isSelected)
        .hoverState($isHovered)
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .onTapGesture {
            onOpen()
        }
        .contextMenu {
            Button {
                NSWorkspace.shared.open(file.path)
            } label: {
                Label("Open in Default App", systemImage: "arrow.up.right.square")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Move to Trash", systemImage: "trash")
            }
        }
        .task(id: file.modifiedAt) {
            await loadContentPreview()
        }
    }

    private func loadContentPreview() async {
        let path = file.path
        let preview = await Task.detached(priority: .userInitiated) {
            guard let raw = try? String(contentsOf: path, encoding: .utf8) else { return "" }
            let prefix = String(raw.prefix(300))
            // Strip common markdown syntax characters
            var cleaned = prefix
            cleaned = cleaned.replacingOccurrences(of: #"#{1,6}\s"#, with: "", options: .regularExpression)
            cleaned = cleaned.replacingOccurrences(of: "**", with: "")
            cleaned = cleaned.replacingOccurrences(of: "*", with: "")
            cleaned = cleaned.replacingOccurrences(of: "__", with: "")
            cleaned = cleaned.replacingOccurrences(of: "_", with: "")
            cleaned = cleaned.replacingOccurrences(of: "`", with: "")
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned
        }.value
        await MainActor.run {
            contentPreview = preview
        }
    }
}
