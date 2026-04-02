import SwiftUI

/// Centered floating detail modal over the canvas.
/// Split layout: hero content (left) + metadata sidebar (right).
struct CanvasDetailOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasSize: CGSize
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    // MARK: - Layout Constants

    private static let modalWidth: CGFloat = 800
    private static let minHeight: CGFloat = 400
    private static let sidebarWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth

    // MARK: - Body

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Modal
            modalContent
                .frame(width: Self.modalWidth, height: modalHeight)
                .background { modalBackground }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                        .allowsHitTesting(false)
                }
                .shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
        }
    }

    // MARK: - Modal Content

    @ViewBuilder
    private var modalContent: some View {
        if let selectedID = viewModel.selectedItemID,
           let uuid = UUID(uuidString: selectedID) {
            VStack(spacing: 0) {
                toolbar(for: uuid)

                Divider()
                    .background(CiderColors.separator)
                    .padding(.leading, Spacing.md + Spacing.xxs)

                // Split content area
                HStack(spacing: 0) {
                    heroColumn(for: uuid)

                    // Vertical separator
                    Rectangle()
                        .fill(CiderColors.separator)
                        .frame(width: 1)

                    metadataSidebar(for: uuid)
                        .frame(width: Self.sidebarWidth)
                        .background(CiderColors.surfaceInput)
                }
            }
        } else {
            unknownItemPlaceholder
        }
    }

    // MARK: - Helpers

    private var modalHeight: CGFloat {
        let target = canvasSize.height * 0.8
        let maxH = canvasSize.height - Spacing.xxl * 2
        return min(max(target, Self.minHeight), maxH)
    }

    private var modalBackground: some View {
        ZStack {
            VisualEffectView(
                material: .underWindowBackground,
                blendingMode: .withinWindow
            )
            CiderColors.acrylicOverlayTint
            CiderColors.surfaceSubtle
        }
    }

    private func dismiss() {
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
            onDismiss()
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

    // MARK: - Toolbar

    private func toolbar(for uuid: UUID) -> some View {
        HStack(spacing: Spacing.sm) {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Title + domain
            toolbarTitle(for: uuid)

            Spacer(minLength: 0)

            // Actions (bookmark-only)
            if let bookmark = viewModel.bookmarkLookup[uuid] {
                toolbarActions(for: bookmark)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.xs + 1)
    }

    @ViewBuilder
    private func toolbarTitle(for uuid: UUID) -> some View {
        if let bookmark = viewModel.bookmarkLookup[uuid] {
            VStack(alignment: .leading, spacing: 0) {
                Text(bookmark.title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)
                if bookmark.hasURL {
                    Text(bookmark.hostDisplay)
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }
        } else if let note = viewModel.noteLookup[uuid] {
            Text(note.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        } else if let todo = viewModel.todoLookup[uuid] {
            Text(todo.title)
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)
        }
    }

    private func toolbarActions(for bookmark: Bookmark) -> some View {
        HStack(spacing: Spacing.xs) {
            // Copy URL
            if bookmark.hasURL {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(bookmark.urlString, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy URL")
            }

            // Open in browser
            if let url = bookmark.url {
                Button {
                    openURLSafely(url)
                } label: {
                    Image(systemName: "safari")
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.secondary)
                        .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open in Browser")
            }
        }
    }

    // MARK: - Hero Column (Left)

    @ViewBuilder
    private func heroColumn(for uuid: UUID) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            if let bookmark = viewModel.bookmarkLookup[uuid] {
                bookmarkHero(bookmark)
            } else if let note = viewModel.noteLookup[uuid] {
                noteHero(note)
            } else if let todo = viewModel.todoLookup[uuid] {
                todoHero(todo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    // MARK: - Bookmark Hero

    private func bookmarkHero(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title
            Text(bookmark.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            // Domain with favicon
            if bookmark.hasURL {
                HStack(spacing: Spacing.xs) {
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

            // Thumbnail hero
            if let thumbnailURL = bookmark.thumbnailFileURL {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .shadow(
                                color: CiderColors.shadowMedium,
                                radius: BookmarksDesign.detailsFloatingLiftBlur,
                                x: 0,
                                y: BookmarksDesign.detailsFloatingLiftYOffset
                            )
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                // Fallback letter icon
                bookmarkFallbackHero(bookmark)
            }
        }
    }

    private func bookmarkFallbackHero(_ bookmark: Bookmark) -> some View {
        let letter = bookmark.title.first.map(String.init) ?? "?"
        return RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(CiderColors.surfaceInput)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .overlay {
                Text(letter)
                    .font(.system(size: BookmarksDesign.detailsHeroFallbackLetterSize, weight: .bold, design: .rounded))
                    .foregroundColor(CiderColors.tertiary)
            }
    }

    // MARK: - Note Hero

    private func noteHero(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(note.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            let preview = note.contentPreview
            if !preview.isEmpty {
                Text(preview)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Todo Hero

    private func todoHero(_ todo: TodoCard) -> some View {
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

            // Details
            if !todo.details.isEmpty {
                Text(todo.details)
                    .font(CiderFont.body)
                    .foregroundColor(CiderColors.secondary)
                    .textSelection(.enabled)
            }

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
        }
    }

    // MARK: - Metadata Sidebar (Right)

    private func metadataSidebar(for uuid: UUID) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let bookmark = viewModel.bookmarkLookup[uuid] {
                    bookmarkMetadata(bookmark)
                } else if let note = viewModel.noteLookup[uuid] {
                    noteMetadata(note)
                } else if let todo = viewModel.todoLookup[uuid] {
                    todoMetadata(todo)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Bookmark Metadata

    private func bookmarkMetadata(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
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
                metadataSection(title: "Summary") {
                    Text(summary)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            // Notes
            if !bookmark.notes.isEmpty {
                metadataSection(title: "Notes") {
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

    // MARK: - Note Metadata

    private func noteMetadata(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
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
                metadataRow(icon: "textformat.abc", label: "Words", value: "\(wordCount)")
            }

            Divider()

            // Modified date
            metadataRow(
                icon: "calendar",
                label: "Modified",
                value: note.modifiedAt.noteCardDate
            )
        }
    }

    // MARK: - Todo Metadata

    private func todoMetadata(_ todo: TodoCard) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Due date
            if let dueDate = todo.dueDate {
                metadataRow(icon: "clock", label: "Due", value: dueDate.noteCardDate)
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

            Divider()

            // Created date
            metadataRow(
                icon: "calendar",
                label: "Created",
                value: todo.createdAt.noteCardDate
            )
        }
    }

    // MARK: - Shared Components

    private func metadataSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            content()
        }
    }

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
}
