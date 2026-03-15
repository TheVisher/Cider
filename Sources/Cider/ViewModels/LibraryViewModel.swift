import Foundation
import Combine

struct StackSurfaceResult: Identifiable, Hashable {
    let id: UUID
    let stack: CardStack
    let items: [LibraryItemV2]
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryItemV2] = []
    /// Top 8 most recently updated items — pre-sorted during rebuildItems().
    @Published private(set) var recentItems: [LibraryItemV2] = []

    /// Cache for filteredItems — avoids re-filtering+sorting on unrelated body evaluations.
    private var filteredItemsCache: (filter: SavedViewFilterSpec, sort: SavedViewSortSpec, result: [LibraryItemV2])?

    /// Cache for external file content read during text search — cleared on rebuildItems.
    private static var externalFileContentCache: [UUID: String] = [:]

    private var cancellables = Set<AnyCancellable>()

    init() {
        bindStorages()
        rebuildItems()
    }

    func rebuildItems() {
        let bookmarkItems = BookmarksStorage.shared.bookmarks.map { LibraryItemV2.bookmark($0) }
        let noteItems = NotesStorage.shared.notes.map { LibraryItemV2.note($0) }
        let dateCardItems = DateCardStorage.shared.dateCards.map { LibraryItemV2.dateCard($0) }
        let contactItems = ContactStorage.shared.contacts.map { LibraryItemV2.contact($0) }
        let todoItems = TodoCardStorage.shared.todoCards.map { LibraryItemV2.todo($0) }
        let externalFileItems = ExternalSourceRegistry.shared.libraryFiles.map { LibraryItemV2.externalFile($0) }
        let vaultFileItems = VaultFileService.shared.files.map { LibraryItemV2.vaultFile($0) }
        let sessionItems = BrowserSessionStorage.shared.sessions.map { LibraryItemV2.session($0) }

        let all = bookmarkItems + noteItems + dateCardItems + contactItems + todoItems + externalFileItems + vaultFileItems + sessionItems
        items = all
        recentItems = Array(all.sorted { $0.updatedDate > $1.updatedDate }.prefix(8))
        filteredItemsCache = nil
        Self.externalFileContentCache.removeAll()
    }

    func filteredItems(
        using filterSpec: SavedViewFilterSpec,
        sort sortSpec: SavedViewSortSpec
    ) -> [LibraryItemV2] {
        if let cache = filteredItemsCache, cache.filter == filterSpec, cache.sort == sortSpec {
            return cache.result
        }

        let query = filterSpec.textQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse scope modifiers from the search query
        let scope = query.isEmpty ? nil : SearchService.parseScope(from: query)
        let cleanQuery = scope?.cleanQuery ?? query

        let filtered = items.filter { item in
            // Apply scope entity type filter (narrower than filterSpec)
            if let scopeTypes = scope?.entityTypes {
                let entityMatch: Bool
                switch item {
                case .bookmark:     entityMatch = scopeTypes.contains(.bookmark)
                case .note:         entityMatch = scopeTypes.contains(.note)
                case .dateCard:     entityMatch = scopeTypes.contains(.dateCard)
                case .contact:      entityMatch = scopeTypes.contains(.contact)
                case .todo:         entityMatch = scopeTypes.contains(.todo)
                case .externalFile, .vaultFile: entityMatch = false
                case .session:      entityMatch = scopeTypes.contains(.session)
                }
                guard entityMatch else { return false }
            } else {
                guard filterSpec.entityTypes.contains(item.entityType) else { return false }
            }

            // Apply scope folder filter
            if let s = scope, !s.folderIDs.isEmpty {
                guard let fID = item.folderID, s.folderIDs.contains(fID) else { return false }
            } else if let s = scope, s.showAllFolders {
                guard item.folderID != nil else { return false }
            } else if let folderID = filterSpec.folderID, item.folderID != folderID {
                return false
            }

            // Apply scope tag filter
            if let scopeLabelID = scope?.labelID {
                guard item.labelIDs.contains(scopeLabelID) else { return false }
            } else if !filterSpec.labelIDs.isEmpty, item.labelIDs.isDisjoint(with: filterSpec.labelIDs) {
                return false
            }

            // Skip onlyUnassigned when scope explicitly targets folders
            if scope?.hasFolderScope != true, filterSpec.onlyUnassigned, item.folderID != nil {
                return false
            }

            if !filterSpec.includeCompleted, item.isCompleted {
                return false
            }

            if !cleanQuery.isEmpty, !Self.matchesTextQuery(cleanQuery, in: item) {
                return false
            }

            return true
        }

        let result = sortItems(filtered, using: sortSpec.mode)
        filteredItemsCache = (filterSpec, sortSpec, result)
        return result
    }

    func calendarBuckets(for month: Date, using filterSpec: SavedViewFilterSpec) -> [Date: [LibraryItemV2]] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [:] }
        let sorted = filteredItems(using: filterSpec, sort: SavedViewSortSpec(mode: .createdDescending))

        var buckets: [Date: [LibraryItemV2]] = [:]
        for item in sorted {
            guard let anchor = item.dateAnchor, monthInterval.contains(anchor) else { continue }
            let dayStart = calendar.startOfDay(for: anchor)
            buckets[dayStart, default: []].append(item)
        }

        for key in buckets.keys {
            buckets[key] = buckets[key]?.sorted(by: { lhs, rhs in
                let lhsDate = lhs.dateAnchor ?? lhs.createdDate
                let rhsDate = rhs.dateAnchor ?? rhs.createdDate
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            })
        }

        return buckets
    }

    func surfacedStacks(from items: [LibraryItemV2], now: Date = Date()) -> [StackSurfaceResult] {
        let stacks = CardStackStorage.shared.stacks
        var results: [StackSurfaceResult] = []

        for stack in stacks {
            let matched = matchedItems(for: stack, from: items)
            guard !matched.isEmpty else { continue }

            let shouldSurface = stack.isPinned || stack.surfaceRules.contains(where: { isSurfaceRuleTriggered($0, items: matched, now: now) })
            guard shouldSurface else { continue }

            results.append(StackSurfaceResult(id: stack.id, stack: stack, items: sortedStackItems(matched, mode: stack.sortMode)))
        }

        return results.sorted { lhs, rhs in
            if lhs.stack.isPinned != rhs.stack.isPinned {
                return lhs.stack.isPinned && !rhs.stack.isPinned
            }
            return lhs.stack.updatedAt > rhs.stack.updatedAt
        }
    }

    private func bindStorages() {
        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        DateCardStorage.shared.$dateCards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        ContactStorage.shared.$contacts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        TodoCardStorage.shared.$todoCards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        ExternalSourceRegistry.shared.$libraryFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        VaultFileService.shared.$files
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)

        BrowserSessionStorage.shared.$sessions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)
    }

    /// Token-based search: splits query into words, each must match in at least one field.
    /// Uses `localizedStandardContains` for diacritic- and case-insensitive matching.
    static func matchesTextQuery(_ query: String, in item: LibraryItemV2) -> Bool {
        let tokens = query.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return true }

        let fields: [String]
        switch item {
        case .bookmark(let bookmark):
            var bFields = [bookmark.title, bookmark.urlString, bookmark.notes] + bookmark.tags
            if let ocr = bookmark.ocrText { bFields.append(ocr) }
            fields = bFields
        case .note(let note):
            let content = NotesStorage.shared.loadContent(for: note)
            fields = [note.title, content]
        case .dateCard(let dateCard):
            fields = [dateCard.title, dateCard.details, dateCard.location]
        case .contact(let contact):
            fields = [contact.displayName, contact.relationshipLabel, contact.notes]
        case .todo(let todo):
            var tFields = [todo.title, todo.details]
            tFields.append(contentsOf: todo.checklist.map(\.title))
            fields = tFields
        case .externalFile(let file):
            let content: String
            if let cached = externalFileContentCache[file.id] {
                content = cached
            } else {
                let loaded = (try? String(contentsOf: file.path, encoding: .utf8)) ?? ""
                externalFileContentCache[file.id] = loaded
                content = loaded
            }
            fields = [file.title, content]
        case .vaultFile(let file):
            fields = [file.filename]
        case .session(let session):
            var sFields = [session.name]
            sFields.append(contentsOf: session.tabs.compactMap(\.title))
            fields = sFields
        }

        // Also match against label names for the item
        let labelNames = item.labelIDs.compactMap { CardLabelStorage.shared.label(for: $0)?.name }

        return tokens.allSatisfy { token in
            fields.contains { $0.localizedStandardContains(token) }
            || labelNames.contains { $0.localizedStandardContains(token) }
        }
    }

    private func sortItems(_ source: [LibraryItemV2], using mode: LibrarySortMode) -> [LibraryItemV2] {
        switch mode {
        case .createdDescending:
            return source.sorted { $0.createdDate > $1.createdDate }
        case .createdAscending:
            return source.sorted { $0.createdDate < $1.createdDate }
        case .updatedDescending:
            return source.sorted { $0.updatedDate > $1.updatedDate }
        case .updatedAscending:
            return source.sorted { $0.updatedDate < $1.updatedDate }
        case .titleAscending:
            return source.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .titleDescending:
            return source.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
        case .dateUpcoming:
            return source.sorted {
                let lhs = $0.dateAnchor ?? $0.createdDate
                let rhs = $1.dateAnchor ?? $1.createdDate
                return lhs < rhs
            }
        case .dateFarthest:
            return source.sorted {
                let lhs = $0.dateAnchor ?? $0.createdDate
                let rhs = $1.dateAnchor ?? $1.createdDate
                return lhs > rhs
            }
        }
    }

    private func matchedItems(for stack: CardStack, from items: [LibraryItemV2]) -> [LibraryItemV2] {
        let manualMatches = items.filter { item in
            stack.manualItemRefs.contains(where: { ref in
                ref.type == item.entityType && ref.entityID.uuidString == entityUUIDString(for: item)
            })
        }

        guard !stack.matchRules.isEmpty else {
            // Manual-only stacks are valid. Empty rule + empty manual should match nothing.
            return manualMatches
        }

        let ruleMatches = items.filter { item in
            stack.matchRules.allSatisfy { rule in
                switch rule.condition {
                case .hasDate:
                    return item.dateAnchor != nil
                case .isIncomplete:
                    return !item.isCompleted
                case .hasLabel:
                    guard let value = rule.value, let labelID = UUID(uuidString: value) else { return false }
                    return item.labelIDs.contains(labelID)
                case .entityType:
                    guard let value = rule.value, let entityType = LibraryEntityType(rawValue: value) else { return false }
                    return item.entityType == entityType
                }
            }
        }

        // Merge while preserving stable order from `items`.
        var merged: [LibraryItemV2] = manualMatches
        var mergedIDs = Set(merged.map(\.id))
        for item in ruleMatches where !mergedIDs.contains(item.id) {
            merged.append(item)
            mergedIDs.insert(item.id)
        }
        // Keep deterministic order aligned with source items.
        return items.filter { mergedIDs.contains($0.id) }
    }

    private func sortedStackItems(_ items: [LibraryItemV2], mode: StackSortMode) -> [LibraryItemV2] {
        switch mode {
        case .time:
            return items.sorted { lhs, rhs in
                let lhsDate = lhs.dateAnchor ?? lhs.createdDate
                let rhsDate = rhs.dateAnchor ?? rhs.createdDate
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        case .attention:
            return items.sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted && rhs.isCompleted
                }
                let lhsDate = lhs.dateAnchor ?? lhs.createdDate
                let rhsDate = rhs.dateAnchor ?? rhs.createdDate
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
                return lhs.updatedDate > rhs.updatedDate
            }
        }
    }

    private func isSurfaceRuleTriggered(_ rule: SurfacingRule, items: [LibraryItemV2], now: Date) -> Bool {
        guard rule.isEnabled else { return false }

        switch rule.type {
        case .pinUntilDone:
            return items.contains(where: { !$0.isCompleted })
        case .surfaceDaysBeforeDate:
            let days = rule.integerValue ?? 0
            guard days >= 0 else { return false }
            let calendar = Calendar.current
            guard let limit = calendar.date(byAdding: .day, value: days, to: now) else { return false }
            return items.contains { item in
                guard let anchor = item.dateAnchor else { return false }
                return anchor >= now && anchor <= limit
            }
        case .remindBeforeMinutes:
            let minutes = rule.integerValue ?? 0
            guard minutes >= 0 else { return false }
            guard let limit = Calendar.current.date(byAdding: .minute, value: minutes, to: now) else { return false }
            return items.contains { item in
                guard let anchor = item.dateAnchor else { return false }
                return anchor >= now && anchor <= limit
            }
        }
    }

    private func entityUUIDString(for item: LibraryItemV2) -> String {
        switch item {
        case .bookmark(let bookmark):
            bookmark.id.uuidString
        case .note(let note):
            note.id.uuidString
        case .dateCard(let dateCard):
            dateCard.id.uuidString
        case .contact(let contact):
            contact.id.uuidString
        case .todo(let todo):
            todo.id.uuidString
        case .externalFile(let file):
            file.id.uuidString
        case .vaultFile(let file):
            file.id.uuidString
        case .session(let session):
            session.id.uuidString
        }
    }
}
