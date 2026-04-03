import SwiftUI
import os

private let logger = Logger(subsystem: "com.cider.app", category: "PanelSearchResults")

struct PanelSearchResultsView: View {
    @ObservedObject var coordinator: UtilityPanelCoordinator

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Rectangle()
                .fill(CiderColors.borderSubtle)
                .frame(height: Spacing.hairline)

            if coordinator.searchResults.isEmpty {
                emptyState
            } else {
                resultsList
            }
        }
    }

    // MARK: - Header

    private var searchHeader: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.bodySemibold)
                .foregroundColor(CiderColors.tertiary)

            Text(coordinator.searchQuery.isEmpty ? "Search" : coordinator.searchQuery)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.xs)

            Text("\(coordinator.searchResults.count) results")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(CiderColors.tertiary)
            Text("No results found")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.xs) {
                ForEach(resultSections, id: \.type) { section in
                    PanelSearchSection(
                        type: section.type,
                        results: section.results,
                        coordinator: coordinator
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
        }
    }

    // MARK: - Grouping

    private var resultSections: [ResultSection] {
        let grouped = Dictionary(grouping: coordinator.searchResults, by: \.type)
        let order: [SearchResultType] = [.bookmark, .note, .todo, .dateCard, .contact, .session, .vaultFile]
        return order.compactMap { type in
            guard let results = grouped[type], !results.isEmpty else { return nil }
            return ResultSection(type: type, results: results)
        }
    }
}

// MARK: - Section

private struct ResultSection {
    let type: SearchResultType
    let results: [SearchResult]
}

private struct PanelSearchSection: View {
    let type: SearchResultType
    let results: [SearchResult]
    let coordinator: UtilityPanelCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            sectionHeader
            ForEach(results) { result in
                PanelSearchResultCard(result: result, coordinator: coordinator)
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: iconName)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text(sectionTitle)
                .font(CiderFont.captionSemibold)
                .foregroundColor(CiderColors.tertiary)
            Text("(\(results.count))")
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(.top, Spacing.xs)
    }

    private var sectionTitle: String {
        switch type {
        case .bookmark:  return "Bookmarks"
        case .note:      return "Notes"
        case .todo:      return "Todos"
        case .dateCard:  return "Dates"
        case .contact:   return "Contacts"
        case .session:   return "Sessions"
        case .vaultFile: return "Files"
        }
    }

    private var iconName: String {
        switch type {
        case .bookmark:  return "bookmark"
        case .note:      return "note.text"
        case .dateCard:  return "calendar"
        case .contact:   return "person"
        case .todo:      return "checklist"
        case .session:   return "rectangle.stack"
        case .vaultFile: return "doc"
        }
    }
}

// MARK: - Result Card

private struct PanelSearchResultCard: View {
    let result: SearchResult
    let coordinator: UtilityPanelCoordinator

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            coordinator.openSearchResultAsItem(result)
        } label: {
            cardContent
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(isHovered ? CiderColors.surfaceHover : CiderColors.surfaceSubtle)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(reduceMotion ? .none : .snappy, value: isHovered)
        .onDrag { makeDragProvider() }
    }

    private var cardContent: some View {
        HStack(spacing: Spacing.sm) {
            // Thumbnail for bookmarks
            if let bookmark = result.bookmark, bookmark.thumbnailFileURL != nil {
                BookmarkThumbnailView(bookmark: bookmark, mode: .list)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xs, style: .continuous))
            } else {
                typeIcon
            }

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(result.title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(2)

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

    private var typeIcon: some View {
        Image(systemName: iconName)
            .font(CiderFont.bodyMedium)
            .foregroundColor(CiderColors.controlAccent)
            .frame(width: 40, height: 40)
    }

    private var iconName: String {
        switch result.type {
        case .bookmark:  return "bookmark"
        case .note:      return "note.text"
        case .dateCard:  return "calendar"
        case .contact:   return "person"
        case .todo:      return "checklist"
        case .session:   return "rectangle.stack"
        case .vaultFile: return "doc"
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

    private func makeDragProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        if let bookmark = result.bookmark, let url = bookmark.url {
            provider.registerObject(url as NSURL, visibility: .all)
        } else {
            provider.registerObject(NSString(string: result.title), visibility: .all)
        }
        return provider
    }
}
