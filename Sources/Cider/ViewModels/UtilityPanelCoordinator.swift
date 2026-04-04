import Foundation
import SwiftUI
import os

private let logger = Logger(subsystem: "com.cider.app", category: "UtilityPanelCoordinator")

// MARK: - Active Item

enum UtilityPanelActiveItem: Equatable {
    case bookmark(UUID)
    case note(UUID)
    case todo(UUID)

    var itemID: UUID {
        switch self {
        case .bookmark(let id), .note(let id), .todo(let id): return id
        }
    }

    var panelItemType: PanelItemType {
        switch self {
        case .bookmark: return .bookmark
        case .note: return .note
        case .todo: return .todo
        }
    }

    var historyType: PanelHistoryType {
        .item(itemID: itemID)
    }
}

// MARK: - Coordinator

@MainActor
final class UtilityPanelCoordinator: ObservableObject {
    let buffer = DotBuffer()
    let history = PanelHistory()

    /// The currently displayed item (nil = placeholder/tool mode)
    @Published private(set) var activeItem: UtilityPanelActiveItem?

    /// The currently active tool mode (nil = showing an item or placeholder)
    @Published private(set) var activeTool: ToolMode?

    /// The two items shown side-by-side in split view (nil = not in split mode)
    @Published private(set) var splitItems: (UtilityPanelActiveItem, UtilityPanelActiveItem)?

    /// Preferred panel width for the current mode. Nil = keep current width.
    var preferredWidth: CGFloat? {
        if splitItems != nil { return UtilityPanelDesign.splitDefaultWidth }
        guard let tool = activeTool else { return nil }
        return switch tool {
        case .aiChat: AIAssistantPanelDesign.defaultWidth
        case .clipboard: ClipboardPanelDesign.narrowWidth
        case .search, .capture: nil
        }
    }

    // MARK: - Search State

    /// Persists across back/forward so returning to search shows the same results
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []

    /// Map from dot slot itemID → UtilityPanelActiveItem (to recover type info from history)
    private var itemTypeMap: [UUID: UtilityPanelActiveItem] = [:]

    /// Stores the last-known title for each item so back/forward can restore evicted items
    private var titleMap: [UUID: String] = [:]

    // MARK: - Open Item

    /// Look up the UtilityPanelActiveItem for a dot slot (for context menu wiring)
    func itemForSlot(_ slot: DotSlot) -> UtilityPanelActiveItem? {
        itemTypeMap[slot.itemID]
    }

    func openItem(_ item: UtilityPanelActiveItem, title: String) {
        collapseSplit()
        activeTool = nil

        let slot = DotSlot(
            itemID: item.itemID,
            itemType: item.panelItemType,
            title: title
        )

        let result = buffer.open(item: slot)

        switch result {
        case .opened, .focused:
            itemTypeMap[item.itemID] = item
            titleMap[item.itemID] = title
            activeItem = item
            history.push(PanelHistoryEntry(type: item.historyType))
            logger.debug("Opened \(title) in utility panel")

        case .rejected:
            logger.info("Utility panel full — item rejected: \(title)")
        }
    }

    // MARK: - Tool Mode

    func openTool(_ tool: ToolMode) {
        collapseSplit()
        activeTool = tool
        activeItem = nil
        buffer.activeIndex = nil
        history.push(PanelHistoryEntry(type: .tool(tool)))
        logger.debug("Opened tool: \(tool.rawValue)")
    }

    func openSearchInPanel(query: String, results: [SearchResult]) {
        searchQuery = query
        searchResults = results
        openTool(.search)
    }

    /// Maps a SearchResult to the appropriate item type and opens it in detail mode.
    func openSearchResultAsItem(_ result: SearchResult) {
        let item: UtilityPanelActiveItem? = switch result.type {
        case .bookmark: .bookmark(result.id)
        case .note: .note(result.id)
        case .todo: .todo(result.id)
        default: nil
        }

        guard let item else {
            logger.info("No detail view for search result type: \(String(describing: result.type))")
            return
        }

        openItem(item, title: result.title)
    }

    // MARK: - Navigation

    func goBack() {
        guard let entry = history.back() else { return }
        navigateToEntry(entry)
    }

    func goForward() {
        guard let entry = history.forward() else { return }
        navigateToEntry(entry)
    }

    // MARK: - Close Active

