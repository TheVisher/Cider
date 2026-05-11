import Foundation

struct MediaIdentificationCandidate: Hashable {
    var id: String
    var type: MediaItemType
    var title: String
    var canonicalTitle: String
    var externalIDs: [String: String]
    var confidence: Double
    var reason: String
}

enum MediaIdentificationDisposition: Hashable {
    case importable
    case review
    case skip
}

struct MediaIdentificationResult: Hashable {
    var disposition: MediaIdentificationDisposition
    var candidate: MediaIdentificationCandidate?
    var confidence: Double
    var reason: String
}

struct MediaMetadataIdentifier {
    static let confidentImportThreshold = 0.8

    func identify(bookmark: Bookmark) -> MediaIdentificationResult {
        guard let url = URL(string: bookmark.urlString),
              let host = url.host?.lowercased() else {
            return MediaIdentificationResult(
                disposition: .skip,
                candidate: nil,
                confidence: 0,
                reason: "Bookmark has no parseable URL."
            )
        }

        if let candidate = parseProviderURL(url: url, host: host, bookmark: bookmark) {
            let disposition: MediaIdentificationDisposition = candidate.confidence >= Self.confidentImportThreshold
                ? .importable
                : .review
            return MediaIdentificationResult(
                disposition: disposition,
                candidate: candidate,
                confidence: candidate.confidence,
                reason: candidate.reason
            )
        }

        if isReferenceHost(host) {
            let candidate = MediaIdentificationCandidate(
                id: "reference-\(stableHash(bookmark.urlString))",
                type: .reference,
                title: bookmark.title,
                canonicalTitle: MediaItem.canonicalTitle(for: bookmark.title),
                externalIDs: [:],
                confidence: 0.45,
                reason: "General media/reference host needs review before attaching to a media item."
            )
            return MediaIdentificationResult(
                disposition: .review,
                candidate: candidate,
                confidence: candidate.confidence,
                reason: candidate.reason
            )
        }

        return MediaIdentificationResult(
            disposition: .skip,
            candidate: nil,
            confidence: 0,
            reason: "No stable media provider ID found."
        )
    }

