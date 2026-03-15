import SwiftUI

struct SessionCardCardView: View {
    let session: BrowserSession
    var onOpen: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @State private var isHovered = false

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Header: icon + name
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "rectangle.stack")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.controlAccent)

                    Text(session.name)
                        .font(CiderFont.subheadingSemibold)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Tab count badge + source browser
                HStack(spacing: Spacing.sm) {
                    HStack(spacing: Spacing.xxs) {
                        Image(systemName: "square.stack")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                        Text("\(session.tabCount) tab\(session.tabCount == 1 ? "" : "s")")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                    }

                    if let browserName = session.sourceBrowserName {
                        Text("\u{00B7}")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.quaternary)
                        Text(browserName)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                // Tab preview — first few tab titles
                if !session.tabs.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        ForEach(Array(session.tabs.prefix(3))) { tab in
                            HStack(spacing: Spacing.xs) {
                                Circle()
                                    .fill(CiderColors.quaternary)
                                    .frame(width: Spacing.xs, height: Spacing.xs)
                                Text(tab.title ?? tab.urlString)
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.secondary)
                                    .lineLimit(1)
                            }
                        }
                        if session.tabs.count > 3 {
                            Text("+\(session.tabs.count - 3) more")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }

                // Bottom row: date
                HStack(spacing: Spacing.sm) {
                    Text(session.createdAt.formatted(.relative(presentation: .named)))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                    Spacer(minLength: 0)
                }

                if !session.labelIDs.isEmpty {
                    TagPillRow(
                        labelIDs: session.labelIDs,
                        labels: CardLabelStorage.shared.labels
                    )
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .top)
        .cardContainer(isHovered: isHovered, isSelected: isSelected, isFocused: isFocused)
        .overlay(alignment: .topLeading) {
            if isSelected {
                SelectionCheckmark()
                    .padding(Spacing.sm)
            }
        }
        .hoverState($isHovered, animation: .snappy)
        .help("Session: \(session.name)")
        .contextMenu {
            Button("Open") { onOpen?() }

            Divider()

            if !folders.isEmpty {
                Menu("Move to Folder") {
                    Button("Unfiled") { onMoveToFolder?(nil) }
                    Divider()
                    ForEach(folders) { folder in
                        Button(folder.name) { onMoveToFolder?(folder.id) }
                    }
                }
            }

            if !CardLabelStorage.shared.labels.isEmpty {
                Menu("Tags") {
                    ForEach(CardLabelStorage.shared.labels) { label in
                        let hasTag = session.labelIDs.contains(label.id)
                        Button {
                            if isSelected {
                                onToggleLabelBulk?(label.id)
                            } else {
                                var updated = session
                                if hasTag {
                                    updated.labelIDs.removeAll { $0 == label.id }
                                } else {
                                    updated.labelIDs.append(label.id)
                                }
                                _ = BrowserSessionStorage.shared.save(updated)
                            }
                        } label: {
                            HStack {
                                Text(label.name)
                                if hasTag {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) { onDelete?() }
        }
    }
}

// MARK: - Session List Row

struct SessionListRow: View {
    let session: BrowserSession
    var onOpen: (() -> Void)? = nil
    var folders: [Folder] = []
    var onMoveToFolder: ((UUID?) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var isSelected: Bool = false
    var isFocused: Bool = false
    var onSelect: (() -> Void)? = nil
    var onShiftSelect: (() -> Void)? = nil
    var onToggleLabelBulk: ((UUID) -> Void)? = nil

    @State private var isHovered = false

    private func handleClick(normalAction: () -> Void) {
        let flags = NSEvent.modifierFlags
        if let onSelect, flags.contains(.command) {
            onSelect()
        } else if let onShiftSelect, flags.contains(.shift) {
            onShiftSelect()
        } else {
            normalAction()
        }
    }

    var body: some View {
        Button {
            handleClick { onOpen?() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if isSelected {
                    SelectionCheckmark()
                }

                Image(systemName: "rectangle.stack")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(session.name)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    HStack(spacing: Spacing.xs) {
                        Text("\(session.tabCount) tab\(session.tabCount == 1 ? "" : "s")")
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)

                        if let browserName = session.sourceBrowserName {
                            Text("\u{00B7}")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.quaternary)
                            Text(browserName)
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: Spacing.sm)

                Text(session.createdAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(
                        isFocused ? CiderColors.controlAccent : (isSelected ? CiderColors.controlAccent : Color.clear),
                        lineWidth: isFocused ? 1.5 : (isSelected ? CiderBorder.innerStrokeWidth : 0)
                    )
            )
        }
        .buttonStyle(.plain)
        .hoverState($isHovered, animation: .snappy)
        .help("Session: \(session.name)")
        .contextMenu {
            Button("Open") { onOpen?() }

            Divider()

            if !folders.isEmpty {
                Menu("Move to Folder") {
                    Button("Unfiled") { onMoveToFolder?(nil) }
                    Divider()
                    ForEach(folders) { folder in
                        Button(folder.name) { onMoveToFolder?(folder.id) }
                    }
                }
            }

            Divider()

            Button("Delete", role: .destructive) { onDelete?() }
        }
    }
}
