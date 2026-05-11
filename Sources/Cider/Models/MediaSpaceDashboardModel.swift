import Foundation

enum MediaSpaceSectionKind: String, CaseIterable, Hashable {
    case movies
    case shows
    case games
    case books
    case references
    case inbox
    case tasteProfile

    var displayName: String {
        switch self {
        case .movies: "Movies"
        case .shows: "Shows"
        case .games: "Games"
        case .books: "Books"
        case .references: "References"
        case .inbox: "Needs Sorting"
        case .tasteProfile: "Taste Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .movies: "film"
        case .shows: "tv"
        case .games: "gamecontroller"
        case .books: "books.vertical"
        case .references: "quote.bubble"
        case .inbox: "tray"
        case .tasteProfile: "sparkles"
        }
    }

    var subtitle: String {
        switch self {
        case .movies: "Films, trailers, reviews, and watchlist saves."
        case .shows: "TV, seasons, episodes, and series notes."
        case .games: "Steam pages, game saves, wishlists, and references."
        case .books: "Books, reading ideas, authors, and book references."
        case .references: "Essays, reviews, criticism, interviews, and videos."
        case .inbox: "Media-ish saves that need a human decision."
        case .tasteProfile: "Preference signals found in your notes and memories."
        }
    }
}

enum MediaSpaceItemDetailMode: String, Hashable {
    case structuredMediaItem
    case sourceBookmark
}

struct MediaSpaceItem: Identifiable, Hashable {
    let id: String
    let mediaItem: MediaItem?
    let bookmark: Bookmark
    let section: MediaSpaceSectionKind
    let reason: String

    var title: String {
        mediaItem?.title ?? bookmark.title
    }

    var sourceSubtitle: String {
        if let mediaItem {
            return mediaItem.sourceURLs.first.flatMap { URL(string: $0)?.host?.ciderDroppingWWWPrefix } ?? mediaItem.type.rawValue
        }
        return bookmark.hostDisplay.ciderDroppingWWWPrefix
    }

    var detailMode: MediaSpaceItemDetailMode {
        mediaItem == nil ? .sourceBookmark : .structuredMediaItem
    }

    var sourceCount: Int {
        guard let mediaItem else { return bookmark.urlString.isEmpty ? 0 : 1 }
        let bookmarkCount = mediaItem.sourceBookmarkIDs.count
        let urlCount = mediaItem.sourceURLs.count
        let pathCount = mediaItem.sourceRelativePaths.count
        return max(1, bookmarkCount + urlCount + pathCount)
    }

    var metadataSummary: String {
        guard let mediaItem else { return reason }

        var parts: [String] = []
        if let year = mediaItem.year {
            parts.append(String(year))
        } else if let releaseDate = mediaItem.releaseDate, !releaseDate.isEmpty {
            parts.append(releaseDate)
        }

        if !mediaItem.genres.isEmpty {
            parts.append(mediaItem.genres.prefix(3).joined(separator: ", "))
        } else if !mediaItem.categories.isEmpty {
            parts.append(mediaItem.categories.prefix(3).joined(separator: ", "))
        }

        if parts.isEmpty {
            return mediaItem.status == .unknown ? mediaItem.type.rawValue.capitalized : mediaItem.status.rawValue.capitalized
        }
        return parts.joined(separator: " · ")
    }

    var confidencePercent: Int? {
        guard let mediaItem else { return nil }
        return Int((mediaItem.confidence * 100).rounded())
    }

    init(bookmark: Bookmark, section: MediaSpaceSectionKind, reason: String) {
        id = bookmark.id.uuidString
        mediaItem = nil
        self.bookmark = bookmark
        self.section = section
        self.reason = reason
    }

    init(mediaItem: MediaItem, sourceBookmark: Bookmark?, section: MediaSpaceSectionKind, reason: String) {
        id = mediaItem.id
        self.mediaItem = mediaItem
        bookmark = sourceBookmark ?? Bookmark(
            title: mediaItem.title,
            urlString: mediaItem.sourceURLs.first ?? "",
            thumbnailRemoteURLString: mediaItem.coverImageURL,
            thumbnailRelativePath: mediaItem.posterImagePath
        )
        self.section = section
        self.reason = reason
    }
}

private extension String {
    var ciderDroppingWWWPrefix: String {
        hasPrefix("www.") ? String(dropFirst(4)) : self
    }
}

struct MediaTasteSignal: Identifiable, Hashable {
    let note: Note
    let section: MediaSpaceSectionKind
    let reason: String

    var id: UUID { note.id }
}

