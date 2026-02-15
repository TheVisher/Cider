import SwiftUI

struct HomeDashboardView: View {
    @ObservedObject var bookmarksViewModel: BookmarksViewModel
    @ObservedObject var notesViewModel: NotesViewModel

    private var recentBookmarks: [Bookmark] {
        Array(
            bookmarksViewModel.bookmarks
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(6)
        )
    }

    private var recentNotes: [Note] {
        Array(
            notesViewModel.notes
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(6)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                statsRow

                quickActions

                if !recentBookmarks.isEmpty {
                    recentBookmarksSection
                }

                if !recentNotes.isEmpty {
                    recentNotesSection
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: Spacing.md) {
            statCard(
                icon: "bookmark.fill",
                label: "Bookmarks",
                count: bookmarksViewModel.bookmarks.count
            )
            statCard(
                icon: "note.text",
                label: "Notes",
                count: notesViewModel.notes.count
            )
        }
    }

    private func statCard(icon: String, label: String, count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(CiderColors.controlAccent)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("\(count)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(CiderColors.primary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(CiderColors.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(CiderColors.separator.opacity(0.2))
        )
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Quick Actions")

            HStack(spacing: Spacing.sm) {
                quickActionButton(
                    icon: "safari",
                    label: "Capture Tab",
                    action: {
                        bookmarksViewModel.captureBookmarkFromActiveBrowserOrClipboard()
                    }
                )
                quickActionButton(
                    icon: "plus",
                    label: "New Note",
                    action: {
                        notesViewModel.createNewNote()
                        if let note = notesViewModel.selectedNote {
                            NotificationCenter.default.post(name: .openNoteInPanel, object: note)
                        }
                    }
                )
                quickActionButton(
                    icon: "doc.on.clipboard",
                    label: "Paste URL",
                    action: {
                        bookmarksViewModel.addBookmarkFromPasteboard()
                    }
                )
            }
        }
    }

    private func quickActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(CiderColors.controlAccent)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CiderColors.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(CiderColors.separator.opacity(0.18))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent Bookmarks

    private var recentBookmarksSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Recent Bookmarks")

            LazyVStack(spacing: Spacing.xxs) {
                ForEach(recentBookmarks) { bookmark in
                    recentBookmarkRow(bookmark)
                }
            }
        }
    }

    private func recentBookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            bookmarksViewModel.open(bookmark)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "bookmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(bookmark.hostDisplay)
                        .font(.system(size: 10))
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
    }

    // MARK: - Recent Notes

    private var recentNotesSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionHeader("Recent Notes")

            LazyVStack(spacing: Spacing.xxs) {
                ForEach(recentNotes) { note in
                    recentNoteRow(note)
                }
            }
        }
    }

    private func recentNoteRow(_ note: Note) -> some View {
        Button {
            NotificationCenter.default.post(name: .openNoteInPanel, object: note)
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "note.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.tertiary)
                    .frame(width: 16)

                Text(note.title)
                    .font(.system(size: 12, weight: .medium))
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
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(CiderColors.tertiary)
            .textCase(.uppercase)
    }
}
