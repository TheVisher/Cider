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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            removeButton(itemID: itemID)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func noteRow(_ note: Note, itemID: UUID) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                onOpenNote(note)
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(CiderColors.controlAccent)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(note.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(CiderColors.primary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Spacing.sm)

                    Text(note.modifiedAt.formatted(.relative(presentation: .named)))
                        .font(.system(size: 10))
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
                .fill(Color.white.opacity(0.04))
        )
    }

    private func removeButton(itemID: UUID) -> some View {
        Button {
            projectStorage.removeItem(itemID)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(CiderColors.tertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Remove from project")
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundColor(CiderColors.tertiary)

            Text("No items in this project")
                .font(.system(size: 13))
                .foregroundColor(CiderColors.secondary)

            Text("Add bookmarks and notes from search or by dragging them here.")
                .font(.system(size: 11))
                .foregroundColor(CiderColors.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
