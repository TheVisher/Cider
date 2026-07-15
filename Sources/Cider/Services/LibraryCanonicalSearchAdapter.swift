import Foundation

enum LibraryCanonicalSearchStatus: Equatable {
    case ready
    case failedClosed([String])
    case unavailable(String)
    case cancelled
}

struct LibraryCanonicalSearchResponse {
    var items: [LibraryItemV2]
    var canonical: CiderQueryResponse?
    var status: LibraryCanonicalSearchStatus
    var canonicalItemIDs: [UUID]
    var unprojectedCanonicalItemIDs: [UUID]
    var locallyExcludedCanonicalItemIDs: [UUID]

    var statusMessage: String? {
        switch status {
        case .cancelled:
            return nil
        case .failedClosed(let reasons):
            return (reasons.first ?? "The requested Library scope is unsupported.")
                + " Search was not broadened."
        case .unavailable:
            return "Indexed Library search is currently unavailable. No complete no-match conclusion was made."
        case .ready:
            var notices: [String] = []
            if !unprojectedCanonicalItemIDs.isEmpty {
                notices.append("Some indexed matches cannot be presented from the current Library snapshot.")
            }
            guard let canonical else {
                return "Indexed Library search state is unavailable."
            }
            if canonical.fallbackState == .canonicalFieldsOnly {
                notices.append("Showing canonical title and path fallback; indexed body search is unavailable.")
            }
            switch canonical.indexState.status {
            case .current:
                break
            case .lagging:
                notices.append("The Library search index is lagging; results may be incomplete.")
            case .incomplete:
                notices.append("The Library search index is incomplete; results may be incomplete.")
            case .unavailable:
                notices.append("Library index freshness is unavailable; results may be incomplete.")
            }
            if canonical.resultWindowIsBounded {
                notices.append("Showing a bounded canonical Library result window.")
            }
            if canonical.classification == .indeterminate {
                notices.append("No complete no-match conclusion was made.")
            }
            return notices.isEmpty ? nil : notices.joined(separator: " ")
        }
    }

    var emptyStateMessage: String? {
        guard items.isEmpty else { return nil }
        if let statusMessage { return statusMessage }
        guard case .ready = status else { return nil }
        guard let canonical else {
            return "Indexed Library search state is unavailable."
        }
        if !locallyExcludedCanonicalItemIDs.isEmpty {
            return "No indexed matches satisfy the current Library facets."
        }
        switch canonical.classification {
        case .matches:
            return "Indexed matches exist, but they cannot be presented in this Library view."
        case .noMatches:
            return nil
        case .indeterminate:
            return "Library search coverage was bounded. No complete no-match conclusion was made."
        }
    }
}

enum LibrarySearchPublishPolicy {
    static func canPublish(
        requestID: UUID,
        activeRequestID: UUID?,
        isCancelled: Bool
    ) -> Bool {
        !isCancelled && requestID == activeRequestID
    }
}

struct LibraryCanonicalSearchRequest: Hashable {
    var filter: LibraryFilterSpec
    var sort: LibrarySortSpec
    var itemRevision: Int
    var scopeIdentity: [String]
    var folderScopeIDs: Set<UUID>?
}

@MainActor
struct LibraryCanonicalSearchAdapter {
    private let contextService: CiderItemContextService
    private let resultLimit: Int

    init(
        contextService: CiderItemContextService = CiderItemContextService(),
        resultLimit: Int = 500
    ) {
        self.contextService = contextService
        self.resultLimit = max(1, resultLimit)
    }

    func search(
        items: [LibraryItemV2],
        filter: LibraryFilterSpec,
        sort: LibrarySortSpec,
        folders: [Folder],
        labels: [CardLabel],
        projectionAliases: [UUID: LibraryItemV2] = [:],
        folderScopeIDs: Set<UUID>? = nil
    ) async -> LibraryCanonicalSearchResponse {
        if Task.isCancelled { return cancelledResponse() }

        let scope = SearchService.parseScope(
            from: filter.textQuery,
            folders: folders,
            labels: labels
        )
        guard scope.isResolved else {
            return failedClosed(scope.resolutionFailures)
        }
        guard !(scope.showAllFolders && !scope.folderIDs.isEmpty) else {
            return failedClosed(["All-folders scope cannot be combined with a specific folder scope."])
        }
        guard filter.entityTypes.isSubset(of: LibraryEntityType.activeCases) else {
            return failedClosed(["The current Library route contains an unsupported item type."])
        }
        guard !filter.entityTypes.isEmpty else {
            return failedClosed(["The current Library route has no supported item scope."])
        }
        if let folderScopeIDs, folderScopeIDs.isEmpty {
            return failedClosed(["The current Library folder scope is empty."])
        }

        let folderIDs = Set(folders.map(\.id))
        if let folderID = filter.folderID, !folderIDs.contains(folderID) {
            return failedClosed(["The selected Library folder could not be resolved."])
        }
        if let folderScopeIDs, !folderScopeIDs.isSubset(of: folderIDs) {
            return failedClosed(["The current Library folder scope could not be fully resolved."])
        }
        let labelIDs = Set(labels.map(\.id))
        let unresolvedLabelIDs = filter.labelIDs.subtracting(labelIDs)
        guard unresolvedLabelIDs.isEmpty else {
            return failedClosed(["One or more selected Library tags could not be resolved."])
        }

        let requestedEntityTypes = scope.entityTypes.map { Set($0.map(libraryEntityType)) }
        let entityTypes: Set<LibraryEntityType>
        if let requestedEntityTypes {
            entityTypes = filter.entityTypes.intersection(requestedEntityTypes)
            guard !entityTypes.isEmpty else {
                return failedClosed(["The requested item scope does not overlap the current Library route or facet."])
            }
        } else {
            entityTypes = filter.entityTypes
        }

        let routeFolderIDs = folderScopeIDs
            ?? filter.folderID.map { Set([$0]) }
        let folderFacet: CiderQueryFolderFacet
        if let routeFolderIDs {
            if !scope.folderIDs.isEmpty {
                let intersection = routeFolderIDs.intersection(scope.folderIDs)
                guard !intersection.isEmpty else {
                    return failedClosed(["The requested folder does not match the current Library route."])
                }
                folderFacet = .folderIDs(intersection)
            } else {
                folderFacet = .folderIDs(routeFolderIDs)
            }
        } else if !scope.folderIDs.isEmpty {
            folderFacet = .folderIDs(scope.folderIDs)
        } else if scope.showAllFolders {
            folderFacet = .anyAssignedFolder
        } else {
            folderFacet = .none
        }

        var canonicalTagIDs = scope.labelID.map { Set([$0]) } ?? []
        if filter.labelIDs.count == 1 {
            canonicalTagIDs.formUnion(filter.labelIDs)
        }
        let query = CiderQuery(
            text: scope.cleanQuery,
            facets: CiderQueryFacets(
                entityTypes: entityTypes,
                folder: folderFacet,
                tagIDs: canonicalTagIDs
            ),
            limit: resultLimit
        )

        do {
            // Let a superseding keystroke cancel before entering the synchronous,
            // bounded canonical SQLite query on its existing actor.
            await Task.yield()
            if Task.isCancelled { return cancelledResponse() }
            let canonical = try contextService.query(query)
            if Task.isCancelled { return cancelledResponse() }
            return project(
                canonical,
                filter: filter,
                sort: sort,
                items: items,
                projectionAliases: projectionAliases
            )
        } catch {
            return LibraryCanonicalSearchResponse(
                items: [],
                canonical: nil,
                status: .unavailable(error.localizedDescription),
                canonicalItemIDs: [],
                unprojectedCanonicalItemIDs: [],
                locallyExcludedCanonicalItemIDs: []
            )
        }
    }

