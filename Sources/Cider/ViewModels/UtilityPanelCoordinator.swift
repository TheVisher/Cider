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

    // MARK: - Search State

    /// Persists across back/forward so returning to search shows the same results
    @Published var searchQuery: String = ""
    @Published var searchResults: [SearchResult] = []

    /// Map from dot slot itemID → UtilityPanelActiveItem (to recover type info from history)
    private var itemTypeMap: [UUID: UtilityPanelActiveItem] = [:]

    /// Stores the last-known title for each item so back/forward can restore evicted items
    private var titleMap: [UUID: String] = [:]

    // MARK: - Open Item

    func openItem(_ item: UtilityPanelActiveItem, title: String) {
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
        activeTool = nil
        buffer.activeIndex = index
        if let item = itemTypeMap[slot.itemID] {
            activeItem = item
            history.push(PanelHistoryEntry(type: item.historyType))
        }
    }

    // MARK: - Private

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

        case .splitView:
            // Phase 6 — not implemented yet
            break

        case .tool(let mode):
            activeTool = mode
            activeItem = nil
            buffer.activeIndex = nil
        }
    }
}
