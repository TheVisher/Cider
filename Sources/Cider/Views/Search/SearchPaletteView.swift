import SwiftUI

// MARK: - Quick Action Model

enum QuickAction: String, CaseIterable, Identifiable {
    case newBookmark, newNote, newEvent, newContact, newFolder, newTag, newTab, openSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newBookmark:  return "New Bookmark"
        case .newNote:      return "New Note"
        case .newEvent:     return "New Event"
        case .newContact:   return "New Contact"
        case .newFolder:    return "New Folder"
        case .newTag:       return "New Tag"
        case .newTab:       return "New Tab"
        case .openSettings: return "Open Settings"
        }
    }

    var icon: String {
        switch self {
        case .newBookmark:  return "bookmark.fill"
        case .newNote:      return "note.text.badge.plus"
        case .newEvent:     return "calendar.badge.plus"
        case .newContact:   return "person.badge.plus"
        case .newFolder:    return "folder.badge.plus"
        case .newTag:       return "tag"
        case .newTab:       return "plus.square.on.square"
        case .openSettings: return "gearshape"
        }
    }

    var keywords: [String] {
        switch self {
        case .newBookmark:  return ["capture", "url", "link", "save", "add"]
        case .newNote:      return ["write", "create", "add"]
        case .newEvent:     return ["date card", "calendar", "schedule", "create", "add"]
        case .newContact:   return ["person", "people", "create", "add"]
        case .newFolder:    return ["organize", "create", "add"]
        case .newTag:       return ["label", "create", "add"]
        case .newTab:       return ["view", "create", "add"]
        case .openSettings: return ["preferences", "config", "set"]
        }
    }

    func matches(query: String) -> Bool {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return true }
        return tokens.allSatisfy { token in
            title.localizedStandardContains(token)
            || keywords.contains { $0.localizedStandardContains(token) }
        }
    }
}

// MARK: - Selectable Item

private enum SelectableItem: Identifiable {
    case action(QuickAction)
    case tag(CardLabel)
    case result(SearchResult)

    var id: String {
        switch self {
        case .action(let a): return "action-\(a.id)"
        case .tag(let t): return "tag-\(t.id.uuidString)"
        case .result(let r): return "result-\(r.id.uuidString)"
        }
    }
}

// MARK: - Search Palette View

struct SearchPaletteView: View {
    let bookmarks: [Bookmark]
    let notes: [Note]
    let onOpenBookmark: (Bookmark) -> Void
    let onOpenNote: (Note) -> Void
    var onOpenDateCard: ((DateCard) -> Void)? = nil
    var onOpenContact: ((ContactCard) -> Void)? = nil
    let onSpawnSearchTab: ((String) -> Void)?
    let onDismiss: () -> Void
    var onAction: ((QuickAction) -> Void)?
    var onSelectTag: ((CardLabel) -> Void)?

    @State private var query = ""
    @State private var results: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedIndex: Int = -1
    @State private var activeScope = SearchScope(cleanQuery: "")
    @FocusState private var isSearchFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Filtered Data

    private var filteredActions: [QuickAction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return QuickAction.allCases.filter { $0.matches(query: trimmed) }
    }

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

    private var filteredTags: [CardLabel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return CardLabelStorage.shared.labels.filter { $0.name.localizedStandardContains(trimmed) }
    }

    private var hasResults: Bool {
        !results.isEmpty
    }

