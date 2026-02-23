import SwiftUI

struct FolderContentView: View {
    let folderID: UUID
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void

    private var folderBookmarks: [Bookmark] {
        bookmarks
            .filter { $0.folderID == folderID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var folderNotes: [Note] {
        notes
            .filter { $0.folderID == folderID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        if folderBookmarks.isEmpty && folderNotes.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if !folderBookmarks.isEmpty {
                        itemSection(title: "Bookmarks", icon: "bookmark", count: folderBookmarks.count) {
                            ForEach(folderBookmarks) { bookmark in
                                bookmarkRow(bookmark)
                            }
                        }
                    }

                    if !folderNotes.isEmpty {
                        itemSection(title: "Notes", icon: "note.text", count: folderNotes.count) {
                            ForEach(folderNotes) { note in
                                noteRow(note)
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private func itemSection<Content: View>(
        title: String, icon: String, count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text(title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }

            content()
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            onOpenBookmark(bookmark)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bookmark")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.title)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    if bookmark.hasURL {
                        Text(bookmark.hostDisplay)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: Spacing.sm)

                Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            onOpenNote(note)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "note.text")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                Text(note.title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(CiderFont.caption)
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private var emptyState: some View {
        EmptyStateView(icon: "folder", title: "This folder is empty")
    }
}
