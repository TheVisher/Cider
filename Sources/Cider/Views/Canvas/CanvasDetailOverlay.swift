import SwiftUI

/// Floating detail modal that appears on the right side of the canvas
/// when a card is selected, showing full metadata for the selected item.
struct CanvasDetailOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject private var labelStorage = CardLabelStorage.shared

    private static let overlayWidth: CGFloat = 380
    private static let verticalInset: CGFloat = Spacing.xxl

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            detailContent
                .frame(width: Self.overlayWidth)
                .frame(maxHeight: .infinity)
                .padding(.vertical, Self.verticalInset)
                .padding(.trailing, Spacing.lg)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        if let selectedID = viewModel.selectedItemID,
           let uuid = UUID(uuidString: selectedID) {
            VStack(spacing: 0) {
                // Close button header
                closeHeader

                // Scrollable metadata
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if let bookmark = viewModel.bookmarkLookup[uuid] {
                            bookmarkDetail(bookmark)
                        } else if let note = viewModel.noteLookup[uuid] {
                            noteDetail(note)
                        } else if let todo = viewModel.todoLookup[uuid] {
                            todoDetail(todo)
                        } else {
                            unknownItemPlaceholder
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.bottom, Spacing.lg)
                }
            }
            .background {
                VisualEffectView(
                    material: .underWindowBackground,
                    blendingMode: .withinWindow
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .strokeBorder(CiderColors.borderSubtle, lineWidth: CiderBorder.hairlineStrokeWidth)
            }
            .shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
        }
    }

    // MARK: - Close Header

    private var closeHeader: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
                    viewModel.deselectAll()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: Spacing.xxl, height: Spacing.xxl)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.top, Spacing.sm)
    }

    // MARK: - Bookmark Detail

    private func bookmarkDetail(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Thumbnail
            if let thumbnailURL = bookmark.thumbnailFileURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
            }

            // Title
            Text(bookmark.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            // Domain with favicon
            if bookmark.hasURL {
                HStack(spacing: Spacing.xs) {
                    // Favicon from Google
                    if let host = bookmark.url?.host {
                        AsyncImage(url: URL(string: "https://www.google.com/s2/favicons?sz=32&domain=\(host)")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .frame(width: Spacing.lg, height: Spacing.lg)
                                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
                            default:
                                Image(systemName: "globe")
                                    .font(CiderFont.caption)
                                    .foregroundColor(CiderColors.tertiary)
                            }
                        }
                    }

                    Text(bookmark.hostDisplay)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            // Folder
            if let folderID = bookmark.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            // Tags
            if !bookmark.labelIDs.isEmpty {
                labelPills(for: bookmark.labelIDs)
            }

            // AI Summary
            if let summary = bookmark.aiSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Summary")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Text(summary)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            // Notes
            if !bookmark.notes.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Notes")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)
                    Text(bookmark.notes)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            // Created date
            metadataRow(
                icon: "calendar",
                label: "Added",
                value: bookmark.createdAt.noteCardDate
            )

            // Open in Browser
            if bookmark.hasURL, let url = bookmark.url {
                Button {
                    openURLSafely(url)
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "safari")
                        Text("Open in Browser")
                    }
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Note Detail

    private func noteDetail(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title
            Text(note.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            // Content preview
            let preview = note.contentPreview
            if !preview.isEmpty {
                Text(preview)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(10)
                    .textSelection(.enabled)
            }

            Divider()

            // Folder
            if let folderID = note.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            // Tags
            if !note.labelIDs.isEmpty {
                labelPills(for: note.labelIDs)
            }

            // Word count
            let wordCount = note.wordCount
            if wordCount > 0 {
                metadataRow(
                    icon: "textformat.abc",
                    label: "Words",
                    value: "\(wordCount)"
                )
            }

            // Modified date
            metadataRow(
                icon: "calendar",
                label: "Modified",
                value: note.modifiedAt.noteCardDate
            )
        }
    }

    // MARK: - Todo Detail

    private func todoDetail(_ todo: TodoCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title with completion indicator
            HStack(spacing: Spacing.sm) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(todo.isCompleted ? CiderColors.success : CiderColors.tertiary)

                Text(todo.title)
                    .font(CiderFont.headingSemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(3)
                    .strikethrough(todo.isCompleted)
                    .textSelection(.enabled)
            }

            // Priority
            if let priority = todo.priority {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: priority.icon)
                        .font(CiderFont.caption)
                        .foregroundColor(priority.color)
                    Text(priority.displayName + " Priority")
                        .font(CiderFont.captionMedium)
                        .foregroundColor(priority.color)
                }
            }

            // Due date
            if let dueDate = todo.dueDate {
                metadataRow(
                    icon: "clock",
                    label: "Due",
                    value: dueDate.noteCardDate
                )
            }

            // Details
            if !todo.details.isEmpty {
                Text(todo.details)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            // Checklist
            if !todo.checklist.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Checklist (\(todo.completedCount)/\(todo.totalCount))")
                        .font(CiderFont.captionSemibold)
                        .foregroundColor(CiderColors.tertiary)

                    ForEach(todo.checklist) { item in
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .font(CiderFont.body)
                                .foregroundColor(item.isCompleted ? CiderColors.success : CiderColors.tertiary)

                            Text(item.title)
                                .font(CiderFont.body)
                                .foregroundColor(item.isCompleted ? CiderColors.tertiary : CiderColors.primary)
                                .strikethrough(item.isCompleted)
                                .lineLimit(2)
                        }
                    }
                }
            }

            // Folder
            if let folderID = todo.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            // Tags
            if !todo.labelIDs.isEmpty {
                labelPills(for: todo.labelIDs)
            }

            // Created date
            metadataRow(
                icon: "calendar",
                label: "Created",
                value: todo.createdAt.noteCardDate
            )
        }
    }

    // MARK: - Shared Components

    private func metadataRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: Spacing.lg)

            Text(label)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            Spacer()

            Text(value)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .lineLimit(1)
        }
    }

    private func labelPills(for labelIDs: [UUID]) -> some View {
        let labels = labelIDs.compactMap { id in
            labelStorage.labels.first { $0.id == id }
        }
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Tags")
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)

            TagFlowLayout(spacing: Spacing.xs) {
                ForEach(labels) { label in
                    let fillColor = Color(hex: label.colorHex) ?? CiderColors.controlAccent
                    HStack(spacing: Spacing.xs) {
                        Circle()
                            .fill(fillColor)
                            .frame(width: Spacing.sm, height: Spacing.sm)
                        Text(label.name)
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.primary)
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(CiderColors.surfaceInput)
                    )
                }
            }
        }
    }

    private var unknownItemPlaceholder: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: Spacing.xxxl))
                .foregroundColor(CiderColors.tertiary)
            Text("Item not found")
                .font(CiderFont.body)
                .foregroundColor(CiderColors.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

