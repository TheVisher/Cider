import SwiftUI

struct RootFolderOverviewView: View {
    let folderID: UUID
    let folders: [Folder]
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void
    let onSelectSubFolder: (UUID) -> Void

    private var childFolders: [Folder] {
        folders
            .filter { $0.parentID == folderID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var unsortedBookmarks: [Bookmark] {
        bookmarks
            .filter { $0.folderID == folderID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var unsortedNotes: [Note] {
        notes
            .filter { $0.folderID == folderID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var hasUnsortedItems: Bool {
        !unsortedBookmarks.isEmpty || !unsortedNotes.isEmpty
    }

    var body: some View {
        if childFolders.isEmpty && !hasUnsortedItems {
            emptyState
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    if !childFolders.isEmpty {
                        subFolderCards
                    }

                    if hasUnsortedItems {
                        unsortedSection
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    // MARK: - Sub-Folder Cards

    private var subFolderCards: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "folder")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("Sub Folders")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(childFolders.count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 200), spacing: Spacing.sm)],
                spacing: Spacing.sm
            ) {
                ForEach(childFolders) { folder in
                    folderCard(folder)
                }
            }
        }
    }

    private func folderCard(_ folder: Folder) -> some View {
        let bookmarkCount = bookmarks.filter { $0.folderID == folder.id }.count
        let noteCount = notes.filter { $0.folderID == folder.id }.count
        let totalItems = bookmarkCount + noteCount

        return Button {
            onSelectSubFolder(folder.id)
        } label: {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "folder.fill")
                        .font(CiderFont.display)
                        .foregroundColor(CiderColors.controlAccent)

                    Spacer()

                    if totalItems > 0 {
                        Text("\(totalItems)")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.tertiary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                Capsule()
                                    .fill(CiderColors.surfaceInput)
                            )
                    }
                }

                Text(folder.name)
                    .font(CiderFont.labelMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

                HStack(spacing: Spacing.sm) {
                    if bookmarkCount > 0 {
                        Label("\(bookmarkCount)", systemImage: "bookmark")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                    if noteCount > 0 {
                        Label("\(noteCount)", systemImage: "note.text")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                    if totalItems == 0 {
                        Text("Empty")
                            .font(CiderFont.caption)
                            .foregroundColor(CiderColors.quaternary)
                    }
                }
            }
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .sectionContainer()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Unsorted Section

    private var unsortedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tray")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("Unsorted")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(unsortedBookmarks.count + unsortedNotes.count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }

            ForEach(unsortedBookmarks) { bookmark in
                bookmarkRow(bookmark)
            }

            ForEach(unsortedNotes) { note in
                noteRow(note)
            }
        }
    }

    // MARK: - Item Rows

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

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "folder",
            title: "This folder is empty",
            subtitle: "Add sub folders or drop items here"
        )
    }
}
