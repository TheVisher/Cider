import SwiftUI

struct SearchPaletteView: View {
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void
    let onSpawnSearchTab: ((String) -> Void)?
    let onDismiss: () -> Void

    @State private var query = ""
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var results: [SearchResult] {
        SearchService.search(query: query, bookmarks: bookmarks, notes: notes)
    }

    private var bookmarkResults: [SearchResult] {
        results.filter { $0.type == .bookmark }
    }

    private var noteResults: [SearchResult] {
        results.filter { $0.type == .note }
    }

    private var hasResults: Bool {
        !results.isEmpty
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var recentBookmarks: [Bookmark] {
        Array(
            bookmarks
                .sorted { $0.updatedAt > $1.updatedAt }
                .prefix(SearchPaletteDesign.recentBookmarkCount)
        )
    }

    private var recentNotes: [Note] {
        Array(
            notes
                .sorted { $0.modifiedAt > $1.modifiedAt }
                .prefix(SearchPaletteDesign.recentNoteCount)
        )
    }

    var body: some View {
        GeometryReader { proxy in
        ZStack(alignment: .top) {
            CiderColors.backdrop
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField

                Divider()
                    .background(CiderColors.separator)

                if hasQuery {
                    if hasResults {
                        resultsList
                    } else {
                        noResultsRow
                    }
                } else {
                    defaultContent
                }
            }
            .frame(width: SearchPaletteDesign.paletteWidth)
            .background(
                ZStack {
                    VisualEffectView(material: .underWindowBackground, blendingMode: .withinWindow)
                    CiderColors.acrylicOverlayTint
                    CiderColors.surfaceSubtle
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg - CiderBorder.innerStrokeInset, style: .continuous)
                    .stroke(CiderColors.borderPanel, lineWidth: CiderBorder.innerStrokeWidth)
                    .padding(CiderBorder.innerStrokeInset)
            )
            .shadow(color: CiderColors.shadowHeavy, radius: 24, x: 0, y: 12)
            .padding(.top, proxy.size.height * 0.22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .transition(.opacity)
        .onAppear {
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
        }
        .onExitCommand { onDismiss() }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.tertiary)

            TextField("Search bookmarks and notes\u{2026}", text: $query)
                .textFieldStyle(.plain)
                .font(CiderFont.title)
                .foregroundColor(CiderColors.primary)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    guard hasQuery else { return }
                    onSpawnSearchTab?(query)
                    onDismiss()
                }

            if hasQuery {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(CiderFont.headingMedium)
                        .foregroundColor(CiderColors.tertiary)
                }
                .buttonStyle(.plain)
            }

            Text("esc")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.quaternary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
        }
        .padding(.horizontal, Spacing.lg)
        .frame(height: SearchPaletteDesign.searchFieldHeight)
    }

    // MARK: - Default Content (no query)

    private var defaultContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if !recentBookmarks.isEmpty || !recentNotes.isEmpty {
                recentItemsSection
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.bottom, Spacing.md)
    }

    private var recentItemsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "clock")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("Recent")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)
            }
            .padding(.top, Spacing.xxs)

            ForEach(recentBookmarks) { bookmark in
                Button {
                    onOpenBookmark(bookmark)
                    onDismiss()
                } label: {
                    recentRowContent(
                        icon: "bookmark",
                        title: bookmark.title,
                        subtitle: bookmark.hostDisplay,
                        date: bookmark.updatedAt
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(recentNotes) { note in
                Button {
                    onOpenNote(note)
                    onDismiss()
                } label: {
                    recentRowContent(
                        icon: "note.text",
                        title: note.title,
                        subtitle: nil,
                        date: note.modifiedAt
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func recentRowContent(icon: String, title: String, subtitle: String?, date: Date) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(CiderFont.subheadingMedium)
                    .foregroundColor(CiderColors.primary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CiderFont.body)
                        .foregroundColor(CiderColors.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.sm)

            Text(date.formatted(.relative(presentation: .named)))
                .font(CiderFont.caption)
                .foregroundColor(CiderColors.quaternary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Results List

    private var resultsList: some View {
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
            }
            .padding(Spacing.md)
        }
        .frame(maxHeight: SearchPaletteDesign.resultsMaxHeight)
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
                searchResultRow(result)
            }
        }
    }

    private func searchResultRow(_ result: SearchResult) -> some View {
        Button {
            switch result.type {
            case .bookmark:
                if let bookmark = result.bookmark {
                    onOpenBookmark(bookmark)
                    onDismiss()
                }
            case .note:
                if let note = result.note {
                    onOpenNote(note)
                    onDismiss()
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

    // MARK: - No Results

    private var noResultsRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.tertiary)

            Text("No results for \"\(query)\"")
                .font(CiderFont.subheading)
                .foregroundColor(CiderColors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }
}
