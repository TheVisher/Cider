import Foundation
import CoreSpotlight
import Combine
import os.log

@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private let index = CSSearchableIndex.default()
    private let logger = Logger(subsystem: "com.cider.app", category: "SpotlightIndexer")
    private var cancellables = Set<AnyCancellable>()
    private var indexedIDs = Set<String>()
    private var debounceTask: Task<Void, Never>?

    nonisolated static let bookmarkDomain = "com.cider.bookmarks"
    nonisolated static let noteDomain = "com.cider.notes"
    nonisolated static let dateCardDomain = "com.cider.datecards"
    nonisolated static let contactDomain = "com.cider.contacts"

    private init() {}

    func start() {
        guard CiderConfig.load().enableSpotlightIndexing else {
            deleteAll()
            return
        }
        // Clear any existing subscriptions to avoid stacking on repeated start() calls
        cancellables.removeAll()
        debounceTask?.cancel()
        bindStorages()
        reindexAll()
    }

    func stop() {
        cancellables.removeAll()
        debounceTask?.cancel()
        deleteAll()
    }

    // MARK: - Storage Bindings

    private func bindStorages() {
        BookmarksStorage.shared.$bookmarks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReindex() }
            .store(in: &cancellables)

        NotesStorage.shared.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReindex() }
            .store(in: &cancellables)

        DateCardStorage.shared.$dateCards
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReindex() }
            .store(in: &cancellables)

        ContactStorage.shared.$contacts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.scheduleReindex() }
            .store(in: &cancellables)
    }

    private func scheduleReindex() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            reindexAll()
        }
    }

    // MARK: - Indexing

    private func reindexAll() {
        guard CiderConfig.load().enableSpotlightIndexing else { return }

        // Snapshot data on main actor, then load heavy data (thumbnails, note content)
        // off-main to avoid blocking the UI. Index items are built on main after.
        let bookmarks = BookmarksStorage.shared.bookmarks
        let notes = NotesStorage.shared.notes
        let dateCards = DateCardStorage.shared.dateCards
        let contacts = ContactStorage.shared.contacts

        // Load note content on main actor (string reads, fast)
        let noteContents: [UUID: String] = Dictionary(
            notes.map { ($0.id, NotesStorage.shared.loadContent(for: $0)) },
            uniquingKeysWith: { _, b in b }
        )

        // Collect thumbnail URLs for off-main disk I/O
        let thumbURLs: [UUID: URL] = Dictionary(
            bookmarks.compactMap { b in b.thumbnailFileURL.map { (b.id, $0) } },
            uniquingKeysWith: { _, b in b }
        )

        Task { [weak self] in
            // Load thumbnail data off main thread (disk I/O)
            let thumbDataMap: [UUID: Data] = await Task.detached(priority: .utility) {
                var result: [UUID: Data] = [:]
                for (id, url) in thumbURLs {
                    if let data = try? Data(contentsOf: url) {
                        result[id] = data
                    }
                }
                return result
            }.value

            guard let self else { return }

            // Build and submit index items on main actor
            self.buildAndSubmitIndex(
                bookmarks: bookmarks,
                notes: notes,
                dateCards: dateCards,
                contacts: contacts,
                thumbDataMap: thumbDataMap,
                noteContents: noteContents
            )
        }
    }

    private func buildAndSubmitIndex(
        bookmarks: [Bookmark],
        notes: [Note],
        dateCards: [DateCard],
        contacts: [ContactCard],
        thumbDataMap: [UUID: Data],
        noteContents: [UUID: String]
    ) {
        var items: [CSSearchableItem] = []
        var newIDs = Set<String>()

        // Bookmarks
        for bookmark in bookmarks {
            let uniqueID = "cider.bookmark.\(bookmark.id.uuidString)"
            newIDs.insert(uniqueID)

            let attrs = CSSearchableItemAttributeSet(contentType: .url)
            attrs.title = bookmark.title
            attrs.contentURL = URL(string: bookmark.urlString)
            attrs.contentDescription = bookmark.notes.isEmpty ? nil : bookmark.notes
            attrs.keywords = bookmark.tags.isEmpty ? nil : bookmark.tags
            attrs.thumbnailData = thumbDataMap[bookmark.id]

            let item = CSSearchableItem(
                uniqueIdentifier: uniqueID,
                domainIdentifier: Self.bookmarkDomain,
                attributeSet: attrs
            )
            items.append(item)
        }

        // Notes
        for note in notes {
            let uniqueID = "cider.note.\(note.id.uuidString)"
            newIDs.insert(uniqueID)

            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = note.title
            let content = noteContents[note.id] ?? ""
            let stripped = NoteCardData.stripMarkup(content)
            attrs.contentDescription = String(stripped.prefix(500))

            let item = CSSearchableItem(
                uniqueIdentifier: uniqueID,
                domainIdentifier: Self.noteDomain,
                attributeSet: attrs
            )
            items.append(item)
        }

        // Date Cards
        for dateCard in dateCards {
            let uniqueID = "cider.datecard.\(dateCard.id.uuidString)"
            newIDs.insert(uniqueID)

            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = dateCard.title
            var desc = dateCard.details
            if !dateCard.location.isEmpty {
                desc += desc.isEmpty ? dateCard.location : " — \(dateCard.location)"
            }
            attrs.contentDescription = desc.isEmpty ? nil : desc
            attrs.startDate = dateCard.startAt

            let item = CSSearchableItem(
                uniqueIdentifier: uniqueID,
                domainIdentifier: Self.dateCardDomain,
                attributeSet: attrs
            )
            items.append(item)
        }

        // Contacts
        for contact in contacts {
            let uniqueID = "cider.contact.\(contact.id.uuidString)"
            newIDs.insert(uniqueID)

            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = contact.displayName
            var desc = contact.relationshipLabel
            if !contact.notes.isEmpty {
                desc += desc.isEmpty ? contact.notes : " — \(contact.notes)"
            }
            attrs.contentDescription = desc.isEmpty ? nil : desc

            let item = CSSearchableItem(
                uniqueIdentifier: uniqueID,
                domainIdentifier: Self.contactDomain,
                attributeSet: attrs
            )
            items.append(item)
        }

        // Delete removed items
        let removedIDs = indexedIDs.subtracting(newIDs)
        if !removedIDs.isEmpty {
            let log = logger
            index.deleteSearchableItems(withIdentifiers: Array(removedIDs)) { error in
                if let error {
                    log.error("Delete error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // Index current items
        if !items.isEmpty {
            let log = logger
            index.indexSearchableItems(items) { error in
                if let error {
                    log.error("Index error: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        indexedIDs = newIDs
    }

    private func deleteAll() {
        let log = logger
        index.deleteAllSearchableItems { error in
            if let error {
                log.error("Delete all error: \(error.localizedDescription, privacy: .public)")
            }
        }
        indexedIDs.removeAll()
    }

    // MARK: - Deep Link Handling

    /// Handle a Spotlight deep link. Returns true if the activity was handled.
    static func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
              let uniqueID = userActivity.userInfo?[CSSearchableItemActivityIdentifier] as? String else {
            return false
        }

        // Parse item type and ID from "cider.bookmark.UUID" format
        let parts = uniqueID.split(separator: ".", maxSplits: 2)
        guard parts.count == 3,
              parts[0] == "cider",
              let itemID = UUID(uuidString: String(parts[2])) else {
            return false
        }

        let itemType = String(parts[1])

        // Show the panel
        NotificationCenter.default.post(name: .toggleCiderPanel, object: nil)

        // Navigate to the item based on type
        switch itemType {
        case "bookmark":
            if let bookmark = BookmarksStorage.shared.bookmarks.first(where: { $0.id == itemID }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(
                        name: .openBookmarkDetails,
                        object: nil,
                        userInfo: ["bookmarkID": bookmark.id]
                    )
                }
            }
        case "note":
            if let note = NotesStorage.shared.notes.first(where: { $0.id == itemID }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .toggleNoteEditor, object: note)
                }
            }
        case "datecard":
            // Open panel — date card will be visible in the feed
            break
        case "contact":
            // Open panel — contact will be visible in the feed
            break
        default:
            return false
        }

        return true
    }
}
