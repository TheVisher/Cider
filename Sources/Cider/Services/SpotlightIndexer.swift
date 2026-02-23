import Foundation
import CoreSpotlight
import Combine

@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private let index = CSSearchableIndex.default()
    private var cancellables = Set<AnyCancellable>()
    private var indexedIDs = Set<String>()
    private var debounceTask: Task<Void, Never>?

    static let bookmarkDomain = "com.cider.bookmarks"
    static let noteDomain = "com.cider.notes"
    static let dateCardDomain = "com.cider.datecards"
    static let contactDomain = "com.cider.contacts"

    private init() {}

    func start() {
        guard CiderConfig.load().enableSpotlightIndexing else {
            deleteAll()
            return
        }
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

        var items: [CSSearchableItem] = []
        var newIDs = Set<String>()

        // Bookmarks
        for bookmark in BookmarksStorage.shared.bookmarks {
            let uniqueID = "cider.bookmark.\(bookmark.id.uuidString)"
            newIDs.insert(uniqueID)

            let attrs = CSSearchableItemAttributeSet(contentType: .url)
            attrs.title = bookmark.title
            attrs.contentURL = URL(string: bookmark.urlString)
            attrs.contentDescription = bookmark.notes.isEmpty ? nil : bookmark.notes
            attrs.keywords = bookmark.tags.isEmpty ? nil : bookmark.tags

            if let thumbURL = bookmark.thumbnailFileURL,
               let data = try? Data(contentsOf: thumbURL) {
                attrs.thumbnailData = data
            }

            let item = CSSearchableItem(
                uniqueIdentifier: uniqueID,
                domainIdentifier: Self.bookmarkDomain,
                attributeSet: attrs
            )
            items.append(item)
        }

        // Notes
        for note in NotesStorage.shared.notes {
            let uniqueID = "cider.note.\(note.id.uuidString)"
            newIDs.insert(uniqueID)

            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = note.title
            let content = NotesStorage.shared.loadContent(for: note)
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
        for dateCard in DateCardStorage.shared.dateCards {
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
        for contact in ContactStorage.shared.contacts {
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
            index.deleteSearchableItems(withIdentifiers: Array(removedIDs)) { error in
                if let error {
                    NSLog("[SpotlightIndexer] Delete error: \(error)")
                }
            }
        }

        // Index current items
        if !items.isEmpty {
            index.indexSearchableItems(items) { error in
                if let error {
                    NSLog("[SpotlightIndexer] Index error: \(error)")
                }
            }
        }

        indexedIDs = newIDs
    }

    private func deleteAll() {
        index.deleteAllSearchableItems { error in
            if let error {
                NSLog("[SpotlightIndexer] Delete all error: \(error)")
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
