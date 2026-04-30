import SwiftUI

typealias CiderFloatingDockAction = @MainActor @Sendable () -> Void
typealias CiderFloatingReanchorAction = @MainActor @Sendable (CiderFloatableSurface) -> Void

struct CiderFloatingItemView: View {
    let surface: CiderFloatableSurface
    var onDock: CiderFloatingDockAction?
    var onReanchor: CiderFloatingReanchorAction?

    @ObservedObject private var bookmarks = VaultBookmarkService.shared
    @ObservedObject private var notes = NotesStorage.shared
    @ObservedObject private var dateCards = DateCardStorage.shared
    @ObservedObject private var contacts = ContactStorage.shared
    @ObservedObject private var todos = TodoCardStorage.shared

    var body: some View {
        Group {
            switch surface {
            case .note(let id):
                if let note = notes.notes.first(where: { $0.id == id }) {
                    FloatingNoteDetail(note: note, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Note not found", surface: surface)
                }
            case .bookmark(let id), .bookmarkMetadata(let id):
                if let bookmark = bookmarks.bookmarks.first(where: { $0.id == id }) {
                    FloatingBookmarkDetail(bookmark: bookmark, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Bookmark not found", surface: surface)
                }
            case .contact(let id):
                if let contact = contacts.contact(for: id) {
                    FloatingContactDetail(contact: contact, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Contact not found", surface: surface)
                }
            case .dateCard(let id):
                if let dateCard = dateCards.dateCard(for: id) {
                    FloatingDateCardDetail(dateCard: dateCard, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Date card not found", surface: surface)
                }
            case .todo(let id):
                if let todo = todos.todoCard(for: id) {
                    FloatingTodoDetail(todo: todo, surface: surface)
                } else {
                    FloatingMissingItemView(title: "Todo not found", surface: surface)
                }
            case .clipboard:
                FloatingMissingItemView(title: "Clipboard opens in its dedicated panel", surface: surface)
            case .aiAssistant:
                FloatingMissingItemView(title: "AI Assistant opens in its dedicated panel", surface: surface)
            case .dropZone:
                FloatingMissingItemView(title: "Drop zone is handled by the drop surface", surface: surface)
            }
        }
        .environment(\.floatingCiderDockAction, onDock)
        .environment(\.floatingCiderReanchorAction, onReanchor)
    }
}

private struct FloatingNoteDetail: View {
    let note: Note
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock
    @StateObject private var viewModel = NotesViewModel()

    var body: some View {
        let presentation = FloatingNoteDetailPresentation(note: note)

        GenericItemDetailPanel(
            title: presentation.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            scrollsContent: presentation.scrollsContent,
            onRenameTitle: renameNote,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            toolbarExtra: {
                if presentation.showsFormattingToolbar {
                    NotesCompactToolbar(viewModel: viewModel)
                }
            },
            trailingExtra: {
                FloatingReanchorButton(surface: surface)
                if presentation.showsMetadataToggle {
                    NotesInfoToggleButton(viewModel: viewModel)
                }
            }
        ) {
            if presentation.usesInlineEditor {
                InlineNoteEditorView(viewModel: viewModel)
            }
        }
        .onAppear(perform: syncSelectedNote)
        .onChange(of: note.id) { _, _ in syncSelectedNote() }
        .onDisappear {
            viewModel.flushSave()
        }
    }

    private func syncSelectedNote() {
        guard viewModel.selectedNote?.id != note.id else { return }
        viewModel.selectNote(note)
    }

    private func renameNote(_ newTitle: String) {
        guard let selected = viewModel.selectedNote ?? NotesStorage.shared.notes.first(where: { $0.id == note.id }) else { return }
        NotesStorage.shared.rename(note: selected, to: newTitle)
    }
}

struct FloatingNoteDetailPresentation: Equatable {
    let title: String
    let usesInlineEditor: Bool
    let showsFormattingToolbar: Bool
    let showsMetadataToggle: Bool
    let scrollsContent: Bool

    init(note: Note) {
        title = note.title.isEmpty ? "Untitled" : note.title
        usesInlineEditor = true
        showsFormattingToolbar = true
        showsMetadataToggle = true
        scrollsContent = false
    }
}

private struct FloatingBookmarkDetail: View {
    let bookmark: Bookmark
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: BookmarkDetailsDraft
    @State private var isMetadataVisible = true

    init(bookmark: Bookmark, surface: CiderFloatableSurface) {
        self.bookmark = bookmark
        self.surface = surface
        _draft = State(initialValue: BookmarkDetailsDraft(bookmark: bookmark))
    }

    var body: some View {
        GenericItemDetailPanel(
            title: bookmark.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            scrollsContent: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: {
                FloatingReanchorButton(surface: surface)

                Button {
                    withAnimation(reduceMotion ? .none : .snappy) {
                        isMetadataVisible.toggle()
                    }
                } label: {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isMetadataVisible ? CiderColors.accentSubtle : CiderColors.separatorSubtle)
                        .frame(width: NotesDesign.toolbarButtonSize, height: NotesDesign.toolbarButtonSize)
                        .overlay {
                            Image(systemName: isMetadataVisible ? "info.circle.fill" : "info.circle")
                                .font(CiderFont.toolbarIcon)
                                .foregroundColor(isMetadataVisible ? CiderColors.controlAccent : CiderColors.secondary)
                        }
                }
                .buttonStyle(.plain)
                .help(isMetadataVisible ? "Hide metadata" : "Show metadata")

                AIDetailActionsButton(
                    bookmarkTitle: bookmark.title,
                    bookmarkURL: bookmark.urlString
                )
            }
        ) {
            FloatingBookmarkDetailContent(
                bookmark: bookmark,
                draft: $draft,
                isMetadataVisible: $isMetadataVisible
            )
        }
        .onChange(of: bookmark.id) { _, _ in
            draft = BookmarkDetailsDraft(bookmark: bookmark)
            isMetadataVisible = true
        }
        .onChange(of: bookmark.updatedAt) { _, _ in
            draft = BookmarkDetailsDraft(bookmark: bookmark)
        }
    }
}

struct FloatingBookmarkDetailMetadata: Equatable {
    let urlString: String
    let url: URL?
    let notes: String?
    let summary: String?
    let tags: [String]
    let folderName: String?
    let createdAt: Date
    let updatedAt: Date
    let metadataUpdatedAt: Date?
    let mediaType: String?
    let relativePath: String?
    let enrichmentStatus: String?
    let colors: [String]

    init(bookmark: Bookmark, folderName: String?) {
        urlString = bookmark.urlString
        url = Self.absoluteURL(from: bookmark.urlString)
        notes = Self.trimmed(bookmark.notes)
        summary = Self.trimmed(bookmark.aiSummary ?? "")
        tags = bookmark.tags
        self.folderName = Self.trimmed(folderName ?? "")
        createdAt = bookmark.createdAt
        updatedAt = bookmark.updatedAt
        metadataUpdatedAt = bookmark.metadataUpdatedAt
        mediaType = bookmark.mediaType.map { Self.mediaTypeLabel($0) }
        relativePath = Self.trimmed(bookmark.relativePath ?? "")
        enrichmentStatus = Self.trimmed(bookmark.enrichmentStatus ?? "")
        colors = (bookmark.dominantColors ?? []).filter { Self.trimmed($0) != nil }
    }

    private static func trimmed(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func absoluteURL(from value: String) -> URL? {
        guard let url = URL(string: value),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    private static func mediaTypeLabel(_ mediaType: BookmarkMediaType) -> String {
        switch mediaType {
        case .image: "Image"
        case .gif: "GIF"
        case .video: "Video"
        }
    }
}

private struct FloatingBookmarkDetailContent: View {
    let bookmark: Bookmark
    @Binding var draft: BookmarkDetailsDraft
    @Binding var isMetadataVisible: Bool

    var body: some View {
        GeometryReader { proxy in
            switch FloatingBookmarkDetailLayout.mode(for: proxy.size.width) {
            case .sideRail:
                HStack(alignment: .top, spacing: 0) {
                    previewStage
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if isMetadataVisible {
                        metadataSidebar
                            .background(CiderColors.surfaceInput)
                            .overlay(alignment: .leading) {
                                CiderColors.separator
                                    .frame(width: Spacing.hairline)
                            }
                            .transition(
                                .detailSlideOutSidebar(
                                    style: DetailSlideOutMotionPolicy.sidebarTransitionStyle()
                                )
                            )
                    }
                }

            case .stacked:
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        previewStage
                            .frame(minHeight: FloatingBookmarkDetailLayout.compactPreviewMinHeight)

                        if isMetadataVisible {
                            metadataSidebar
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(Spacing.md)
                }
            }
        }
    }

    private var previewStage: some View {
        BookmarkDetailsHeroPreview(bookmark: bookmark, draft: draft)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.lg)
    }

    private var metadataSidebar: some View {
        BookmarkMetadataSidebar(
            draft: $draft,
            bookmark: bookmark,
            errorMessage: nil,
            folders: VaultFolderService.shared.legacyFolders,
            width: FloatingBookmarkDetailLayout.metadataSidebarWidth,
            showBackground: false,
            onDelete: nil,
            onFolderChanged: assignFolder,
            onOpenURL: openURL,
            onCopyURL: copyURL,
            onSave: saveDraft,
            onCancel: {}
        )
    }

    private func openURL() {
        guard let url = URL(string: draft.sourceURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(draft.sourceURL, forType: .string)
    }

    private func saveDraft() {
        let parsedTags = draft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceURL: String? = draft.sourceURL != draft.originalURLString
            ? draft.sourceURL
            : nil

        _ = VaultBookmarkService.shared.updateDetails(
            for: bookmark.id,
            title: draft.title,
            notes: draft.notes,
            tags: parsedTags,
            labelIDs: draft.labelIDs,
            urlString: sourceURL
        )
    }

    private func assignFolder(_ folderID: UUID?) {
        _ = VaultBookmarkService.shared.assignBookmark(bookmark.id, toFolder: folderID)
    }
}

struct FloatingBookmarkDetailLayout {
    enum Mode {
        case sideRail
        case stacked
    }

    static let metadataSidebarWidth = BookmarksDesign.detailsSidebarFixedWidth
    static let compactPreviewMinHeight: CGFloat = 300
    static let sideRailMinimumWidth: CGFloat = 760

    static func mode(for width: CGFloat) -> Mode {
        width >= sideRailMinimumWidth ? .sideRail : .stacked
    }
}

private struct FloatingContactDetail: View {
    let contact: ContactCard
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: contact.displayName,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: {
                FloatingReanchorButton(surface: surface)
                AIDetailActionsButton(contactName: contact.displayName)
            }
        ) {
            ContactDetailView(contact: contact, onDismiss: { dock(surface, action: onDock) })
        }
    }
}

private struct FloatingDateCardDetail: View {
    let dateCard: DateCard
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: dateCard.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: {
                FloatingReanchorButton(surface: surface)
                AIDetailActionsButton(eventTitle: dateCard.title)
            }
        ) {
            DateCardDetailView(dateCard: dateCard, onDismiss: { dock(surface, action: onDock) })
        }
    }
}

private struct FloatingTodoDetail: View {
    let todo: TodoCard
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: todo.title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: {
                FloatingReanchorButton(surface: surface)
                AIDetailActionsButton(todoTitle: todo.title)
            }
        ) {
            TodoDetailView(todoCard: todo, onDismiss: { dock(surface, action: onDock) })
        }
    }
}

