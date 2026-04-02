import SwiftUI

/// Centered floating detail modal over the canvas.
/// Split layout: hero content (left) + metadata sidebar (right).
struct CanvasDetailOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasSize: CGSize
    let isSidebarVisible: Bool
    let isSearchVisible: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var labelStorage = CardLabelStorage.shared

    // Draft for editable bookmark metadata sidebar
    @State private var draft: BookmarkDetailsDraft?
    @State private var detailsErrorMessage: String?

    // MARK: - Layout Constants

    private static let minWidth: CGFloat = BookmarksDesign.detailsSlideOutMinWidth
    private static let minHeight: CGFloat = 400
    private static let metadataSidebarWidth: CGFloat = BookmarksDesign.detailsSidebarFixedWidth
    private static let canvasSidebarWidth: CGFloat = BookmarksDesign.folderSidebarWidth
    private static let modalInset: CGFloat = Spacing.xxl

    /// Available width to the right of the canvas sidebar (or full width if collapsed).
    private var availableWidth: CGFloat {
        isSidebarVisible
            ? canvasSize.width - Self.canvasSidebarWidth
            : canvasSize.width
    }

    /// Space reserved for the search palette when it's open.
    private static let paletteReservedWidth: CGFloat = SearchPaletteDesign.paletteWidth + Spacing.md

    private var modalWidth: CGFloat {
        let space = isSearchVisible
            ? availableWidth - Self.paletteReservedWidth - Self.modalInset
            : availableWidth - Self.modalInset * 2
        return max(min(space, 1200), Self.minWidth)
    }

    /// Horizontal offset to center the modal in its available space.
    private var modalOffsetX: CGFloat {
        var offset: CGFloat = isSidebarVisible ? Self.canvasSidebarWidth / 2 : 0
        if isSearchVisible {
            // Shift right to make room for the palette on the left
            offset += Self.paletteReservedWidth / 2
        }
        return offset
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            // Modal — centered in available space (right of sidebar)
            modalContent
                .frame(width: modalWidth, height: modalHeight)
                .background { modalBackground }
                .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                        .allowsHitTesting(false)
                }
                .shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
                .offset(x: modalOffsetX)
        }
        .onChange(of: viewModel.selectedItemID) { _, newID in
            updateDraft(for: newID)
        }
        .onAppear {
            updateDraft(for: viewModel.selectedItemID)
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

                    // Bookmark: use the full BookmarkMetadataSidebar from NSPanel
                    if let bookmark = viewModel.bookmarkLookup[uuid], draft != nil {
                        bookmarkMetadataSidebarView(bookmark: bookmark)
                    } else {
                        // Notes/Todos: simple metadata
                        VStack(spacing: 0) {
                            CiderColors.separator
                                .frame(width: Spacing.hairline)
                                .frame(maxHeight: .infinity)
                        }
                        .background(CiderColors.surfaceInput)
                        .overlay(alignment: .leading) {
                            CiderColors.separator
                                .frame(width: Spacing.hairline)
                        }
                        .frame(width: Self.metadataSidebarWidth)
                        .overlay {
                            simpleMetadataSidebar(for: uuid)
                                .frame(width: Self.metadataSidebarWidth)
                        }
                    }
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
        saveDraft()
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
            onDismiss()
        }
    }

    private func updateDraft(for selectedID: String?) {
        guard let selectedID,
              let uuid = UUID(uuidString: selectedID),
              let bookmark = viewModel.bookmarkLookup[uuid] else {
            draft = nil
            detailsErrorMessage = nil
            return
        }
        draft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsErrorMessage = nil
    }

    private func saveDraft() {
        guard let draft,
              let selectedID = viewModel.selectedItemID,
              let uuid = UUID(uuidString: selectedID),
              viewModel.bookmarkLookup[uuid] != nil else { return }

        let parsedTags = draft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceURL: String? = draft.sourceURL != draft.originalURLString
            ? draft.sourceURL
            : nil

        VaultBookmarkService.shared.updateDetails(
            for: uuid,
            title: draft.title,
            notes: draft.notes,
            tags: parsedTags,
            labelIDs: draft.labelIDs,
            urlString: sourceURL
        )
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
        VStack(spacing: 0) {
            if let bookmark = viewModel.bookmarkLookup[uuid] {
                bookmarkHero(bookmark)
            } else if let note = viewModel.noteLookup[uuid] {
                ScrollView(.vertical, showsIndicators: false) {
                    noteHero(note)
                }
            } else if let todo = viewModel.todoLookup[uuid] {
                ScrollView(.vertical, showsIndicators: false) {
                    todoHero(todo)
                }
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

            // Thumbnail hero — centered, constrained, not stretched
            Spacer(minLength: 0)

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
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                bookmarkFallbackHero(bookmark)
            }

            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
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

    // MARK: - Bookmark Metadata Sidebar (reuses NSPanel component)

    @ViewBuilder
    private func bookmarkMetadataSidebarView(bookmark: Bookmark) -> some View {
        if let draftBinding = makeDraftBinding() {
            BookmarkMetadataSidebar(
                draft: draftBinding,
                bookmark: bookmark,
                errorMessage: detailsErrorMessage,
                folders: VaultFolderService.shared.legacyFolders,
                width: Self.metadataSidebarWidth,
                showBackground: false,
                onDelete: {
                    let bm = bookmark
                    dismiss()
                    let trashItems = VaultBookmarkService.shared.removeAll([bm])
                    if !trashItems.isEmpty {
                        CiderUndoManager.shared.record(.bulkDeletedToTrash(trashItems))
                    }
                },
                onFolderChanged: { folderID in
                    VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: folderID)
                },
                onOpenURL: {
                    if let url = bookmark.url { openURLSafely(url) }
                },
                onCopyURL: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(bookmark.urlString, forType: .string)
                },
                onSave: { saveDraft() },
                onCancel: { dismiss() }
            )
            .background(CiderColors.surfaceInput)
            .overlay(alignment: .leading) {
                CiderColors.separator
                    .frame(width: Spacing.hairline)
            }
        }
    }

    private func makeDraftBinding() -> Binding<BookmarkDetailsDraft>? {
        guard draft != nil else { return nil }
        return Binding(
            get: { self.draft! },
            set: { next in
                self.draft = next
                self.detailsErrorMessage = nil
            }
        )
    }

    // MARK: - Simple Metadata Sidebar (Notes/Todos)

    private func simpleMetadataSidebar(for uuid: UUID) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let note = viewModel.noteLookup[uuid] {
                    noteMetadata(note)
                } else if let todo = viewModel.todoLookup[uuid] {
                    todoMetadata(todo)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Note Metadata

    private func noteMetadata(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let folderID = note.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            if !note.labelIDs.isEmpty {
                labelPills(for: note.labelIDs)
            }

            let wordCount = note.wordCount
            if wordCount > 0 {
                metadataRow(icon: "textformat.abc", label: "Words", value: "\(wordCount)")
            }

            Divider()

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
            if let dueDate = todo.dueDate {
                metadataRow(icon: "clock", label: "Due", value: dueDate.noteCardDate)
            }

            if let folderID = todo.folderID,
               let folder = VaultFolderService.shared.folder(for: folderID) {
                metadataRow(icon: "folder", label: "Folder", value: folder.name)
            }

            if !todo.labelIDs.isEmpty {
                labelPills(for: todo.labelIDs)
            }

            Divider()

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
}