    private func failedClosed(_ reasons: [String]) -> LibraryCanonicalSearchResponse {
        LibraryCanonicalSearchResponse(
            items: [],
            canonical: nil,
            status: .failedClosed(reasons),
            canonicalItemIDs: [],
            unprojectedCanonicalItemIDs: [],
            locallyExcludedCanonicalItemIDs: []
        )
    }

    private func cancelledResponse() -> LibraryCanonicalSearchResponse {
        LibraryCanonicalSearchResponse(
            items: [],
            canonical: nil,
            status: .cancelled,
            canonicalItemIDs: [],
            unprojectedCanonicalItemIDs: [],
            locallyExcludedCanonicalItemIDs: []
        )
    }

    private func libraryEntityType(_ type: SearchResultType) -> LibraryEntityType {
        switch type {
        case .bookmark: return .bookmark
        case .note: return .note
        case .dateCard: return .dateCard
        case .contact: return .contact
        case .todo: return .todo
        case .vaultFile: return .vaultFile
        }
    }

    private func project(
        _ canonical: CiderQueryResponse,
        filter: LibraryFilterSpec,
        sort: LibrarySortSpec,
        items: [LibraryItemV2],
        projectionAliases: [UUID: LibraryItemV2]
    ) -> LibraryCanonicalSearchResponse {
        var itemsByID = projectionAliases
        for item in items {
            if let id = item.canonicalEntityID, itemsByID[id] == nil {
                itemsByID[id] = item
            }
        }

        var canonicalItemIDs: [UUID] = []
        var visible: [LibraryItemV2] = []
        var visibleRowIDs = Set<String>()
        var unprojected: [UUID] = []
        var locallyExcluded: [UUID] = []
        for result in canonical.results {
            guard let canonicalItem = result.item else { continue }
            canonicalItemIDs.append(canonicalItem.id)
            guard let item = itemsByID[canonicalItem.id] else {
                unprojected.append(canonicalItem.id)
                continue
            }
            guard matchesLocalLibraryFacets(item, filter: filter) else {
                locallyExcluded.append(canonicalItem.id)
                continue
            }
            if visibleRowIDs.insert(item.id).inserted {
                visible.append(item)
            }
        }

        return LibraryCanonicalSearchResponse(
            items: sortItems(visible, using: sort.mode),
            canonical: canonical,
            status: .ready,
            canonicalItemIDs: canonicalItemIDs,
            unprojectedCanonicalItemIDs: unprojected,
            locallyExcludedCanonicalItemIDs: locallyExcluded
        )
    }

    /// These facets are intentionally Library presentation policy because the
    /// canonical query contract does not model multi-tag OR, Inbox semantics,
    /// or completion state.
    private func matchesLocalLibraryFacets(
        _ item: LibraryItemV2,
        filter: LibraryFilterSpec
    ) -> Bool {
        if !filter.labelIDs.isEmpty, item.labelIDs.isDisjoint(with: filter.labelIDs) {
            return false
        }
        if filter.onlyUnassigned, !item.isInboxItem {
            return false
        }
        if !filter.includeCompleted, item.isCompleted {
            return false
        }
        return true
    }

    private func sortItems(
        _ source: [LibraryItemV2],
        using mode: LibrarySortMode
    ) -> [LibraryItemV2] {
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
                ($0.dateAnchor ?? $0.createdDate) < ($1.dateAnchor ?? $1.createdDate)
            }
        case .dateFarthest:
            return source.sorted {
                ($0.dateAnchor ?? $0.createdDate) > ($1.dateAnchor ?? $1.createdDate)
            }
        }
    }
}
