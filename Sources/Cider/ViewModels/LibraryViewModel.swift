import Foundation
import Combine

@MainActor
final class LibraryRebuildCoalescer {
    private var isScheduled = false
    private let rebuild: @MainActor () -> Void

    init(rebuild: @escaping @MainActor () -> Void) {
        self.rebuild = rebuild
    }

    func requestRebuild() {
        guard !isScheduled else { return }
        isScheduled = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isScheduled = false
            self.rebuild()
        }
    }
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published private(set) var items: [LibraryItemV2] = []
    /// Top 8 most recently updated items — pre-sorted during rebuildItems().
    @Published private(set) var recentItems: [LibraryItemV2] = []
    @Published private(set) var itemRevision = 0
    @Published private(set) var canonicalSearchRevision = 0

    /// Cache for filteredItems — avoids re-filtering+sorting on unrelated body evaluations.
    private var filteredItemsCache: (filter: LibraryFilterSpec, sort: LibrarySortSpec, result: [LibraryItemV2])?
    private var canonicalSearchCache: (
        request: LibraryCanonicalSearchRequest,
        response: LibraryCanonicalSearchResponse
    )?
    private var activeCanonicalSearchRequestID: UUID?
    private var journalProjectionAliases: [UUID: LibraryItemV2] = [:]
    private let canonicalSearchAdapter: LibraryCanonicalSearchAdapter

    private var cancellables = Set<AnyCancellable>()
    private lazy var rebuildCoalescer = LibraryRebuildCoalescer { [weak self] in
        self?.rebuildItems()
    }

    init(canonicalSearchAdapter: LibraryCanonicalSearchAdapter = LibraryCanonicalSearchAdapter()) {
        self.canonicalSearchAdapter = canonicalSearchAdapter
        bindStorages()
        rebuildItems()
    }

    func rebuildItems() {
        let journalProjection = JournalLibraryReadModel.buildFromCanonicalStore(from: NotesStorage.shared.notes)
        let journalItems: [LibraryItemV2] = journalProjection.entries.isEmpty
            ? []
            : [.journal(journalProjection.container)]
        if let journalItem = journalItems.first {
            journalProjectionAliases = Dictionary(
                uniqueKeysWithValues: journalProjection.entries.map { ($0.note.id, journalItem) }
            )
        } else {
            journalProjectionAliases = [:]
        }
        let bookmarkItems = VaultBookmarkService.shared.bookmarks.map { LibraryItemV2.bookmark($0) }
        let noteItems = NotesStorage.shared.notes
            .filter { !$0.isProjectArtifact }
            .filter { !$0.isDailyJournalNote }
            .map { LibraryItemV2.note($0) }
        let dateCardItems = DateCardStorage.shared.dateCards.map { LibraryItemV2.dateCard($0) }
        let contactItems = ContactStorage.shared.contacts.map { LibraryItemV2.contact($0) }
        let todoItems = TodoCardStorage.shared.todoCards.map { LibraryItemV2.todo($0) }
        let vaultFileItems = VaultFileService.shared.files
            .filter { !$0.isProjectArtifact }
            .filter { !$0.isJournalSourceOriginal }
            .map { LibraryItemV2.vaultFile($0) }

        let all = journalItems + bookmarkItems + noteItems + dateCardItems + contactItems + todoItems + vaultFileItems
        items = all
        recentItems = Array(all.sorted { $0.updatedDate > $1.updatedDate }.prefix(8))
        filteredItemsCache = nil
        canonicalSearchCache = nil
        activeCanonicalSearchRequestID = nil
        itemRevision &+= 1
    }

    func filteredItems(
        using filterSpec: LibraryFilterSpec,
        sort sortSpec: LibrarySortSpec,
        canonicalFolderScopeIDs: Set<UUID>? = nil
    ) -> [LibraryItemV2] {
        let query = filterSpec.textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            let request = canonicalSearchRequest(
                using: filterSpec,
                sort: sortSpec,
                folderScopeIDs: canonicalFolderScopeIDs
            )
            return canonicalSearchCache?.request == request
                ? canonicalSearchCache?.response.items ?? []
                : []
        }

        if let cache = filteredItemsCache, cache.filter == filterSpec, cache.sort == sortSpec {
            return cache.result
        }

        let filtered = items.filter { item in
            guard filterSpec.entityTypes.contains(item.entityType) else { return false }

            if let folderID = filterSpec.folderID, item.folderID != folderID {
                return false
            }

            if !filterSpec.labelIDs.isEmpty, item.labelIDs.isDisjoint(with: filterSpec.labelIDs) {
                return false
            }

            // Inbox/Unassigned views should show real Inbox captures and pathless unfiled cards,
            // not every legacy path-backed item whose folder row is missing.
            if filterSpec.onlyUnassigned, !item.isInboxItem {
                return false
            }

            if !filterSpec.includeCompleted, item.isCompleted {
                return false
            }

            return true
        }

        let result = sortItems(filtered, using: sortSpec.mode)
        filteredItemsCache = (filterSpec, sortSpec, result)
        return result
    }

    func canonicalSearchRequest(
        using filterSpec: LibraryFilterSpec,
        sort sortSpec: LibrarySortSpec,
        folderScopeIDs: Set<UUID>? = nil
    ) -> LibraryCanonicalSearchRequest {
        LibraryCanonicalSearchRequest(
            filter: filterSpec,
            sort: sortSpec,
            itemRevision: itemRevision,
            scopeIdentity: (
                VaultFolderService.shared.legacyFolders.map { "folder:\($0.id.uuidString):\($0.name)" }
                    + CardLabelStorage.shared.labels.map { "tag:\($0.id.uuidString):\($0.name)" }
            ).sorted(),
            folderScopeIDs: folderScopeIDs
        )
    }

    func refreshCanonicalSearch(
        using filterSpec: LibraryFilterSpec,
        sort sortSpec: LibrarySortSpec,
        folderScopeIDs: Set<UUID>? = nil
    ) async {
        let query = filterSpec.textQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            let hadCachedSearch = canonicalSearchCache != nil
            canonicalSearchCache = nil
            activeCanonicalSearchRequestID = nil
            if hadCachedSearch { canonicalSearchRevision &+= 1 }
            return
        }

        let request = canonicalSearchRequest(
            using: filterSpec,
            sort: sortSpec,
            folderScopeIDs: folderScopeIDs
        )
        if canonicalSearchCache?.request == request { return }

        let requestID = UUID()
        activeCanonicalSearchRequestID = requestID
        let response = await canonicalSearchAdapter.search(
            items: items,
            filter: filterSpec,
            sort: sortSpec,
            folders: VaultFolderService.shared.legacyFolders,
            labels: CardLabelStorage.shared.labels,
            projectionAliases: journalProjectionAliases,
            folderScopeIDs: folderScopeIDs
        )
        guard LibrarySearchPublishPolicy.canPublish(
            requestID: requestID,
            activeRequestID: activeCanonicalSearchRequestID,
            isCancelled: Task.isCancelled
        ), request == canonicalSearchRequest(
            using: filterSpec,
            sort: sortSpec,
            folderScopeIDs: folderScopeIDs
        ) else {
            return
        }
        canonicalSearchCache = (request, response)
        canonicalSearchRevision &+= 1
    }

    func canonicalSearchStatusMessage(
        using filterSpec: LibraryFilterSpec,
        sort sortSpec: LibrarySortSpec,
        folderScopeIDs: Set<UUID>? = nil
    ) -> String? {
        let request = canonicalSearchRequest(
            using: filterSpec,
            sort: sortSpec,
            folderScopeIDs: folderScopeIDs
        )
        guard canonicalSearchCache?.request == request else { return nil }
        return canonicalSearchCache?.response.statusMessage
    }

    func canonicalSearchEmptyStateMessage(
        using filterSpec: LibraryFilterSpec,
        sort sortSpec: LibrarySortSpec,
        folderScopeIDs: Set<UUID>? = nil
    ) -> String? {
        let request = canonicalSearchRequest(
            using: filterSpec,
            sort: sortSpec,
            folderScopeIDs: folderScopeIDs
        )
        guard canonicalSearchCache?.request == request else {
            return "Searching indexed Library items…"
        }
        return canonicalSearchCache?.response.emptyStateMessage
    }

    func calendarBuckets(for month: Date, using filterSpec: LibraryFilterSpec) -> [Date: [LibraryItemV2]] {
        let calendar = Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: month) else { return [:] }
        let sorted = filteredItems(using: filterSpec, sort: LibrarySortSpec(mode: .createdDescending))

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

    private func bindStorages() {
        VaultBookmarkService.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCoalescer.requestRebuild() }
            .store(in: &cancellables)

        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCoalescer.requestRebuild() }
            .store(in: &cancellables)

        DateCardStorage.shared.$dateCards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCoalescer.requestRebuild() }
            .store(in: &cancellables)

        ContactStorage.shared.$contacts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCoalescer.requestRebuild() }
            .store(in: &cancellables)

        TodoCardStorage.shared.$todoCards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCoalescer.requestRebuild() }
            .store(in: &cancellables)

        VaultFileService.shared.$files
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildCoalescer.requestRebuild() }
            .store(in: &cancellables)

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

}
