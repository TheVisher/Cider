import Foundation

// MARK: - Item Type (for dot color coding)

enum PanelItemType: String, Sendable {
    case bookmark
    case note
    case todo
    case image
    case contact
    case event
}

// MARK: - Dot Slot

struct DotSlot: Identifiable, Sendable {
    let id: UUID
    let itemID: UUID
    let itemType: PanelItemType
    let title: String
    var isPinned: Bool
    var canEvict: Bool

    init(
        id: UUID = UUID(),
        itemID: UUID,
        itemType: PanelItemType,
        title: String,
        isPinned: Bool = false,
        canEvict: Bool = true
    ) {
        self.id = id
        self.itemID = itemID
        self.itemType = itemType
        self.title = title
        self.isPinned = isPinned
        self.canEvict = canEvict
    }
}

// MARK: - Open Result

enum DotBufferOpenResult: Sendable, Equatable {
    case opened(index: Int)
    case focused(index: Int)
    case rejected
}

// MARK: - Dot Buffer

@MainActor
final class DotBuffer: ObservableObject {

    static let capacity = 5

    @Published private(set) var slots: [DotSlot?] = Array(repeating: nil, count: capacity)
    @Published var activeIndex: Int?

    /// Insertion order counter — used to determine which unpinned dot is oldest.
    private var insertionOrder: [Int: UInt64] = [:]
    private var nextOrder: UInt64 = 0

    // MARK: - Open

    /// Opens an item into the dot buffer.
    /// - Returns dedup (focused), opened, or rejected.
    @discardableResult
    func open(item: DotSlot) -> DotBufferOpenResult {
        // Dedup: if item already has a dot, focus it
        if let existing = slots.firstIndex(where: { $0?.itemID == item.itemID }) {
            activeIndex = existing
            return .focused(index: existing)
        }

        // Find first empty slot
        if let empty = slots.firstIndex(where: { $0 == nil }) {
            place(item, at: empty)
            return .opened(index: empty)
        }

        // Evict oldest unpinned, evictable slot
        if let victim = oldestEvictableIndex() {
            place(item, at: victim)
            return .opened(index: victim)
        }

        // All pinned or non-evictable — reject
        return .rejected
    }

    // MARK: - Pin / Unpin

    func pin(at index: Int) {
        guard slots.indices.contains(index), slots[index] != nil else { return }
        slots[index]?.isPinned = true
    }

    func unpin(at index: Int) {
        guard slots.indices.contains(index), slots[index] != nil else { return }
        slots[index]?.isPinned = false
    }

    // MARK: - Eviction Control

    func setCanEvict(_ canEvict: Bool, at index: Int) {
        guard slots.indices.contains(index), slots[index] != nil else { return }
        slots[index]?.canEvict = canEvict
    }

    // MARK: - Clear

    func clear(at index: Int) {
        guard slots.indices.contains(index) else { return }
        slots[index] = nil
        insertionOrder.removeValue(forKey: index)
        if activeIndex == index {
            activeIndex = nil
        }
    }

    func clearAll() {
        slots = Array(repeating: nil, count: Self.capacity)
        insertionOrder.removeAll()
        nextOrder = 0
        activeIndex = nil
    }

    // MARK: - Queries

    var filledCount: Int {
        slots.compactMap { $0 }.count
    }

    var allPinnedOrNonEvictable: Bool {
        slots.compactMap { $0 }.allSatisfy { $0.isPinned || !$0.canEvict }
    }

    func index(of itemID: UUID) -> Int? {
        slots.firstIndex { $0?.itemID == itemID }
    }

    // MARK: - Private

    private func place(_ item: DotSlot, at index: Int) {
        slots[index] = item
        insertionOrder[index] = nextOrder
        nextOrder += 1
        activeIndex = index
    }

    private func oldestEvictableIndex() -> Int? {
        var oldest: Int?
        var oldestOrder: UInt64 = .max

        for (index, slot) in slots.enumerated() {
            guard let slot, !slot.isPinned, slot.canEvict else { continue }
            let order = insertionOrder[index] ?? 0
            if order < oldestOrder {
                oldestOrder = order
                oldest = index
            }
        }
        return oldest
    }
}