struct MediaSpaceSectionSummary: Identifiable, Hashable {
    let section: MediaSpaceSectionKind
    let items: [MediaSpaceItem]
    let tasteSignals: [MediaTasteSignal]

    var id: MediaSpaceSectionKind { section }
    var count: Int { items.count + tasteSignals.count }
    var previewItems: [MediaSpaceItem] { Array(items.prefix(8)) }
}

struct MediaSpaceSourceSummary: Identifiable, Hashable {
    let host: String
    let count: Int

    var id: String { host }
}

struct MediaSpaceStatusSummary: Identifiable, Hashable {
    let status: MediaItemStatus
    let count: Int

    var id: MediaItemStatus { status }

    var displayName: String {
        switch status {
        case .unknown: "Unknown"
        case .want: "Want"
        case .consuming: "In Progress"
        case .completed: "Completed"
        case .paused: "Paused"
        case .abandoned: "Abandoned"
        case .favorite: "Favorite"
        }
    }
}

struct MediaSpaceRecommendedAction: Identifiable, Hashable {
    let section: MediaSpaceSectionKind
    let title: String
    let message: String
    let actionLabel: String
    let systemImage: String

    var id: String { "\(section.rawValue)-\(title)" }
}

struct MediaSpaceDashboardModel: Equatable {
    let summaries: [MediaSpaceSectionSummary]

    static let empty = MediaSpaceDashboardModel(
        summaries: MediaSpaceSectionKind.allCases.map {
            MediaSpaceSectionSummary(section: $0, items: [], tasteSignals: [])
        }
    )

    var totalMediaItems: Int {
        summaries
            .filter { $0.section != .tasteProfile }
            .reduce(0) { $0 + $1.items.count }
    }

    var featuredItems: [MediaSpaceItem] {
        let preferred: [MediaSpaceSectionKind] = [.movies, .shows, .games, .books, .references]
        return preferred
            .flatMap { items(for: $0).prefix(4) }
            .prefix(12)
            .map { $0 }
    }

    var needsSortingCount: Int {
        items(for: .inbox).count
    }

    var reviewItems: [MediaSpaceItem] {
        items(for: .inbox)
    }

    var allItems: [MediaSpaceItem] {
        summaries.flatMap(\.items)
    }

    var structuredItemCount: Int {
        allItems.filter { $0.detailMode == .structuredMediaItem }.count
    }

    var sourceOnlyItemCount: Int {
        allItems.filter { $0.detailMode == .sourceBookmark }.count
    }

    var sourceSummaries: [MediaSpaceSourceSummary] {
        var counts: [String: Int] = [:]
        var orderedHosts: [String] = []

        for item in allItems {
            let host = item.sourceSubtitle.isEmpty ? "Unknown source" : item.sourceSubtitle
            if counts[host] == nil {
                orderedHosts.append(host)
            }
            counts[host, default: 0] += 1
        }

        return orderedHosts
            .map { MediaSpaceSourceSummary(host: $0, count: counts[$0, default: 0]) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                guard let lhsIndex = orderedHosts.firstIndex(of: lhs.host), let rhsIndex = orderedHosts.firstIndex(of: rhs.host) else {
                    return lhs.host < rhs.host
                }
                return lhsIndex < rhsIndex
            }
    }

    var statusBreakdown: [MediaSpaceStatusSummary] {
        let statuses = allItems.compactMap(\.mediaItem?.status).filter { $0 != .unknown }
        let counts = Dictionary(statuses.map { ($0, 1) }, uniquingKeysWith: +)
        let preferredOrder: [MediaItemStatus] = [.want, .consuming, .favorite, .completed, .paused, .abandoned]

        return preferredOrder.compactMap { status in
            guard let count = counts[status], count > 0 else { return nil }
            return MediaSpaceStatusSummary(status: status, count: count)
        }
    }

    var recommendedActions: [MediaSpaceRecommendedAction] {
        var actions: [MediaSpaceRecommendedAction] = []

        if needsSortingCount > 0 {
            actions.append(MediaSpaceRecommendedAction(
                section: .inbox,
                title: "Review \(needsSortingCount) ambiguous \(needsSortingCount == 1 ? "save" : "saves")",
                message: "Keep conservative media guesses out of the wrong shelf.",
                actionLabel: "Sort now",
                systemImage: "tray.full"
            ))
        }

        let tasteCount = tasteSignals().count
        if tasteCount > 0 {
            actions.append(MediaSpaceRecommendedAction(
                section: .tasteProfile,
                title: "Review \(tasteCount) taste \(tasteCount == 1 ? "signal" : "signals")",
                message: "Turn favorites and Hermes context into reviewable media ideas later.",
                actionLabel: "Open signals",
                systemImage: "sparkles"
            ))
        }

        let seedSections: [MediaSpaceSectionKind] = [.movies, .shows, .games, .books, .references]
        for section in seedSections where items(for: section).isEmpty {
            actions.append(MediaSpaceRecommendedAction(
                section: section,
                title: "Seed \(section.displayName)",
                message: "Capture or identify saved \(section.displayName.lowercased()) so this shelf stops being empty.",
                actionLabel: "View shelf",
                systemImage: section.systemImage
            ))
        }

        return Array(actions.prefix(4))
    }

