import SwiftUI

extension CiderPanelView {

    // MARK: - Select All

    func selectAllVisibleItems() {
        if let folderID = selectedFolderID {
            let bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
            let notes = notesViewModel.notes.filter { $0.folderID == folderID }
            let dateCards = DateCardStorage.shared.dateCards.filter { $0.folderID == folderID }
            let contacts = ContactStorage.shared.contacts.filter { $0.folderID == folderID }
            for b in bookmarks { selectedItemIDs.insert("bookmark-\(b.id.uuidString)") }
            for n in notes { selectedItemIDs.insert("note-\(n.id.uuidString)") }
            for dc in dateCards { selectedItemIDs.insert("datecard-\(dc.id.uuidString)") }
            for c in contacts { selectedItemIDs.insert("contact-\(c.id.uuidString)") }
        } else if selectedTab != nil {
            for item in libraryViewModel.items {
                selectedItemIDs.insert(item.id)
            }
        }
    }

    // MARK: - Bulk Selection Actions

    func deleteSelectedItems() {
        var bookmarksToDelete: [Bookmark] = []
        var notesToDelete: [Note] = []
        var dateCardIDsToDelete: [UUID] = []
        var contactIDsToDelete: [UUID] = []
        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    bookmarksToDelete.append(bookmark)
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    notesToDelete.append(note)
                }
            } else if id.hasPrefix("datecard-") {
                let uuidString = String(id.dropFirst("datecard-".count))
                if let uuid = UUID(uuidString: uuidString) {
                    dateCardIDsToDelete.append(uuid)
                }
            } else if id.hasPrefix("contact-") {
                let uuidString = String(id.dropFirst("contact-".count))
                if let uuid = UUID(uuidString: uuidString) {
                    contactIDsToDelete.append(uuid)
                }
            }
        }

        // Collect ALL trash items into a single unified undo recording.
        // Don't use ViewModel bulk-delete methods — they each record their own
        // undo action, and CiderUndoManager only tracks one pending action.
        var allTrashItems: [TrashItem] = []

        if !bookmarksToDelete.isEmpty {
            let trashItems = VaultBookmarkService.shared.removeAll(bookmarksToDelete)
            allTrashItems.append(contentsOf: trashItems)
        }
        if !notesToDelete.isEmpty {
            let idsToDelete = Set(notesToDelete.map(\.id))
            if let selected = notesViewModel.selectedNote, idsToDelete.contains(selected.id) {
                notesViewModel.clearSelectedNote()
            }
            for note in notesToDelete {
                let trashItem = NotesStorage.shared.delete(note: note)
                allTrashItems.append(trashItem)
            }
        }
        for dcID in dateCardIDsToDelete {
            if let trashItem = DateCardStorage.shared.deleteDateCard(dcID) {
                allTrashItems.append(trashItem)
            }
        }
        for cID in contactIDsToDelete {
            if let trashItem = ContactStorage.shared.deleteContact(cID) {
                allTrashItems.append(trashItem)
            }
        }

        if !allTrashItems.isEmpty {
            CiderUndoManager.shared.record(.bulkDeletedToTrash(allTrashItems))
        }

        selectedItemIDs.removeAll()
    }

    func moveSelectedToFolder(_ folderID: UUID?) {
        var movedItemIDs = Set<String>()

        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    if bookmarksViewModel.assign(bookmark, toFolder: folderID) {
                        movedItemIDs.insert(id)
                    }
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    if notesViewModel.assignNote(note, toFolder: folderID) {
                        movedItemIDs.insert(id)
                    }
                }
            } else if id.hasPrefix("datecard-") {
                let uuidString = String(id.dropFirst("datecard-".count))
                if let uuid = UUID(uuidString: uuidString) {
                    if DateCardStorage.shared.assignDateCard(uuid, toFolder: folderID) {
                        movedItemIDs.insert(id)
                    }
                }
            } else if id.hasPrefix("contact-") {
                let uuidString = String(id.dropFirst("contact-".count))
                if let uuid = UUID(uuidString: uuidString) {
                    if ContactStorage.shared.assignContact(uuid, toFolder: folderID) {
                        movedItemIDs.insert(id)
                    }
                }
            }
        }

        selectedItemIDs.subtract(movedItemIDs)
    }

    // MARK: - Bulk Tag

    func toggleTagOnSelected(_ labelID: UUID) {
        let allHave = selectedItemsAllHaveLabel(labelID)
        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString) {
                    if allHave {
                        VaultBookmarkService.shared.removeLabel(uuid, labelID: labelID)
                    } else {
                        VaultBookmarkService.shared.assignLabel(uuid, labelID: labelID)
                    }
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString) {
                    if allHave {
                        NotesStorage.shared.removeLabel(uuid, labelID: labelID)
                    } else {
                        NotesStorage.shared.assignLabel(uuid, labelID: labelID)
                    }
                }
            } else if id.hasPrefix("datecard-") {
                let uuidString = String(id.dropFirst("datecard-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let card = DateCardStorage.shared.dateCard(for: uuid) {
                    var updated = card
                    if allHave {
                        updated.labelIDs.removeAll { $0 == labelID }
                    } else if !updated.labelIDs.contains(labelID) {
                        updated.labelIDs.append(labelID)
                    }
                    DateCardStorage.shared.updateDateCard(updated)
                }
            } else if id.hasPrefix("contact-") {
                let uuidString = String(id.dropFirst("contact-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let contact = ContactStorage.shared.contact(for: uuid) {
                    var updated = contact
                    if allHave {
                        updated.labelIDs.removeAll { $0 == labelID }
                    } else if !updated.labelIDs.contains(labelID) {
                        updated.labelIDs.append(labelID)
                    }
                    ContactStorage.shared.updateContact(updated)
                }
            }
        }
    }

    func selectedItemsAllHaveLabel(_ labelID: UUID) -> Bool {
        for id in selectedItemIDs {
            if id.hasPrefix("bookmark-") {
                let uuidString = String(id.dropFirst("bookmark-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                    if !bookmark.labelIDs.contains(labelID) { return false }
                }
            } else if id.hasPrefix("note-") {
                let uuidString = String(id.dropFirst("note-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                    if !note.labelIDs.contains(labelID) { return false }
                }
            } else if id.hasPrefix("datecard-") {
                let uuidString = String(id.dropFirst("datecard-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let card = DateCardStorage.shared.dateCard(for: uuid) {
                    if !card.labelIDs.contains(labelID) { return false }
                }
            } else if id.hasPrefix("contact-") {
                let uuidString = String(id.dropFirst("contact-".count))
                if let uuid = UUID(uuidString: uuidString),
                   let contact = ContactStorage.shared.contact(for: uuid) {
                    if !contact.labelIDs.contains(labelID) { return false }
                }
            }
        }
        return true
    }
}
