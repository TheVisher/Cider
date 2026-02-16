import SwiftUI

struct ProjectTabContent: View {
    let projectID: UUID
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void

    @ObservedObject private var projectStorage = ProjectStorage.shared

    private var projectItems: [ProjectItem] {
        projectStorage.itemsForProject(projectID)
    }

    private var project: Project? {
        projectStorage.project(for: projectID)
    }

    var body: some View {
        if projectItems.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(projectItems) { item in
                        projectItemRow(item)
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    @ViewBuilder
    private func projectItemRow(_ item: ProjectItem) -> some View {
        if let bookmarkID = item.bookmarkID,
           let bookmark = bookmarks.first(where: { $0.id == bookmarkID }) {
            bookmarkRow(bookmark, itemID: item.id)
        } else if let noteID = item.noteID,
                  let note = notes.first(where: { $0.id == noteID }) {
            noteRow(note, itemID: item.id)
        }
    }

    private func bookmarkRow(_ bookmark: Bookmark, itemID: UUID) -> some View {
        HStack(spacing: Spacing.sm) {
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

                        Text(bookmark.hostDisplay)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Text(bookmark.updatedAt.formatted(.relative(presentation: .named)))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            removeButton(itemID: itemID)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func noteRow(_ note: Note, itemID: UUID) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                onOpenNote(note)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "note.text")
                        .font(CiderFont.bodyMedium)
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(CiderFont.subheadingMedium)
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(CiderFont.caption)
                        .foregroundColor(CiderColors.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            removeButton(itemID: itemID)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func removeButton(itemID: UUID) -> some View {
        Button {
            projectStorage.removeItem(itemID)
        } label: {
            Image(systemName: "xmark")
                .font(CiderFont.microBold)
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Remove from project")
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: "tray",
            title: "No items in this project",
            subtitle: "Add bookmarks and notes from search or by dragging them here."
        )
    }
}
