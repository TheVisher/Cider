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
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(CiderColors.controlAccent)

            Text("\(results.count) results")
                .font(.system(size: 12))
                .foregroundColor(CiderColors.secondary)

            Spacer()

            Button {
                let projectName = query.isEmpty ? "Search Results" : query
                onSaveAsProject?(projectName, results)
            } label: {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "plus.rectangle.on.folder")
                        .font(.system(size: 11, weight: .medium))
                    Text("Save as Project")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.12))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func resultsSection(title: String, icon: String, results: [SearchResult]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)

                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(results.count)")
                    .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    Text(result.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: Spacing.sm)

                Text(result.date.formatted(.relative(presentation: .named)))
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
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundColor(CiderColors.tertiary)

            Text("No results for \"\(query)\"")
                .font(.system(size: 13))
                .foregroundColor(CiderColors.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
