import AppKit

@MainActor
final class CiderPanelPositionStore {
    static let shared = CiderPanelPositionStore()
    static let utilityPanelShared = CiderPanelPositionStore(
        storageKey: "CiderUtilityPanelFrame",
        perScreenStorageKey: "CiderUtilityPanelFramePerScreen"
    )

    private let storageKey: String
    private let perScreenStorageKey: String

    /// Legacy single-frame cache (fallback for first launch after upgrade)
    private var cachedFrame: NSRect?

    /// Per-screen frame cache, keyed by screen identifier (e.g. "3440x1440")
    private var perScreenFrames: [String: NSRect] = [:]

    private init(
        storageKey: String = "CiderPanelFrame",
        perScreenStorageKey: String = "CiderPanelFramePerScreen"
    ) {
        self.storageKey = storageKey
        self.perScreenStorageKey = perScreenStorageKey
        loadFromDefaults()
    }

    /// Returns the saved frame for the given screen, falling back to the legacy single frame.
    func frame(for screen: NSScreen? = nil) -> NSRect? {
        if let screen, let key = Self.screenKey(for: screen), let saved = perScreenFrames[key] {
            return saved
        }
        return cachedFrame
    }

    /// Saves the frame for the screen the panel is currently on.
    func setFrame(_ frame: NSRect) {
        cachedFrame = frame

        // Determine which screen the panel center is on
        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(center, $0.frame, false) }),
           let key = Self.screenKey(for: screen) {
            perScreenFrames[key] = frame
        }

        saveToDefaults()
    }

    func clear() {
        cachedFrame = nil
        perScreenFrames.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: perScreenStorageKey)
    }

    // MARK: - Screen Key

    /// Generates a stable key for a screen based on its pixel dimensions.
    /// Uses the backing store pixel size (retina-aware) for uniqueness.
    static func screenKey(for screen: NSScreen) -> String? {
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        let pw = Int(size.width * scale)
        let ph = Int(size.height * scale)
        return "\(pw)x\(ph)"
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        // Load legacy single frame
        if let raw = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Double],
           let x = raw["x"], let y = raw["y"], let w = raw["width"], let h = raw["height"] {
            cachedFrame = NSRect(x: x, y: y, width: w, height: h)
        }

        // Load per-screen frames
        if let dict = UserDefaults.standard.dictionary(forKey: perScreenStorageKey) as? [String: [String: Double]] {
            for (key, raw) in dict {
                if let x = raw["x"], let y = raw["y"], let w = raw["width"], let h = raw["height"] {
                    perScreenFrames[key] = NSRect(x: x, y: y, width: w, height: h)
                }
            }
        }
    }

    private func saveToDefaults() {
        // Save legacy single frame (backward compat)
        if let frame = cachedFrame {
            UserDefaults.standard.set([
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height,
            ], forKey: storageKey)
        }

        // Save per-screen frames
        var dict: [String: [String: Double]] = [:]
        for (key, frame) in perScreenFrames {
            dict[key] = [
                "x": frame.origin.x,
                "y": frame.origin.y,
                "width": frame.size.width,
                "height": frame.size.height,
            ]
        }
        UserDefaults.standard.set(dict, forKey: perScreenStorageKey)
    }
}