    private var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectableItems: [SelectableItem] {
        var items: [SelectableItem] = filteredActions.map { .action($0) }
        items += filteredTags.map { .tag($0) }
        items += results.map { .result($0) }
        return items
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

    private var recentDateCards: [DateCard] {
        Array(DateCardStorage.shared.dateCards.sorted { $0.updatedAt > $1.updatedAt }.prefix(2))
    }

    private var recentContacts: [ContactCard] {
        Array(ContactStorage.shared.contacts.sorted { $0.updatedAt > $1.updatedAt }.prefix(2))
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
        ZStack(alignment: .top) {
            CiderColors.backdrop
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                searchField

                if activeScope.hasActiveScopes {
                    scopePillsBar
                }

                Divider()
                    .background(CiderColors.separator)

                if hasQuery {
                    queryContent
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
            .background {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                    .fill(Color.black)
                    .blur(radius: 24)
                    .offset(y: 12)
                    .opacity(0.7)
            }
            .padding(.top, proxy.size.height * 0.22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            // Hidden buttons for arrow key + return handling (NSPanel workaround)
            VStack(spacing: 0) {
                Button("") { handleArrowDown() }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("") { handleArrowUp() }
                    .keyboardShortcut(.upArrow, modifiers: [])
                Button("") { handleReturn() }
                    .keyboardShortcut(.return, modifiers: [])
            }
            .frame(width: 0, height: 0)
            .opacity(0)
        }
        .transition(.opacity)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            isSearchFieldFocused = true
        }
        .onChange(of: query) { _, newQuery in
            selectedIndex = -1
            searchTask?.cancel()
            let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            activeScope = SearchService.parseScope(from: trimmed)
            guard !trimmed.isEmpty else { results = []; return }
            searchTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                results = await SearchService.search(query: trimmed, bookmarks: bookmarks, notes: notes)
            }
        }
    }

    // MARK: - Keyboard Navigation

    private func handleArrowDown() {
        let items = selectableItems
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    private func handleArrowUp() {
        selectedIndex = max(selectedIndex - 1, -1)
    }

    private func handleReturn() {
        let items = selectableItems
        if selectedIndex >= 0, selectedIndex < items.count {
            executeItem(items[selectedIndex])
        } else if hasQuery {
            onSpawnSearchTab?(query)
            onDismiss()
        }
    }

    private func executeItem(_ item: SelectableItem) {
        switch item {
        case .action(let action):
            onAction?(action)
            onDismiss()
        case .tag(let label):
            onSelectTag?(label)
            onDismiss()
        case .result(let result):
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
                break // TODO: open todo detail
            }
            onDismiss()
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(CiderFont.titleMedium)
                .foregroundColor(CiderColors.tertiary)

            TextField("Search everything\u{2026}  @bookmarks @notes @folder:Name", text: $query)
                .textFieldStyle(.plain)
                .font(CiderFont.title)
                .foregroundColor(CiderColors.primary)
                .focused($isSearchFieldFocused)
                .onSubmit {
                    handleReturn()
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

    // MARK: - Scope Pills

    private var scopePillsBar: some View {
        let descriptions = activeScope.activeScopeDescriptions
        return HStack(spacing: Spacing.xs) {
            ForEach(Array(descriptions.enumerated()), id: \.offset) { _, desc in
                HStack(spacing: Spacing.xxs) {
                    Image(systemName: scopeIcon(for: desc))
                        .font(CiderFont.caption)
                    Text(desc)
                        .font(CiderFont.captionMedium)
                }
                .foregroundColor(CiderColors.controlAccent)
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(CiderColors.controlAccent.opacity(0.12))
                )
            }
            Spacer()
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.xs)
    }

    private func scopeIcon(for description: String) -> String {
        let lower = description.lowercased()
        if lower == "bookmarks" { return "bookmark" }
        if lower == "notes" { return "note.text" }
        if lower == "events" { return "calendar" }
        if lower == "contacts" { return "person" }
        if lower.hasPrefix("folder:") { return "folder" }
        if lower.hasPrefix("tag:") { return "tag" }
        return "scope"
    }

    // MARK: - Folder Grouped Results

    /// Groups results by folder, showing a folder header + divider for each.
    private var folderGroupedResults: some View {
        let allFolders = BookmarksStorage.shared.folders
        // Determine which folders to show
        let targetFolderIDs: Set<UUID>
        if activeScope.showAllFolders {
            // All root folders that have items
            let folderIDsWithItems = Set(results.compactMap { resultFolderID($0) })
            targetFolderIDs = folderIDsWithItems
        } else {
            targetFolderIDs = activeScope.folderIDs
        }

        // Group results by folder
        let grouped: [(folder: Folder, items: [SearchResult])] = allFolders
            .filter { targetFolderIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .compactMap { folder in
                let folderResults = results.filter { resultFolderID($0) == folder.id }
                guard !folderResults.isEmpty else { return nil }
                return (folder, folderResults)
            }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            if grouped.isEmpty && !results.isEmpty {
                // Results exist but none have folder assignments (shouldn't happen with folder scope)
                ForEach(results) { result in
                    searchResultRow(result)
                }
            } else {
                ForEach(grouped, id: \.folder.id) { group in
                    folderSection(folder: group.folder, items: group.items, allFolders: allFolders)
                }
            }
        }
    }

    private func folderSection(folder: Folder, items: [SearchResult], allFolders: [Folder]) -> some View {
        let subFolders = allFolders.filter { $0.parentID == folder.id }

        return VStack(alignment: .leading, spacing: Spacing.xs) {
            // Folder header
            HStack(spacing: Spacing.sm) {
                if let icon = folder.icon {
                    if folder.iconIsEmoji {
                        Text(icon)
                            .font(CiderFont.subheadingMedium)
                    } else {
                        Image(systemName: icon)
                            .font(CiderFont.subheadingMedium)
                            .foregroundColor(CiderColors.controlAccent)
                    }
                } else {
                    Image(systemName: "folder.fill")
                        .font(CiderFont.subheadingMedium)
                        .foregroundColor(CiderColors.controlAccent)
                }

                Text(folder.name)
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.primary)

                if !subFolders.isEmpty {
                    HStack(spacing: Spacing.xxs) {
                        ForEach(subFolders.prefix(3)) { sub in
                            Text(sub.name)
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                        if subFolders.count > 3 {
                            Text("+\(subFolders.count - 3)")
                                .font(CiderFont.caption)
                                .foregroundColor(CiderColors.quaternary)
                        }
                    }
                }

                Spacer()

                Text("\(items.count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }

            Divider()
                .background(CiderColors.separator)

            // Items in this folder
            ForEach(items) { result in
                searchResultRow(result)
            }
        }
    }

    private func resultFolderID(_ result: SearchResult) -> UUID? {
        if let bookmark = result.bookmark { return bookmark.folderID }
        if let note = result.note { return note.folderID }
        if let dateCard = result.dateCard { return dateCard.folderID }
        if let contact = result.contact { return contact.folderID }
        return nil
    }

    // MARK: - Default Content (no query)

    private var defaultContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    actionsSection(actions: filteredActions)

                    let hasRecents = !recentBookmarks.isEmpty || !recentNotes.isEmpty
                                  || !recentDateCards.isEmpty || !recentContacts.isEmpty
                    if hasRecents {
                        recentItemsSection
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.bottom, Spacing.md)
            }
            .frame(maxHeight: SearchPaletteDesign.resultsMaxHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                let items = selectableItems
                guard newIndex >= 0, newIndex < items.count else { return }
                proxy.scrollTo(items[newIndex].id, anchor: .center)
            }
        }
    }

    // MARK: - Query Content (with search text)

    private var queryContent: some View {
        let actions = filteredActions
        let tags = filteredTags
        let showActions = !actions.isEmpty
        let showTags = !tags.isEmpty
        let showResults = hasResults
        let showNoResults = !showActions && !showTags && !showResults

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    if showActions {
                        actionsSection(actions: actions)
                    }

                    if showTags {
                        tagsSection(tags: tags)
                    }

                    if activeScope.hasFolderScope {
                        folderGroupedResults
                    } else if showResults {
                        if !bookmarkResults.isEmpty {
                            resultsSection(title: "Bookmarks", icon: "bookmark", results: bookmarkResults)
                        }
                        if !noteResults.isEmpty {
                            resultsSection(title: "Notes", icon: "note.text", results: noteResults)
                        }
                        if !dateCardResults.isEmpty {
                            resultsSection(title: "Date Cards", icon: "calendar", results: dateCardResults)
                        }
                        if !contactResults.isEmpty {
                            resultsSection(title: "Contacts", icon: "person", results: contactResults)
                        }
                    }

                    if showNoResults && !activeScope.hasFolderScope {
                        noResultsRow
                    }
                }
                .padding(Spacing.md)
            }
            .frame(maxHeight: SearchPaletteDesign.resultsMaxHeight)
            .onChange(of: selectedIndex) { _, newIndex in
                let items = selectableItems
                guard newIndex >= 0, newIndex < items.count else { return }
                proxy.scrollTo(items[newIndex].id, anchor: .center)
            }
        }
    }

    // MARK: - Actions Section

    private func actionsSection(actions: [QuickAction]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "bolt")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("Actions")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)
            }
            .padding(.top, Spacing.xxs)

            ForEach(actions) { action in
                let isSelected = isItemSelected(.action(action))

                Button {
                    onAction?(action)
                    onDismiss()
                } label: {
                    actionRowContent(action: action)
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? CiderColors.selectedFill : Color.clear)
                )
                .id(SelectableItem.action(action).id)
            }
        }
    }

    private func actionRowContent(action: QuickAction) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: action.icon)
                .font(CiderFont.bodyMedium)
                .foregroundColor(CiderColors.controlAccent)
                .frame(width: 16)

            Text(action.title)
                .font(CiderFont.subheadingMedium)
                .foregroundColor(CiderColors.primary)
                .lineLimit(1)

            Spacer(minLength: Spacing.sm)

            Text("Action")
                .font(CiderFont.captionMedium)
                .foregroundColor(CiderColors.quaternary)
                .padding(.horizontal, Spacing.xs)
                .padding(.vertical, Spacing.xxs)
                .background(
                    RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                        .fill(CiderColors.surfaceInput)
                )
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .contentShape(Rectangle())
    }

    // MARK: - Tags Section

    private func tagsSection(tags: [CardLabel]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "tag")
                    .font(CiderFont.captionSemibold)
                    .foregroundColor(CiderColors.tertiary)

                Text("Tags")
                    .font(CiderFont.bodySemibold)
                    .foregroundColor(CiderColors.tertiary)
                    .textCase(.uppercase)

                Text("\(tags.count)")
                    .font(CiderFont.captionMedium)
                    .foregroundColor(CiderColors.quaternary)
            }

            ForEach(tags) { label in
                let isSelected = isItemSelected(.tag(label))
                let count = CardLabelStorage.shared.itemCount(for: label.id)

                Button {
                    executeItem(.tag(label))
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(Color(hex: label.colorHex) ?? CiderColors.secondary)
                            .frame(width: 10, height: 10)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(label.name)
                                .font(CiderFont.subheadingMedium)
                                .foregroundColor(CiderColors.primary)
                                .lineLimit(1)

                            Text("Filter by tag \u{00B7} \(count) item\(count == 1 ? "" : "s")")
                                .font(CiderFont.body)
                                .foregroundColor(CiderColors.tertiary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: Spacing.sm)

                        Text("Tag")
                            .font(CiderFont.captionMedium)
                            .foregroundColor(CiderColors.quaternary)
                            .padding(.horizontal, Spacing.xs)
                            .padding(.vertical, Spacing.xxs)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.xs, style: .continuous)
                                    .fill(CiderColors.surfaceInput)
                            )
                    }
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xs)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(isSelected ? CiderColors.selectedFill : Color.clear)
                )
                .id("tag-\(label.id.uuidString)")
            }
        }
    }

    // MARK: - Recent Items Section

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
                        icon: bookmark.hasURL ? "bookmark" : "photo",
                        title: bookmark.title,
                        subtitle: bookmark.hasURL ? bookmark.hostDisplay : "",
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

            ForEach(recentDateCards) { card in
                Button {
                    guard let handler = onOpenDateCard else { return }
                    handler(card)
                    onDismiss()
                } label: {
                    recentRowContent(
                        icon: "calendar",
                        title: card.title,
                        subtitle: card.startAt.formatted(.dateTime.month().day().year()),
                        date: card.updatedAt
                    )
                }
                .buttonStyle(.plain)
            }

            ForEach(recentContacts) { contact in
                Button {
                    guard let handler = onOpenContact else { return }
                    handler(contact)
                    onDismiss()
                } label: {
                    recentRowContent(
                        icon: "person",
                        title: contact.displayName,
                        subtitle: contact.relationshipLabel.isEmpty ? nil : contact.relationshipLabel,
                        date: contact.updatedAt
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

    // MARK: - Results Section

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
        let isSelected = isItemSelected(.result(result))

        return Button {
            executeItem(.result(result))
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: iconName(for: result.type))
                    .font(CiderFont.bodyMedium)
                    .foregroundColor(CiderColors.controlAccent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 1) {
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
                .fill(isSelected ? CiderColors.selectedFill : CiderColors.surfaceSubtle)
        )
        .id("result-\(result.id.uuidString)")
    }

    // MARK: - Helpers

    private func isItemSelected(_ item: SelectableItem) -> Bool {
        let items = selectableItems
        guard selectedIndex >= 0, selectedIndex < items.count else { return false }
        return items[selectedIndex].id == item.id
    }

    private func iconName(for type: SearchResultType) -> String {
        switch type {
        case .bookmark:  return "bookmark"
        case .note:      return "note.text"
        case .dateCard:  return "calendar"
        case .contact:   return "person"
        case .todo:      return "checklist"
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