    func summary(for section: MediaSpaceSectionKind) -> MediaSpaceSectionSummary {
        summaries.first(where: { $0.section == section }) ?? MediaSpaceSectionSummary(
            section: section,
            items: [],
            tasteSignals: []
        )
    }

    func items(for section: MediaSpaceSectionKind) -> [MediaSpaceItem] {
        summary(for: section).items
    }

    func tasteSignals(for section: MediaSpaceSectionKind? = nil) -> [MediaTasteSignal] {
        let all = summary(for: .tasteProfile).tasteSignals
        guard let section else { return all }
        return all.filter { $0.section == section }
    }

    static func make(
        bookmarks: [Bookmark],
        mediaItems: [MediaItem] = [],
        notes: [Note] = []
    ) -> MediaSpaceDashboardModel {
        var grouped: [MediaSpaceSectionKind: [MediaSpaceItem]] = [:]

        if mediaItems.isEmpty {
            for bookmark in bookmarks {
                guard let classification = classify(bookmark) else { continue }
                grouped[classification.section, default: []].append(
                    MediaSpaceItem(
                        bookmark: bookmark,
                        section: classification.section,
                        reason: classification.reason
                    )
                )
            }
        } else {
            let bookmarksByID = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0) })
            let bookmarksByURL = Dictionary(bookmarks.map { ($0.urlString, $0) }, uniquingKeysWith: { first, _ in first })

            for item in mediaItems {
                let section = section(for: item.type)
                let sourceBookmark = item.sourceBookmarkIDs.compactMap { bookmarksByID[$0] }.first
                    ?? item.sourceURLs.compactMap { bookmarksByURL[$0] }.first
                grouped[section, default: []].append(
                    MediaSpaceItem(
                        mediaItem: item,
                        sourceBookmark: sourceBookmark,
                        section: section,
                        reason: item.identificationReason ?? "Structured MediaItem"
                    )
                )
            }

            let attachedBookmarkIDs = Set(mediaItems.flatMap(\.sourceBookmarkIDs))
            let attachedURLs = Set(mediaItems.flatMap(\.sourceURLs))
            for bookmark in bookmarks where !attachedBookmarkIDs.contains(bookmark.id) && !attachedURLs.contains(bookmark.urlString) {
                guard let classification = classify(bookmark), classification.section == .inbox else { continue }
                grouped[.inbox, default: []].append(
                    MediaSpaceItem(
                        bookmark: bookmark,
                        section: .inbox,
                        reason: classification.reason
                    )
                )
            }
        }

        let tasteSignals = classifyTasteSignals(notes)
        let summaries = MediaSpaceSectionKind.allCases.map { section in
            MediaSpaceSectionSummary(
                section: section,
                items: grouped[section, default: []].sorted(by: sortMediaItems),
                tasteSignals: section == .tasteProfile ? tasteSignals : []
            )
        }

        return MediaSpaceDashboardModel(summaries: summaries)
    }

    private static func sortMediaItems(_ lhs: MediaSpaceItem, _ rhs: MediaSpaceItem) -> Bool {
        if lhs.bookmark.thumbnailFileURL != nil && rhs.bookmark.thumbnailFileURL == nil { return true }
        if lhs.bookmark.thumbnailFileURL == nil && rhs.bookmark.thumbnailFileURL != nil { return false }
        if lhs.mediaItem != nil && rhs.mediaItem == nil { return true }
        if lhs.mediaItem == nil && rhs.mediaItem != nil { return false }
        return lhs.bookmark.updatedAt > rhs.bookmark.updatedAt
    }

    private static func section(for type: MediaItemType) -> MediaSpaceSectionKind {
        switch type {
        case .movie: .movies
        case .show: .shows
        case .game: .games
        case .book: .books
        case .reference: .references
        case .unknown: .inbox
        }
    }

    private static func classify(_ bookmark: Bookmark) -> (section: MediaSpaceSectionKind, reason: String)? {
        let host = bookmark.url?.host?.lowercased() ?? ""
        let fields = normalizedFields(for: bookmark, host: host)

        if containsAny(fields, [
            "store.steampowered.com", "steamcommunity.com", "itch.io", "gog.com",
            "epicgames.com", "nintendo.com", "playstation.com", "xbox.com"
        ]) || containsAnyWord(fields, ["game", "games", "gaming"]) {
            return (.games, host.contains("steam") ? "Steam or game save" : "Game signal")
        }

        if containsAny(fields, ["goodreads.com", "thestorygraph.com", "bookshop.org", "audible.com"])
            || containsAnyWord(fields, ["book", "books", "reading", "kindle", "author", "novel"]) {
            return (.books, "Book or reading signal")
        }

        if containsAny(fields, ["trakt.tv/shows"])
            || containsAnyWord(fields, ["tv", "episode", "episodes", "show", "shows"])
            || containsAnySeasonSignal(fields) {
            return (.shows, "Show or episode signal")
        }

        if containsAny(fields, ["letterboxd.com", "imdb.com/title", "themoviedb.org/movie", "rottentomatoes.com/m/"])
            || containsAnyWord(fields, ["movie", "movies", "film", "films", "cinema", "trailer", "watchlist"]) {
            return (.movies, "Movie or watchlist signal")
        }

        if containsAny(fields, [
            "youtube.com", "youtu.be", "vimeo.com", "polygon.com", "ign.com",
            "gamespot.com", "theverge.com", "reddit.com"
        ]) || containsAnyWord(fields, ["review", "essay", "criticism", "analysis", "interview", "retrospective"]) {
            return (.references, "Media reference")
        }

        if containsAnyWord(fields, ["media", "entertainment", "wishlist", "favorite", "favourite"]) {
            return (.inbox, "Media-ish save that needs sorting")
        }

        return nil
    }

    private static func classifyTasteSignals(_ notes: [Note]) -> [MediaTasteSignal] {
        notes.compactMap { note in
            let fields = MediaSpaceSignalFields([
                note.title,
                note.summary ?? "",
                note.content,
                note.relativePath,
                note.tags.joined(separator: " ")
            ])

            guard containsAnyWord(fields, ["favorite", "favorites", "favourite", "favourites", "like", "liked", "love", "loved", "recommendations"]) else {
                return nil
            }

            if containsAnyWord(fields, ["game", "games", "gaming", "steam"]) {
                return MediaTasteSignal(note: note, section: .games, reason: "Game preference signal")
            }
            if containsAnyWord(fields, ["movie", "movies", "film", "films", "cinema"]) {
                return MediaTasteSignal(note: note, section: .movies, reason: "Movie preference signal")
            }
            if containsAnyWord(fields, ["show", "shows", "series", "season", "tv"]) {
                return MediaTasteSignal(note: note, section: .shows, reason: "Show preference signal")
            }
            if containsAnyWord(fields, ["book", "books", "reading", "novel", "author"]) {
                return MediaTasteSignal(note: note, section: .books, reason: "Book preference signal")
            }
            if containsAnyWord(fields, ["media", "hermes", "recommendations"]) {
                return MediaTasteSignal(note: note, section: .references, reason: "Media taste source")
            }
            return nil
        }
        .sorted { $0.note.modifiedAt > $1.note.modifiedAt }
    }

    private static func normalizedFields(for bookmark: Bookmark, host: String) -> MediaSpaceSignalFields {
        MediaSpaceSignalFields([
            bookmark.title,
            bookmark.urlString,
            host
        ])
    }

    private static func containsAny(_ haystack: MediaSpaceSignalFields, _ needles: [String]) -> Bool {
        needles.contains { haystack.raw.contains($0) }
    }

    private static func containsAnyWord(_ haystack: MediaSpaceSignalFields, _ words: [String]) -> Bool {
        words.contains { haystack.words.contains($0) }
    }

    private static func containsAnySeasonSignal(_ haystack: MediaSpaceSignalFields) -> Bool {
        let patterns = [
            #"(?<![a-z0-9])s\d{1,2}\s*e\d{1,2}(?![a-z0-9])"#,
            #"(?<![a-z0-9])season\s+\d{1,2}(?![a-z0-9])"#,
            #"(?<![a-z0-9])season\s+(one|two|three|four|five|six|seven|eight|nine|ten)(?![a-z0-9])"#
        ]

        return patterns.contains { pattern in
            haystack.raw.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
}

private struct MediaSpaceSignalFields {
    let raw: String
    let words: Set<String>

    init(_ values: [String]) {
        raw = values.joined(separator: " ").lowercased()
        words = Set(
            raw.split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
        )
    }
}
