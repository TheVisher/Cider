import SwiftUI

struct UtilityPanelBookmarkDetail: View {
    let bookmarkID: UUID
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @StateObject private var webViewStore = DetailWebViewStore()
    @State private var draft: BookmarkDetailsDraft?
    @State private var errorMessage: String?

    private var bookmark: Bookmark? {
        bookmarksViewModel.bookmarks.first(where: { $0.id == bookmarkID })
    }

    var body: some View {
        Group {
            if let bookmark, let draft = Binding($draft) {
                ScrollView {
                    VStack(spacing: 0) {
                        BookmarkDetailsHeroPreview(
                            bookmark: bookmark,
                            draft: draft.wrappedValue
                        )
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                        .padding(.horizontal, Spacing.md)
                        .padding(.top, Spacing.sm)
                        .padding(.bottom, Spacing.md)

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
                        .padding(.vertical, Spacing.sm)
                    }
                }
            } else {
                PlaceholderMode().contentView
            }
        }
        .onAppear { loadDraft() }
        .onChange(of: bookmarkID) { _, _ in loadDraft() }
    }

    private func loadDraft() {
        guard let bookmark else { return }
        draft = BookmarkDetailsDraft(bookmark: bookmark)
        if bookmark.hasURL, let url = bookmark.url {
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
