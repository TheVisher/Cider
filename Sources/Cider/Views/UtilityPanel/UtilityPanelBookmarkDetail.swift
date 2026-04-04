import SwiftUI

struct UtilityPanelBookmarkDetail: View {
    let bookmarkID: UUID
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    var compact: Bool = false
    @StateObject private var webViewStore = DetailWebViewStore()
    @State private var draft: BookmarkDetailsDraft?
    @State private var errorMessage: String?

    private var bookmark: Bookmark? {
        bookmarksViewModel.bookmarks.first(where: { $0.id == bookmarkID })
    }

    var body: some View {
        if compact {
            Group {
                if let bookmark, let draft = Binding($draft) {
                    ScrollView {
                        VStack(spacing: 0) {
                            BookmarkDetailsHeroPreview(
                                bookmark: bookmark,
                                draft: draft.wrappedValue
                            )
                            .frame(height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                            .padding(.horizontal, Spacing.md)
                            .padding(.top, Spacing.sm)
                            .padding(.bottom, Spacing.sm)

                            BookmarkMetadataSidebar(
                                draft: draft,
                                bookmark: bookmark,
                                errorMessage: errorMessage,
                                folders: bookmarksViewModel.folders,
                                width: .infinity,
                                showBackground: false,
                                onDelete: nil,
                                onFolderChanged: { folderID in
                                    self.draft?.folderID = folderID
                                    saveDetails()
                                },
                                onOpenURL: {
                                    if let url = bookmark.url {
                                        NSWorkspace.shared.open(url)
                                    }
                                },
                                onCopyURL: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(bookmark.urlString, forType: .string)
                                },
                                onSave: { saveDetails() },
                                onCancel: { loadDraft() }
                            )
                            .padding(.horizontal, Spacing.md)
                        }
                    }
                } else {
                    PlaceholderMode().contentView
                }
            }
            .onAppear { loadDraft() }
            .onChange(of: bookmarkID) { _, _ in loadDraft() }
        } else {
            Group {
                if let bookmark, let draft = Binding($draft) {
                    HStack(alignment: .top, spacing: 0) {
                        // Hero image (left)
                        BookmarkDetailsHeroPreview(
                            bookmark: bookmark,
                            draft: draft.wrappedValue
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .padding(Spacing.md)

                        // Metadata sidebar (right, fixed width, scrollable)
                        ScrollView {
                            BookmarkMetadataSidebar(
                                draft: draft,
                                bookmark: bookmark,
                                errorMessage: errorMessage,
                                folders: bookmarksViewModel.folders,
                                width: BookmarksDesign.detailsSidebarFixedWidth,
                                showBackground: false,
                                onDelete: nil,
                                onFolderChanged: { folderID in
                                    self.draft?.folderID = folderID
                                    saveDetails()
                                },
                                onOpenURL: {
                                    if let url = bookmark.url {
                                        NSWorkspace.shared.open(url)
                                    }
                                },
                                onCopyURL: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(bookmark.urlString, forType: .string)
                                },
                                onSave: { saveDetails() },
                                onCancel: { loadDraft() }
                            )
                            .padding(.vertical, Spacing.sm)
                        }
                        .frame(width: BookmarksDesign.detailsSidebarFixedWidth)
                    }
                } else {
                    PlaceholderMode().contentView
                }
            }
            .onAppear { loadDraft() }
            .onChange(of: bookmarkID) { _, _ in loadDraft() }
        }
    }

    private func loadDraft() {
        guard let bookmark else { return }
        draft = BookmarkDetailsDraft(bookmark: bookmark)
        if !compact, bookmark.hasURL, let url = bookmark.url {
            webViewStore.preload(url: url, bookmarkID: bookmark.id)
        }
    }

    private func saveDetails() {
        guard let draft, let bookmark else { return }

        let parsedTags = draft.tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let sourceURL: String? = draft.sourceURL != draft.originalURLString
            ? draft.sourceURL
            : nil

        let didSave = bookmarksViewModel.updateDetails(
            for: bookmark,
            title: draft.title,
            notes: draft.notes,
            tags: parsedTags,
            labelIDs: draft.labelIDs,
            urlString: sourceURL
        )

        if !didSave {
            errorMessage = "Could not save bookmark details."
        }
    }
}
