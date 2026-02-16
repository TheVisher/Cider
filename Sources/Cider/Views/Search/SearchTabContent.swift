import SwiftUI

struct SearchTabContent: View {
    let query: String
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void
    var onSaveAsProject: ((String, [SearchResult]) -> Void)?

    private var results: [SearchResult] {
        SearchService.search(query: query, bookmarks: bookmarks, notes: notes)
    }

    private var bookmarkResults: [SearchResult] {
        results.filter { $0.type == .bookmark }
    }

    private var noteResults: [SearchResult] {
        results.filter { $0.type == .note }
    }

    var body: some View {
        if results.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if onSaveAsProject != nil {
                        saveAsProjectBar
                    }

                    if !bookmarkResults.isEmpty {
                        resultsSection(
                            title: "Bookmarks",
                            icon: "bookmark",
                            results: bookmarkResults
                        )
                    }

                    if !noteResults.isEmpty {
                        resultsSection(
                            title: "Notes",
                            icon: "note.text",
                            results: noteResults
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
    }

    private var saveAsProjectBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "tray.full")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)

            Text("\(results.count) results")
                .font(CiderFont.label)
                .foregroundColor(CiderColors.secondary)

            Spacer()

            Button {
                let projectName = query.isEmpty ? "Search Results" : query
                onSaveAsProject?(projectName, results)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(CiderFont.bodyMedium)
                    Text("Save as Project")
                        .font(CiderFont.labelMedium)
                }
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.accentLight)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(CiderColors.surfaceSubtle)
        )
    }

    private func resultsSection(title: String, icon: String, results: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text(title)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(results.count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }

            ForEach(results) { result in
                resultRow(result)
            }
        }
    }

    private func resultRow(_ result: SearchResult) -> some View {
        Button {
            switch result.type {
            case .bookmark:
                if let bookmark = result.bookmark {
                    onOpenBookmark(bookmark)
                }
            case .note:
                if let note = result.note {
                    onOpenNote(note)
                }
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: result.type == .bookmark ? "bookmark" : "note.text")
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                Text(result.date.formatted(.relative(presentation: .named)))
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
        EmptyStateView(icon: "magnifyingglass", title: "No results for \"\(query)\"")
    }
}
