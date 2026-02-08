import Foundation
import CoreGraphics

/// Stores pre-tile window frames so they can be restored with the Restore hotkey.
/// LRU-capped at 50 entries.
@MainActor
final class WindowFrameHistory {
    static let shared = WindowFrameHistory()

    private var frames: [CGWindowID: CGRect] = [:]
    private var order: [CGWindowID] = []  // LRU order, most recent at end
    private let maxEntries = 50

    /// Save a window's current frame before tiling/resizing.
    func save(windowID: CGWindowID, frame: CGRect) {
        // If already tracked, remove from order to re-append at end
        if frames[windowID] != nil {
            order.removeAll { $0 == windowID }
        }

        frames[windowID] = frame
        order.append(windowID)

        // Evict oldest if over capacity
        while order.count > maxEntries {
            let evicted = order.removeFirst()
            frames.removeValue(forKey: evicted)
        }
    }

    /// Pop and return the saved frame for a window (used by restore).
    func restore(windowID: CGWindowID) -> CGRect? {
        guard let frame = frames.removeValue(forKey: windowID) else { return nil }
        order.removeAll { $0 == windowID }
        return frame
    }
}