    private func parseProviderURL(url: URL, host: String, bookmark: Bookmark) -> MediaIdentificationCandidate? {
        let path = url.path
        let components = path.split(separator: "/").map(String.init)

        if host == "store.steampowered.com" || host == "steamcommunity.com" {
            if let appID = value(after: "app", in: components), appID.allSatisfy(\.isNumber) {
                return candidate(
                    providerKey: "steamAppID",
                    providerValue: appID,
                    id: "steam-\(appID)",
                    type: .game,
                    title: title(from: components.dropFirst(components.firstIndex(of: "app").map { $0 + 2 } ?? components.count), fallback: bookmark.title),
                    confidence: 0.98,
                    reason: "Steam app URL contained stable app id \(appID)."
                )
            }
        }

        if host.hasSuffix("imdb.com"), let imdbID = components.first(where: { $0.range(of: #"^tt\d+$"#, options: .regularExpression) != nil }) {
            let explicitShow = bookmark.title.range(of: #"(?<![a-z0-9])(tv\s+series|tv\s+mini\s+series|tv\s+show)(?![a-z0-9])"#, options: [.regularExpression, .caseInsensitive]) != nil
            return candidate(
                providerKey: "imdb",
                providerValue: imdbID,
                id: "imdb-\(imdbID)",
                type: explicitShow ? .show : .movie,
                title: bookmark.title,
                confidence: 0.84,
                reason: "IMDb title URL contained stable title id \(imdbID)."
            )
        }

        if host.hasSuffix("letterboxd.com"), components.first == "film", components.count >= 2 {
            let slug = components[1]
            return candidate(
                providerKey: "letterboxd",
                providerValue: slug,
                id: "letterboxd-\(slug)",
                type: .movie,
                title: title(from: [slug], fallback: bookmark.title),
                confidence: 0.92,
                reason: "Letterboxd film URL contained stable film slug \(slug)."
            )
        }

        if host.hasSuffix("trakt.tv"), components.count >= 2 {
            if components[0] == "movies" {
                let slug = components[1]
                return candidate(
                    providerKey: "trakt",
                    providerValue: "movie:\(slug)",
                    id: "trakt-movie-\(slug)",
                    type: .movie,
                    title: title(from: [slug], fallback: bookmark.title),
                    confidence: 0.92,
                    reason: "Trakt movie URL contained stable movie slug \(slug)."
                )
            }
            if components[0] == "shows" {
                let slug = components[1]
                return candidate(
                    providerKey: "trakt",
                    providerValue: "show:\(slug)",
                    id: "trakt-show-\(slug)",
                    type: .show,
                    title: title(from: [slug], fallback: bookmark.title),
                    confidence: 0.92,
                    reason: "Trakt show URL contained stable show slug \(slug)."
                )
            }
        }

        if host.hasSuffix("themoviedb.org"), components.count >= 2 {
            if components[0] == "movie", let id = numericPrefix(components[1]) {
                return candidate(
                    providerKey: "tmdb",
                    providerValue: "movie:\(id)",
                    id: "tmdb-movie-\(id)",
                    type: .movie,
                    title: title(from: [components[1]], fallback: bookmark.title),
                    confidence: 0.94,
                    reason: "TMDB movie URL contained stable movie id \(id)."
                )
            }
            if components[0] == "tv", let id = numericPrefix(components[1]) {
                return candidate(
                    providerKey: "tmdb",
                    providerValue: "show:\(id)",
                    id: "tmdb-show-\(id)",
                    type: .show,
                    title: title(from: [components[1]], fallback: bookmark.title),
                    confidence: 0.94,
                    reason: "TMDB TV URL contained stable show id \(id)."
                )
            }
        }

        if host.hasSuffix("goodreads.com"), components.count >= 3, components[0] == "book", components[1] == "show" {
            let raw = components[2]
            guard let id = numericPrefix(raw) else { return nil }
            return candidate(
                providerKey: "goodreads",
                providerValue: id,
                id: "goodreads-\(id)",
                type: .book,
                title: title(from: [raw], fallback: bookmark.title),
                confidence: 0.9,
                reason: "Goodreads book URL contained stable book id \(id)."
            )
        }

        if host.hasSuffix("thestorygraph.com"), components.count >= 2, components[0] == "books" {
            let slugOrISBN = components[1]
            let key = isISBNLike(slugOrISBN) ? "isbn" : "storygraph"
            return candidate(
                providerKey: key == "isbn" ? "storygraph" : key,
                providerValue: slugOrISBN,
                id: "storygraph-\(slugOrISBN)",
                type: .book,
                title: title(from: [slugOrISBN], fallback: bookmark.title),
                confidence: 0.88,
                reason: "StoryGraph book URL contained stable book identifier \(slugOrISBN)."
            )
        }

        return nil
    }

    private func candidate(
        providerKey: String,
        providerValue: String,
        id: String,
        type: MediaItemType,
        title: String,
        confidence: Double,
        reason: String
    ) -> MediaIdentificationCandidate {
        MediaIdentificationCandidate(
            id: id,
            type: type,
            title: title,
            canonicalTitle: MediaItem.canonicalTitle(for: title),
            externalIDs: [providerKey: providerValue],
            confidence: confidence,
            reason: reason
        )
    }

    private func value(after marker: String, in components: [String]) -> String? {
        guard let index = components.firstIndex(of: marker), index + 1 < components.count else { return nil }
        return components[index + 1]
    }

    private func numericPrefix(_ value: String) -> String? {
        let prefix = value.prefix { $0.isNumber }
        return prefix.isEmpty ? nil : String(prefix)
    }

    private func title<S: Sequence>(from slugs: S, fallback: String) -> String where S.Element == String {
        guard let slug = slugs.first(where: { !$0.isEmpty }) else { return fallback }
        let withoutNumericPrefix = slug.replacingOccurrences(
            of: #"^\d+-"#,
            with: "",
            options: .regularExpression
        )
        let words = withoutNumericPrefix
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .filter { !$0.allSatisfy(\.isNumber) }
        let title = words.map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
        return title.isEmpty ? fallback : title
    }

    private func isReferenceHost(_ host: String) -> Bool {
        [
            "youtube.com",
            "youtu.be",
            "reddit.com",
            "vimeo.com",
            "polygon.com",
            "ign.com",
            "gamespot.com",
            "theverge.com",
        ].contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func isISBNLike(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return digits.count == 10 || digits.count == 13
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

struct MediaBackfillReport: Hashable {
    var proposedItems: [MediaItem]
    var reviewItems: [MediaIdentificationResult]
    var skippedCount: Int
    var createdCount: Int
    var updatedCount: Int
}

struct MediaBackfillPlanner {
    private let identifier = MediaMetadataIdentifier()

    func plan(bookmarks: [Bookmark], existingItems: [MediaItem]) -> MediaBackfillReport {
        var itemsByID = Dictionary(uniqueKeysWithValues: existingItems.map { ($0.id, $0) })
        var proposedOrder: [String] = []
        var reviewItems: [MediaIdentificationResult] = []
        var skippedCount = 0

        for bookmark in bookmarks {
            let result = identifier.identify(bookmark: bookmark)
            switch result.disposition {
            case .importable:
                guard let candidate = result.candidate else {
                    skippedCount += 1
                    continue
                }
                let item = mediaItem(from: candidate, bookmark: bookmark)
                if let existing = itemsByID[item.id] {
                    let merged = existing.mergingSources(from: item)
                    if hasNewSources(existing: existing, candidate: item) {
                        itemsByID[item.id] = merged
                        if !proposedOrder.contains(item.id) {
                            proposedOrder.append(item.id)
                        }
                    }
                } else {
                    itemsByID[item.id] = item
                    proposedOrder.append(item.id)
                }
            case .review:
                reviewItems.append(result)
            case .skip:
                skippedCount += 1
            }
        }

        let proposedItems = proposedOrder.compactMap { itemsByID[$0] }
        return MediaBackfillReport(
            proposedItems: proposedItems,
            reviewItems: reviewItems,
            skippedCount: skippedCount,
            createdCount: 0,
            updatedCount: 0
        )
    }

    private func mediaItem(from candidate: MediaIdentificationCandidate, bookmark: Bookmark) -> MediaItem {
        MediaItem(
            id: candidate.id,
            type: candidate.type,
            title: candidate.title,
            canonicalTitle: candidate.canonicalTitle,
            externalIDs: candidate.externalIDs,
            sourceBookmarkIDs: [bookmark.id],
            sourceRelativePaths: bookmark.relativePath.map { [$0] } ?? [],
            sourceURLs: bookmark.urlString.isEmpty ? [] : [bookmark.urlString],
            confidence: candidate.confidence,
            identificationReason: candidate.reason
        )
    }

    private func hasNewSources(existing: MediaItem, candidate: MediaItem) -> Bool {
        let bookmarkIDs = Set(existing.sourceBookmarkIDs)
        let relativePaths = Set(existing.sourceRelativePaths)
        let sourceURLs = Set(existing.sourceURLs)

        return candidate.sourceBookmarkIDs.contains { !bookmarkIDs.contains($0) }
            || candidate.sourceRelativePaths.contains { !relativePaths.contains($0) }
            || candidate.sourceURLs.contains { !sourceURLs.contains($0) }
    }
}

enum MediaBackfillMode {
    case dryRun
    case apply
}

@MainActor
struct MediaBackfillService {
    let storage: MediaItemStorage
    private let planner = MediaBackfillPlanner()

    func identify(bookmarks: [Bookmark], mode: MediaBackfillMode) throws -> MediaBackfillReport {
        var report = planner.plan(bookmarks: bookmarks, existingItems: storage.items)
        guard mode == .apply else { return report }

        var created = 0
        var updated = 0
        for item in report.proposedItems {
            if storage.item(id: item.id) == nil {
                created += 1
            } else {
                updated += 1
            }
            try storage.upsert(item)
        }
        report.createdCount = created
        report.updatedCount = updated
        return report
    }
}
