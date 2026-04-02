import SwiftUI

/// Canvas command palette overlay.
/// Centers the NSPanel's SearchPaletteView, with push-aside detail when a result is selected.
struct CanvasSearchOverlay: View {
    @ObservedObject var viewModel: CanvasViewModel
    let canvasSize: CGSize
    let isSidebarVisible: Bool
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Selected result triggers push-aside detail
    @State private var selectedResult: SearchResult?

    // Draft for editable bookmark metadata sidebar
    @State private var draft: BookmarkDetailsDraft?
    @State private var detailsErrorMessage: String?

    // MARK: - Layout Constants

    private static let palettePushedWidth: CGFloat = 360
    private static let detailGap: CGFloat = Spacing.md
    private static let canvasSidebarWidth: CGFloat = BookmarksDesign.folderSidebarWidth
    private static let modalInset: CGFloat = Spacing.xxl

    private var availableWidth: CGFloat {
        isSidebarVisible
            ? canvasSize.width - Self.canvasSidebarWidth
            : canvasSize.width
    }

    private var modalOffsetX: CGFloat {
        isSidebarVisible ? Self.canvasSidebarWidth / 2 : 0
    }

    private var isPushedAside: Bool { selectedResult != nil }

    /// Left edge of available area (right of sidebar, or 0 if collapsed).
    private var availableLeadingEdge: CGFloat {
        isSidebarVisible ? Self.canvasSidebarWidth : 0
    }

    /// Detail panel width — fills the right portion of available space.
    private var detailWidth: CGFloat {
        max(availableWidth - Self.modalInset * 2 - SearchPaletteDesign.paletteWidth - Self.detailGap, 300)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Backdrop
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { dismissAll() }

            // Palette — always rendered, stays in its natural position
            // SearchPaletteView has its own GeometryReader and centers itself.
            // We just need to constrain it to the available area right of the sidebar.
            paletteView
                .padding(.leading, availableLeadingEdge)

            // Detail — anchored to the right edge of available space
            if let _ = selectedResult {
                detailPanel
                    .frame(width: detailWidth)
                    .frame(height: detailHeight)
                    .padding(.top, canvasSize.height * SearchPaletteDesign.topOffsetFactor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, Self.modalInset)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .none : .snappy(duration: 0.3), value: isPushedAside)
    }

    // MARK: - Palette