    func closeActive() {
        if activeTool != nil {
            activeTool = nil
            // Restore the most recent dot item if one exists
            if let lastIndex = buffer.slots.lastIndex(where: { $0 != nil }),
               let slot = buffer.slots[lastIndex],
               let item = itemTypeMap[slot.itemID] {
                buffer.activeIndex = lastIndex
                activeItem = item
            }
            return
        }
        if splitItems != nil {
            if let pair = buffer.linkedPair {
                let id1 = buffer.slots[pair.0]?.itemID
                let id2 = buffer.slots[pair.1]?.itemID
                buffer.unlink()
                buffer.clear(at: pair.0)
                buffer.clear(at: pair.1)
                if let id1 { itemTypeMap.removeValue(forKey: id1) }
                if let id2 { itemTypeMap.removeValue(forKey: id2) }
            }
            splitItems = nil
            return
        }
        guard let activeItem else { return }
        if let index = buffer.index(of: activeItem.itemID) {
            buffer.clear(at: index)
        }
        itemTypeMap.removeValue(forKey: activeItem.itemID)
        self.activeItem = nil
    }

    // MARK: - Dot Tap

    /// Called when user clicks a dot directly.
    func activateDot(at index: Int) {
        guard let slot = buffer.slots[index] else { return }
        // If tapping a dot that IS part of the current split, do nothing
        if splitItems != nil && buffer.isLinked(index) { return }
        // If tapping a dot that's NOT part of the split, collapse it
        if splitItems != nil { collapseSplit() }
        activeTool = nil
        buffer.activeIndex = index
        if let item = itemTypeMap[slot.itemID] {
            activeItem = item
            history.push(PanelHistoryEntry(type: item.historyType))
        }
    }

    // MARK: - Split View

    func openSplitView(item1: UtilityPanelActiveItem, item2: UtilityPanelActiveItem) {
        guard item1.itemID != item2.itemID else {
            logger.info("Split view requires two distinct items")
            return
        }
        collapseSplit()
        activeTool = nil
        activeItem = nil

        let title1 = titleMap[item1.itemID] ?? "Item"
        let title2 = titleMap[item2.itemID] ?? "Item"
        let slot1 = DotSlot(itemID: item1.itemID, itemType: item1.panelItemType, title: title1)
        let slot2 = DotSlot(itemID: item2.itemID, itemType: item2.panelItemType, title: title2)

        let r1 = buffer.open(item: slot1)
        if case .rejected = r1 {
            logger.info("Split view rejected — cannot open first item")
            return
        }
        let r2 = buffer.open(item: slot2)
        if case .rejected = r2 {
            logger.info("Split view rejected — cannot open second item")
            return
        }

        guard let i1 = buffer.index(of: item1.itemID),
              let i2 = buffer.index(of: item2.itemID) else { return }

        buffer.link(i1, i2)
        itemTypeMap[item1.itemID] = item1
        itemTypeMap[item2.itemID] = item2
        splitItems = (item1, item2)
        history.push(PanelHistoryEntry(type: .splitView(itemID1: item1.itemID, itemID2: item2.itemID)))
        logger.debug("Opened split view: \(title1) vs \(title2)")
    }

    // MARK: - Private

    private func collapseSplit() {
        guard splitItems != nil else { return }
        buffer.unlink()
        splitItems = nil
    }

    private func navigateToEntry(_ entry: PanelHistoryEntry) {
        switch entry.type {
        case .item(let itemID):
            activeTool = nil
            if let item = itemTypeMap[itemID] {
                let title = titleMap[itemID]
                    ?? buffer.slots.compactMap({ $0 }).first(where: { $0.itemID == itemID })?.title
                    ?? "Item"
                let slot = DotSlot(
                    itemID: itemID,
                    itemType: item.panelItemType,
                    title: title
                )
                let result = buffer.open(item: slot)
                if case .rejected = result {
                    logger.info("Cannot restore evicted item — all slots full")
                    return
                }
                activeItem = item
            }

        case .splitView(let itemID1, let itemID2):
            activeTool = nil
            collapseSplit()
            guard let item1 = itemTypeMap[itemID1],
                  let item2 = itemTypeMap[itemID2] else {
                logger.info("Cannot restore split — item type info missing")
                return
            }
            let title1 = titleMap[itemID1] ?? "Item"
            let title2 = titleMap[itemID2] ?? "Item"
            let slot1 = DotSlot(itemID: itemID1, itemType: item1.panelItemType, title: title1)
            let slot2 = DotSlot(itemID: itemID2, itemType: item2.panelItemType, title: title2)
            let r1 = buffer.open(item: slot1)
            if case .rejected = r1 { return }
            let r2 = buffer.open(item: slot2)
            if case .rejected = r2 { return }
            if let i1 = buffer.index(of: itemID1), let i2 = buffer.index(of: itemID2) {
                buffer.link(i1, i2)
                activeItem = nil
                splitItems = (item1, item2)
            }

        case .tool(let mode):
            activeTool = mode
            activeItem = nil
            buffer.activeIndex = nil
        }
    }
}
