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
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var folderNotes: [Note] {
        notes
            .filter { $0.folderID == folderID }
            .sorted { $0.modifiedAt > $1.modifiedAt }
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(bookmark.hostDisplay)
                        .font(.system(size: 11))
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func noteRow(_ note: Note) -> some View {
        Button {
            onOpenNote(note)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "note.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                Text(note.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                Spacer(minLength: Spacing.sm)

                Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10))
                    .foregroundColor(CiderColors.quaternary)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundColor(CiderColors.tertiary)

            Text("This folder is empty")
                .font(.system(size: 13))
                .foregroundColor(CiderColors.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