    private var paletteView: some View {
        SearchPaletteView(
            bookmarks: Array(viewModel.bookmarkLookup.values),
            notes: Array(viewModel.noteLookup.values),
            onOpenBookmark: { bookmark in
                selectBookmark(bookmark)
            },
            onOpenNote: { note in
                selectNote(note)
            },
            onOpenDateCard: nil,
            onOpenContact: nil,
            onOpenTodo: { todo in
                selectTodo(todo)
            },
            onSpawnSearchTab: nil,
            onDismiss: { dismissAll() },
            onAction: { _ in
                dismissAll()
            },
            onSelectTag: nil,
            dismissOnResultSelect: false
        )
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var detailPanel: some View {
        if let result = selectedResult {
            VStack(spacing: 0) {
                detailToolbar

                Divider()
                    .background(CiderColors.separator)
                    .padding(.leading, Spacing.md + Spacing.xxs)

                HStack(spacing: 0) {
                    detailHeroColumn(for: result)

                    if result.type == .bookmark, let bookmark = result.bookmark, draft != nil {
                        bookmarkMetadataSidebarView(bookmark: bookmark)
                    } else {
                        simpleMetadataSidebar(for: result)
                    }
                }
            }
            .background {
                ZStack {
                    VisualEffectView(
                        material: .underWindowBackground,
                        blendingMode: .withinWindow
                    )
                    CiderColors.acrylicOverlayTint
                    CiderColors.surfaceSubtle
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                    .allowsHitTesting(false)
            }
            .shadow(color: CiderColors.shadowHeavy, radius: Spacing.xl, y: Spacing.sm)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var detailHeight: CGFloat {
        let target = canvasSize.height * 0.8
        let maxH = canvasSize.height - Spacing.xxl * 2
        return min(max(target, 400), maxH)
    }

    // MARK: - Detail Toolbar

    private var detailToolbar: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
                    closeDetail()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .frame(width: BookmarksDesign.buttonTapTarget, height: BookmarksDesign.buttonTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            if let bookmark = selectedResult?.bookmark {
                detailActions(for: bookmark)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.xxs)
        .padding(.bottom, Spacing.xs + 1)
    }

    private func detailActions(for bookmark: Bookmark) -> some View {
        HStack(spacing: Spacing.xs) {
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

    // MARK: - Detail Hero Column

    private func detailHeroColumn(for result: SearchResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Title
            Text(result.title)
                .font(CiderFont.headingSemibold)
                .foregroundColor(CiderColors.primary)
                .lineLimit(3)
                .textSelection(.enabled)

            // Subtitle
            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            // Thumbnail for bookmarks
            if let bookmark = result.bookmark, let thumbnailURL = bookmark.thumbnailFileURL {
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
            } else if let note = result.note {
                let preview = note.contentPreview
                if !preview.isEmpty {
                    Text(preview)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.lg)
    }

    // MARK: - Bookmark Metadata Sidebar

    @ViewBuilder
    private func bookmarkMetadataSidebarView(bookmark: Bookmark) -> some View {
        if let draftBinding = makeDraftBinding() {
            BookmarkMetadataSidebar(
                draft: draftBinding,
                bookmark: bookmark,
                errorMessage: detailsErrorMessage,
                folders: VaultFolderService.shared.legacyFolders,
                width: BookmarksDesign.detailsSidebarFixedWidth,
                showBackground: false,
                onDelete: {
                    let bm = bookmark
                    closeDetail()
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
                onCancel: { closeDetail() }
            )
            .background(CiderColors.surfaceInput)
            .overlay(alignment: .leading) {
                CiderColors.separator
                    .frame(width: Spacing.hairline)
            }
        }
    }

    // MARK: - Simple Metadata Sidebar (Notes/Todos)

    @ViewBuilder
    private func simpleMetadataSidebar(for result: SearchResult) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if let note = result.note {
                    if let folderID = note.folderID,
                       let folder = VaultFolderService.shared.folder(for: folderID) {
                        metadataRow(icon: "folder", label: "Folder", value: folder.name)
                    }
                    let wordCount = note.wordCount
                    if wordCount > 0 {
                        metadataRow(icon: "textformat.abc", label: "Words", value: "\(wordCount)")
                    }
                    Divider()
                    metadataRow(icon: "calendar", label: "Modified", value: note.modifiedAt.noteCardDate)
                } else if let todo = result.todoCard {
                    if let dueDate = todo.dueDate {
                        metadataRow(icon: "clock", label: "Due", value: dueDate.noteCardDate)
                    }
                    if let folderID = todo.folderID,
                       let folder = VaultFolderService.shared.folder(for: folderID) {
                        metadataRow(icon: "folder", label: "Folder", value: folder.name)
                    }
                    Divider()
                    metadataRow(icon: "calendar", label: "Created", value: todo.createdAt.noteCardDate)
                }
            }
            .padding(Spacing.lg)
        }
        .frame(width: BookmarksDesign.detailsSidebarFixedWidth)
        .frame(maxHeight: .infinity)
        .background(CiderColors.surfaceInput)
        .overlay(alignment: .leading) {
            CiderColors.separator
                .frame(width: Spacing.hairline)
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

    // MARK: - Selection Handlers

    private func selectBookmark(_ bookmark: Bookmark) {
        viewModel.panToItem(bookmark.id.uuidString)
        draft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsErrorMessage = nil
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
            selectedResult = SearchResult(
                id: bookmark.id, type: .bookmark,
                title: bookmark.title, subtitle: bookmark.hostDisplay,
                snippet: nil, date: bookmark.updatedAt,
                bookmark: bookmark
            )
        }
    }

    private func selectNote(_ note: Note) {
        viewModel.panToItem(note.id.uuidString)
        draft = nil
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
            selectedResult = SearchResult(
                id: note.id, type: .note,
                title: note.title, subtitle: nil,
                snippet: nil, date: note.modifiedAt,
                note: note
            )
        }
    }

    private func selectTodo(_ todo: TodoCard) {
        viewModel.panToItem(todo.id.uuidString)
        draft = nil
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.3)) {
            selectedResult = SearchResult(
                id: todo.id, type: .todo,
                title: todo.title, subtitle: nil,
                snippet: nil, date: todo.createdAt,
                todoCard: todo
            )
        }
    }

    // MARK: - Dismiss / Close

    private func closeDetail() {
        saveDraft()
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
            selectedResult = nil
            draft = nil
            detailsErrorMessage = nil
        }
    }

    private func dismissAll() {
        saveDraft()
        withAnimation(reduceMotion ? .none : .snappy(duration: 0.25)) {
            selectedResult = nil
            draft = nil
            detailsErrorMessage = nil
            onDismiss()
        }
    }

    // MARK: - Draft Management

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

    private func saveDraft() {
        guard let draft,
              let bookmark = selectedResult?.bookmark else { return }

        let parsedTags = draft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceURL: String? = draft.sourceURL != draft.originalURLString
            ? draft.sourceURL
            : nil

        VaultBookmarkService.shared.updateDetails(
            for: bookmark.id,
            title: draft.title,
            notes: draft.notes,
            tags: parsedTags,
            labelIDs: draft.labelIDs,
            urlString: sourceURL
        )
    }
}
