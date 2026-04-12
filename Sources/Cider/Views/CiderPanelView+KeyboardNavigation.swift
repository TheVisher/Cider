import SwiftUI
import AppKit
import WebKit

extension CiderPanelView {

    // MARK: - Keyboard Navigation

    func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            handleKeyDown(event)
        }
    }

    func removeKeyboardMonitor() {
        if let monitor = keyboardMonitor {
            NSEvent.removeMonitor(monitor)
            keyboardMonitor = nil
        }
    }

    /// Whether the first responder is a text field or its field editor
    private var isTextFieldFocused: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if responder is WKWebView { return true }
        if responder is NSTextField { return true }
        if let textView = responder as? NSTextView {
            // NSTextView is used as field editor for NSTextField (sidebar search)
            // and also for standalone text editors. Check if it's a field editor.
            return textView.isFieldEditor || textView.superview?.superview is NSTextField
        }
        return false
    }

    /// Whether the focused text field has non-empty content
    private var textFieldHasContent: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        if let textView = responder as? NSTextView { return !textView.string.isEmpty }
        if let textField = responder as? NSTextField { return !textField.stringValue.isEmpty }
        return false
    }

    /// Whether an arrow key at the current cursor position should escape the text field
    /// and transfer to card navigation. Up/Down always escape (single-line field).
    /// Left escapes at position 0, Right escapes at end of text.
    private func arrowEscapesTextField(_ keyCode: UInt16) -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        let range = responder.selectedRange()
        let length = responder.string.count
        switch keyCode {
        case 126, 125: // Up / Down — always escape single-line search field
            return true
        case 124: // Right — escape when cursor is at end with no selection
            return range.location >= length && range.length == 0
        case 123: // Left — escape when cursor is at start with no selection
            return range.location == 0 && range.length == 0
        default:
            return false
        }
    }

    func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let isArrowKey = event.keyCode >= 123 && event.keyCode <= 126

        // When a text field has content, let most keys go to it.
        // Arrow keys escape to card nav when at text boundaries (e.g. Right at end of text).
        if textFieldHasContent {
            if isArrowKey && arrowEscapesTextField(event.keyCode) {
                // Fall through to card navigation below
            } else {
                return event
            }
        }

        // When a text field is focused but empty, intercept navigation keys for card nav.
        // If the user is actively navigating (focusedItemID set), also intercept action keys
        // (Enter, Delete, Tab, Space) so they act on the focused card, not the text field.
        let isActionKey = focusedItemID != nil && [36, 76, 51, 117, 48, 49].contains(event.keyCode)
        if isTextFieldFocused && !isArrowKey && !isActionKey { return event }

        // Skip if search palette or detail view is open
        guard !isSearchPaletteVisible, !isAnyDetailOpen else { return event }

        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers ?? ""

        switch event.keyCode {
        case 126: // Up arrow
            handleArrowKey(.up, shift: shift)
            return nil
        case 125: // Down arrow
            handleArrowKey(.down, shift: shift)
            return nil
        case 123: // Left arrow
            handleArrowKey(.left, shift: shift)
            return nil
        case 124: // Right arrow
            handleArrowKey(.right, shift: shift)
            return nil
        case 36, 76: // Return / Enter
            handleEnterKey()
            return nil
        case 51, 117: // Backspace / Forward Delete
            // Delete focused item even if not explicitly selected
            if selectedItemIDs.isEmpty, let focused = focusedItemID {
                selectedItemIDs = [focused]
            }
            guard !selectedItemIDs.isEmpty else { return event }
            deleteSelectedItems()
            focusedItemID = nil
            selectionAnchorID = nil
            return nil
        case 48: // Tab
            handleTabKey(shift: shift)
            return nil
        case 49 where chars == " ": // Space — toggle selection
            handleSpaceKey()
            return nil
        default:
            return event
        }
    }

    /// Ordered IDs of items in the current content area
    var navigableItemIDs: [String] {
        if let folderID = selectedFolderID {
            let bookmarks = bookmarksViewModel.bookmarks.filter { $0.folderID == folderID }
                .map { LibraryItemV2.bookmark($0) }
            let notes = notesViewModel.notes.filter { $0.folderID == folderID }
                .map { LibraryItemV2.note($0) }
            let dateCards = DateCardStorage.shared.dateCards.filter { $0.folderID == folderID }
                .map { LibraryItemV2.dateCard($0) }
            let contacts = ContactStorage.shared.contacts.filter { $0.folderID == folderID }
                .map { LibraryItemV2.contact($0) }
            let sessions = BrowserSessionStorage.shared.sessions.filter { $0.folderID == folderID }
                .map { LibraryItemV2.session($0) }
            var all = (bookmarks + notes + dateCards + contacts + sessions)
                .sorted { $0.createdDate > $1.createdDate }

            let query = debouncedSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty {
                let scope = SearchService.parseScope(from: query)
                if let scopeTypes = scope.entityTypes {
                    all = all.filter { item in
                        switch item {
                        case .bookmark:     return scopeTypes.contains(.bookmark)
                        case .note:         return scopeTypes.contains(.note)
                        case .dateCard:     return scopeTypes.contains(.dateCard)
                        case .contact:      return scopeTypes.contains(.contact)
                        case .todo:         return scopeTypes.contains(.todo)
                        case .session:      return scopeTypes.contains(.session)
                        case .vaultFile: return false
                        }
                    }
                }
                if let labelID = scope.labelID {
                    all = all.filter { $0.labelIDs.contains(labelID) }
                }
                if !scope.cleanQuery.isEmpty {
                    all = all.filter { LibraryViewModel.matchesTextQuery(scope.cleanQuery, in: $0) }
                }
            }
            return all.map(\.id)
        } else if let tab = selectedTab, let savedViewID = tab.savedViewID {
            if let savedView = savedViewStorage.savedView(for: savedViewID), !savedView.isBlank, !savedView.isOnboarding {
                let filterSpec = SavedViewFilterSpec(
                    entityTypes: savedView.filterSpec.entityTypes.isEmpty
                        ? Set(LibraryEntityType.allCases) : savedView.filterSpec.entityTypes,
                    labelIDs: savedView.filterSpec.labelIDs,
                    includeCompleted: true,
                    textQuery: debouncedSearchText,
                    onlyUnassigned: savedView.filterSpec.onlyUnassigned
                )
                let sortSpec = SavedViewSortSpec(mode: savedView.sortSpec.mode)
                return libraryViewModel.filteredItems(using: filterSpec, sort: sortSpec).map(\.id)
            }
            return []
        } else {
            return []
        }
    }

    /// Column count for current display mode and content width
    var currentColumnCount: Int {
        if homeDisplayMode == .list { return 1 }
        let minWidth = LibraryCardSizing(scale: homeCardSizeScale).cardMinWidth
        let spacing = Spacing.md
        let availableWidth = contentAreaWidth - (Spacing.md + Spacing.xxs) * 2
        return max(1, Int(floor((availableWidth + spacing) / (minWidth + spacing))))
    }

    private func handleArrowKey(_ direction: KeyboardNavigation.Direction, shift: Bool) {
        let items = navigableItemIDs
        guard !items.isEmpty else { return }

        // If nothing focused, focus first item (no selection)
        guard let current = focusedItemID, items.contains(current) else {
            let first = items[0]
            focusedItemID = first
            selectionAnchorID = first
            scrollToItemID = first
            return
        }

        guard let next = KeyboardNavigation.nextItem(
            from: current, in: items,
            columns: currentColumnCount,
            direction: direction
        ) else { return }

        focusedItemID = next
        scrollToItemID = next

        if shift {
            // Shift+Arrow: range select from anchor to new position
            let anchor = selectionAnchorID ?? current
            selectedItemIDs = KeyboardNavigation.rangeSelection(from: anchor, to: next, in: items)
        } else {
            // Plain arrow: move focus only, clear selection
            selectionAnchorID = next
            selectedItemIDs = []
        }
    }

    private func handleTabKey(shift: Bool) {
        let items = navigableItemIDs
        guard !items.isEmpty else { return }

        guard let current = focusedItemID, items.contains(current) else {
            let first = items[0]
            focusedItemID = first
            selectionAnchorID = first
            scrollToItemID = first
            return
        }

        let next: String?
        if shift {
            next = KeyboardNavigation.linearPrevious(from: current, in: items)
        } else {
            next = KeyboardNavigation.linearNext(from: current, in: items)
        }
        guard let next else { return }

        focusedItemID = next
        selectionAnchorID = next
        selectedItemIDs = []
        scrollToItemID = next
    }

    private func handleEnterKey() {
        guard let id = focusedItemID else { return }
        openItemByID(id)
    }

    private func handleSpaceKey() {
        guard let id = focusedItemID else { return }
        if selectedItemIDs.contains(id) {
            selectedItemIDs.remove(id)
        } else {
            selectedItemIDs.insert(id)
        }
    }

    func openItemByID(_ id: String) {
        if id.hasPrefix("bookmark-") {
            let uuidString = String(id.dropFirst("bookmark-".count))
            if let uuid = UUID(uuidString: uuidString),
               let bookmark = bookmarksViewModel.bookmarks.first(where: { $0.id == uuid }) {
                openBookmarkDetails(bookmark)
            }
        } else if id.hasPrefix("note-") {
            let uuidString = String(id.dropFirst("note-".count))
            if let uuid = UUID(uuidString: uuidString),
               let note = notesViewModel.notes.first(where: { $0.id == uuid }) {
                openNoteDetail(note)
            }
        } else if id.hasPrefix("datecard-") {
            let uuidString = String(id.dropFirst("datecard-".count))
            if let uuid = UUID(uuidString: uuidString),
               let dateCard = DateCardStorage.shared.dateCard(for: uuid) {
                openDateCardDetail(dateCard)
            }
        } else if id.hasPrefix("contact-") {
            let uuidString = String(id.dropFirst("contact-".count))
            if let uuid = UUID(uuidString: uuidString),
               let contact = ContactStorage.shared.contact(for: uuid) {
                openContactDetail(contact)
            }
        } else if id.hasPrefix("session-") {
            let uuidString = String(id.dropFirst("session-".count))
            if let uuid = UUID(uuidString: uuidString),
               let session = BrowserSessionStorage.shared.sessions.first(where: { $0.id == uuid }) {
                openSessionDetail(session)
            }
        }
    }

    // MARK: - Collapse State Sync

    func setCollapsed(_ collapsed: Bool) {
        isCollapsed = collapsed
    }
}
