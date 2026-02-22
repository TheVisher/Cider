import SwiftUI
import AppKit

struct BookmarksTabContent: View {
    @ObservedObject var viewModel: BookmarksViewModel
    var selectedFolderID: UUID?
    @Binding var selectedItemIDs: Set<String>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var panelWindow: NSWindow?
    @State private var detailsDraft: BookmarkDetailsDraft?
    @State private var detailsPresentationMode: DetailModalMode?
    @State private var detailsErrorMessage: String?

    private var displayedBookmarks: [Bookmark] {
        guard let selectedFolderID else { return viewModel.filteredBookmarks }
        return viewModel.filteredBookmarks.filter { $0.folderID == selectedFolderID }
    }

    private var selectedDetailsBookmark: Bookmark? {
        guard let detailsDraft else { return nil }
        return viewModel.bookmarks.first(where: { $0.id == detailsDraft.id })
    }

    private var isExpandMode: Bool {
        (detailsPresentationMode ?? CiderConfig.load().detailModalMode) == .expand
    }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Spacing.md) {
                BookmarksBrowserView(
                    bookmarks: displayedBookmarks,
                    folders: viewModel.folders,
                    displayMode: Binding(
                        get: { viewModel.displayMode },
                        set: { viewModel.setDisplayMode($0) }
                    ),
                    cardSizeScale: Binding(
                        get: { viewModel.cardSizeScale },
                        set: { viewModel.setCardSizeScale($0) }
                    ),
                    selectedItemIDs: $selectedItemIDs,
                    onOpenBookmark: {
                        clearSearchFocus()
                        viewModel.open($0)
                    },
                    onShowBookmarkDetails: { presentDetails(for: $0) },
                    onDeleteBookmark: {
                        clearSearchFocus()
                        viewModel.delete($0)
                    },
                    onAddBookmark: { viewModel.addBookmark(urlString: $0, title: $1) },
                    onAssignBookmarkToFolder: { viewModel.assign($0, toFolder: $1) },
                    onCreateFolder: { viewModel.createFolder(name: $0, parentID: $1) },
                    showsInternalFolderSidebar: false
                )
            }
            .blur(radius: (isExpandMode && detailsDraft != nil) ? BookmarksDesign.detailsContentBlurRadius : 0)
            .animation(reduceMotion ? .none : .snappy, value: detailsDraft != nil)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)

            if isExpandMode && detailsDraft != nil {
                detailsOverlay
            }
        }
        .background(
            BookmarksTabWindowAccessor(window: $panelWindow)
        )
        .onChange(of: viewModel.bookmarks.map(\.id)) { _, bookmarkIDs in
            guard let detailsDraft else { return }
            if !bookmarkIDs.contains(detailsDraft.id) {
                closeDetails()
            }
        }
        .onDisappear {
            if detailsDraft != nil {
                closeDetails()
            }
        }
        .task(id: viewModel.pendingDetailBookmarkID) {
            guard let bookmarkID = viewModel.pendingDetailBookmarkID,
                  let bookmark = viewModel.bookmarks.first(where: { $0.id == bookmarkID }) else { return }
            viewModel.pendingDetailBookmarkID = nil
            presentDetails(for: bookmark)
        }
    }

    // MARK: - Details Overlay

    @ViewBuilder
    private var detailsOverlay: some View {
        if let draft = detailsDraft {
            let draftBinding = Binding(
                get: { self.detailsDraft ?? draft },
                set: { next in
                    self.detailsDraft = next
                    detailsErrorMessage = nil
                }
            )

            GeometryReader { proxy in
                let sheetWidth = resolvedDetailsSheetWidth(for: proxy.size.width)
                let sheetHeight = resolvedDetailsSheetHeight(for: proxy.size.height)

                ZStack {
                    CiderColors.backdropSubtle
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeDetails()
                        }

                    BookmarkDetailsSheet(
                        draft: draftBinding,
                        bookmark: selectedDetailsBookmark,
                        errorMessage: detailsErrorMessage,
                        folders: viewModel.folders,
                        onDelete: { deleteDetailsBookmark() },
                        onFolderChanged: { assignDetailsBookmarkToFolder($0) },
                        onOpenURL: openDetailsURL,
                        onCopyURL: copyDetailsURL,
                        onSave: saveDetails,
                        onCancel: { closeDetails() }
                    )
                    .frame(width: sheetWidth)
                    .frame(maxHeight: sheetHeight)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.xxl)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .transition(.opacity)
        }
    }

    private func presentDetails(for bookmark: Bookmark) {
        clearSearchFocus()
        let draft = BookmarkDetailsDraft(bookmark: bookmark)
        detailsDraft = draft
        detailsErrorMessage = nil

        let presentationMode = CiderConfig.load().detailModalMode
        detailsPresentationMode = presentationMode

        if presentationMode == .popover {
            showDetailsPopover(draft: draft)
        } else {
            requestPanelExpansionForDetails()
        }
    }

    private func closeDetails() {
        clearSearchFocus()
        let presentationMode = detailsPresentationMode ?? CiderConfig.load().detailModalMode
        if presentationMode == .popover {
            NotificationCenter.default.post(name: .dismissDetailPopover, object: nil)
        } else {
            requestPanelRestoreAfterDetails()
        }
        detailsPresentationMode = nil
        detailsDraft = nil
        detailsErrorMessage = nil
    }

    private func showDetailsPopover(draft: BookmarkDetailsDraft) {
        let draftBinding = Binding<BookmarkDetailsDraft>(
            get: { self.detailsDraft ?? draft },
            set: { next in
                self.detailsDraft = next
                self.detailsErrorMessage = nil
            }
        )

        let popoverContent = AnyView(
            BookmarkDetailsSheet(
                draft: draftBinding,
                bookmark: selectedDetailsBookmark,
                errorMessage: detailsErrorMessage,
                folders: viewModel.folders,
                onDelete: { deleteDetailsBookmark() },
                onFolderChanged: { assignDetailsBookmarkToFolder($0) },
                onOpenURL: openDetailsURL,
                onCopyURL: copyDetailsURL,
                onSave: saveDetails,
                onCancel: { closeDetails() }
            )
            .padding(Spacing.xl)
        )

        NotificationCenter.default.post(
            name: .showDetailPopover,
            object: nil,
            userInfo: [
                "view": popoverContent,
                "preferredWidth": BookmarksDesign.detailsRequiredPanelWidth,
            ]
        )
    }

    private func requestPanelExpansionForDetails() {
        NotificationCenter.default.post(
            name: .expandCiderPanelForDetailModal,
            object: nil,
            userInfo: ["minimumWidth": BookmarksDesign.detailsRequiredPanelWidth]
        )
    }

    private func requestPanelRestoreAfterDetails() {
        NotificationCenter.default.post(name: .restoreCiderPanelAfterDetailModal, object: nil)
    }

    private func saveDetails() {
        guard let detailsDraft else { return }
        guard let selectedBookmark = selectedDetailsBookmark else {
            detailsErrorMessage = "This bookmark is no longer available."
            return
        }

        let parsedTags = detailsDraft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let didSave = viewModel.updateDetails(
            for: selectedBookmark,
            title: detailsDraft.title,
            notes: detailsDraft.notes,
            tags: parsedTags
        )

        if didSave {
            closeDetails()
        } else {
            detailsErrorMessage = "Could not save bookmark details."
        }
    }

    private func deleteDetailsBookmark() {
        guard let bookmark = selectedDetailsBookmark else { return }
        closeDetails()
        viewModel.deleteBookmarks([bookmark])
    }

    private func assignDetailsBookmarkToFolder(_ folderID: UUID?) {
        guard let bookmark = selectedDetailsBookmark else { return }
        _ = viewModel.assign(bookmark, toFolder: folderID)
    }

    private func copyDetailsURL() {
        guard let detailsDraft else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(detailsDraft.urlString, forType: .string)
    }

    private func openDetailsURL() {
        guard let detailsDraft,
              let url = URL(string: detailsDraft.urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func clearSearchFocus() {
        panelWindow?.makeFirstResponder(nil)
    }

    private func resolvedDetailsSheetWidth(for containerWidth: CGFloat) -> CGFloat {
        let horizontalInset = Spacing.xxxl * 2
        let availableWidth = max(containerWidth - horizontalInset, 1)
        let minimumWidth = min(BookmarksDesign.detailsSheetMinWidth, availableWidth)
        let preferredWidth = max(minimumWidth, availableWidth * BookmarksDesign.detailsSheetPreferredWidthRatio)
        return min(preferredWidth, BookmarksDesign.detailsSheetMaxWidth)
    }

    private func resolvedDetailsSheetHeight(for containerHeight: CGFloat) -> CGFloat {
        let verticalInset = Spacing.xxxl * 2
        let availableHeight = max(containerHeight - verticalInset, 1)
        let minimumHeight = min(BookmarksDesign.detailsSheetMinHeight, availableHeight)
        let preferredHeight = max(minimumHeight, availableHeight * BookmarksDesign.detailsSheetPreferredHeightRatio)
        return min(preferredHeight, BookmarksDesign.detailsSheetMaxHeight)
    }
}

// MARK: - Window Accessor

private struct BookmarksTabWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if window !== view.window {
                window = view.window
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if window !== nsView.window {
                window = nsView.window
            }
        }
    }
}
