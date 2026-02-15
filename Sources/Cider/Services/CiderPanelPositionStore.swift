import AppKit

@MainActor
final class CiderPanelPositionStore {
    static let shared = CiderPanelPositionStore()

    private let storageKey = "CiderPanelFrame"
    private var cachedFrame: NSRect?

    private init() {
        loadFromDefaults()
    }

    func frame() -> NSRect? {
        cachedFrame
    }

    func setFrame(_ frame: NSRect) {
        cachedFrame = frame
        saveToDefaults()
    }

    func clear() {
        cachedFrame = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func loadFromDefaults() {
        guard let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double],
              let x = raw["x"],
              let y = raw["y"],
              let width = raw["width"],
              let height = raw["height"] else {
            cachedFrame = nil
            return
        }

        cachedFrame = NSRect(x: x, y: y, width: width, height: height)
    }

    private func saveToDefaults() {
        guard let frame = cachedFrame else { return }

        UserDefaults.standard.set([
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
        ], forKey: storageKey)
    }
}
