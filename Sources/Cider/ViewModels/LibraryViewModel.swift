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
        let externalFileItems = ExternalSourceRegistry.shared.libraryFiles.map { LibraryItemV2.externalFile($0) }

        let all = bookmarkItems + noteItems + dateCardItems + contactItems + externalFileItems
        items = all
        recentItems = Array(all.sorted { $0.updatedDate > $1.updatedDate }.prefix(8))
    }

    func filteredItems(
        using filterSpec: SavedViewFilterSpec,
        sort sortSpec: SavedViewSortSpec
    ) -> [LibraryItemV2] {
        let query = filterSpec.textQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = items.filter { item in
            guard filterSpec.entityTypes.contains(item.entityType) else { return false }

            if let folderID = filterSpec.folderID, item.folderID != folderID {
                return false
            }

            if !filterSpec.includeCompleted, item.isCompleted {
                return false
            }

            if !filterSpec.labelIDs.isEmpty, item.labelIDs.isDisjoint(with: filterSpec.labelIDs) {
                return false
            }

            if !query.isEmpty, !matchesTextQuery(query, in: item) {
                return false
            }

            return true
        }

        return sortItems(filtered, using: sortSpec.mode)
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

        ExternalSourceRegistry.shared.$libraryFiles
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildItems() }
            .store(in: &cancellables)
    }

    private func matchesTextQuery(_ query: String, in item: LibraryItemV2) -> Bool {
        switch item {
        case .bookmark(let bookmark):
            return bookmark.title.lowercased().contains(query)
                || bookmark.urlString.lowercased().contains(query)
                || bookmark.notes.lowercased().contains(query)
                || bookmark.tags.contains(where: { $0.lowercased().contains(query) })
        case .note(let note):
            let content = NotesStorage.shared.loadContent(for: note).lowercased()
            return note.title.lowercased().contains(query) || content.contains(query)
        case .dateCard(let dateCard):
            return dateCard.title.lowercased().contains(query)
                || dateCard.details.lowercased().contains(query)
                || dateCard.location.lowercased().contains(query)
        case .contact(let contact):
            return contact.displayName.lowercased().contains(query)
                || contact.relationshipLabel.lowercased().contains(query)
                || contact.notes.lowercased().contains(query)
        case .externalFile(let file):
            if file.title.lowercased().contains(query) { return true }
            let content = (try? String(contentsOf: file.path, encoding: .utf8))?.lowercased() ?? ""
            return content.contains(query)
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
        case .externalFile(let file):
            file.id.uuidString
        }
    }
}