private struct FloatingMissingItemView: View {
    let title: String
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderDockAction) private var onDock

    var body: some View {
        GenericItemDetailPanel(
            title: title,
            detailViewMode: .slideOut,
            showDragHandle: false,
            onClose: { dock(surface, action: onDock) },
            onModeChange: { _ in },
            trailingExtra: {
                if CiderReanchorSurfaceResolver.canOpenInMainWindow(surface) {
                    FloatingReanchorButton(surface: surface)
                }
            }
        ) {
            Text(title)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct FloatingDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text(value)
                .font(CiderFont.body)
                .foregroundColor(CiderColors.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct FloatingReanchorButton: View {
    let surface: CiderFloatableSurface
    @Environment(\.floatingCiderReanchorAction) private var onReanchor

    var body: some View {
        Button {
            if let onReanchor {
                onReanchor(surface)
            } else {
                reanchor(surface)
            }
        } label: {
            Image(systemName: "rectangle.arrowtriangle.2.inward")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.secondary)
                .frame(width: DetailToolbarDesign.iconButtonSize, height: DetailToolbarDesign.iconButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show in Cider")
    }
}

@MainActor
private func dock(_ surface: CiderFloatableSurface, action: CiderFloatingDockAction?) {
    if let action {
        action()
    } else {
        NotificationCenter.default.post(name: .dockCiderSurface, object: surface)
    }
}

@MainActor
private func reanchor(_ surface: CiderFloatableSurface) {
    NotificationCenter.default.post(
        name: .reanchorCiderSurface,
        object: surface,
        userInfo: [CiderFloatingPanelManager.surfaceUserInfoKey: surface]
    )
}

private struct FloatingCiderDockActionKey: EnvironmentKey {
    static let defaultValue: CiderFloatingDockAction? = nil
}

private struct FloatingCiderReanchorActionKey: EnvironmentKey {
    static let defaultValue: CiderFloatingReanchorAction? = nil
}

private extension EnvironmentValues {
    var floatingCiderDockAction: CiderFloatingDockAction? {
        get { self[FloatingCiderDockActionKey.self] }
        set { self[FloatingCiderDockActionKey.self] = newValue }
    }

    var floatingCiderReanchorAction: CiderFloatingReanchorAction? {
        get { self[FloatingCiderReanchorActionKey.self] }
        set { self[FloatingCiderReanchorActionKey.self] = newValue }
    }
}
