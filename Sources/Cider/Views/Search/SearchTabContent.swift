import SwiftUI

struct SearchTabContent: View {
    let query: String
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void
    var onOpenDateCard: ((DateCard) -> Void)? = nil
    var onOpenContact: ((ContactCard) -> Void)? = nil
    var onOpenTodo: ((TodoCard) -> Void)? = nil

    @State private var results: [SearchResult] = []

    private var bookmarkResults: [SearchResult] {
        results.filter { $0.type == .bookmark }
    }

    private var noteResults: [SearchResult] {
        results.filter { $0.type == .note }
    }

    private var dateCardResults: [SearchResult] {
        results.filter { $0.type == .dateCard }
    }

    private var contactResults: [SearchResult] {
        results.filter { $0.type == .contact }
    }

    var body: some View {
        Group {
        if results.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
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

                    if !dateCardResults.isEmpty {
                        resultsSection(
                            title: "Date Cards",
                            icon: "calendar",
                            results: dateCardResults
                        )
                    }

                    if !contactResults.isEmpty {
                        resultsSection(
                            title: "Contacts",
                            icon: "person",
                            results: contactResults
                        )
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.md)
            }
        }
        }
        .task(id: query) {
            results = await SearchService.search(query: query, bookmarks: bookmarks, notes: notes)
        }
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
            case .dateCard:
                if let dateCard = result.dateCard {
                    onOpenDateCard?(dateCard)
                }
            case .contact:
                if let contact = result.contact {
                    onOpenContact?(contact)
                }
            case .todo:
                if let todoCard = result.todoCard {
                    onOpenTodo?(todoCard)
                }
            case .session:
                break
            }
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName(for: result.type))
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(result.title)
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.primary)
                        .lineLimit(1)

                    if let snippet = result.snippet {
                        Text(snippetAttributedString(snippet))
                            .font(CiderFont.body)
                            .lineLimit(1)
                    } else if let subtitle = result.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(CiderFont.body)
                            .foregroundColor(CiderColors.tertiary)
                            .lineLimit(1)
                    }
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

    private func iconName(for type: SearchResultType) -> String {
        switch type {
        case .bookmark:  return "bookmark"
        case .note:      return "note.text"
        case .dateCard:  return "calendar"
        case .contact:   return "person"
        case .todo:      return "checklist"
        case .session:   return "rectangle.stack"
        }
    }

    private func snippetAttributedString(_ snippet: SearchSnippet) -> AttributedString {
        var prefix = AttributedString(snippet.prefix)
        prefix.swiftUI.foregroundColor = CiderColors.tertiary
        var match = AttributedString(snippet.match)
        match.swiftUI.foregroundColor = CiderColors.primary
        var suffix = AttributedString(snippet.suffix)
        suffix.swiftUI.foregroundColor = CiderColors.tertiary
        return prefix + match + suffix
    }

    private var emptyState: some View {
        EmptyStateView(icon: "magnifyingglass", title: "No results for \"\(query)\"")
    }
}
