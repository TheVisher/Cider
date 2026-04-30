import AppKit

@MainActor
final class CiderPanelPositionStore {
    static let shared = CiderPanelPositionStore()

    private let storageKey = "CiderPanelFrame"
    private let perScreenStorageKey = "CiderPanelFramePerScreen"
    private let floatingStorageKey = "CiderFloatingPanelFrames"

    /// Legacy single-frame cache (fallback for first launch after upgrade)
    private var cachedFrame: NSRect?

    /// Per-screen frame cache, keyed by screen identifier (e.g. "3440x1440")
    private var perScreenFrames: [String: NSRect] = [:]

    /// Last known frame for each floatable surface, keyed by stable surface key.
    private var floatingFrames: [String: NSRect] = [:]

    private init() {
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

    func frame(forFloatingSurfaceKey surfaceKey: String) -> NSRect? {
        floatingFrames[surfaceKey]
    }

    func setFrame(_ frame: NSRect, forFloatingSurfaceKey surfaceKey: String) {
        floatingFrames[surfaceKey] = frame
        saveToDefaults()
    }

    func clear() {
        cachedFrame = nil
        perScreenFrames.removeAll()
        floatingFrames.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: perScreenStorageKey)
        UserDefaults.standard.removeObject(forKey: floatingStorageKey)
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

        if let dict = UserDefaults.standard.dictionary(forKey: floatingStorageKey) as? [String: [String: Double]] {
            for (surfaceKey, raw) in dict {
                if let x = raw["x"], let y = raw["y"], let w = raw["width"], let h = raw["height"] {
                    floatingFrames[surfaceKey] = NSRect(x: x, y: y, width: w, height: h)
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

        var floatingDict: [String: [String: Double]] = [:]
        for (surfaceKey, frame) in floatingFrames {
            floatingDict[surfaceKey] = Self.encodedFrame(frame)
        }
        UserDefaults.standard.set(floatingDict, forKey: floatingStorageKey)

    }

    private static func encodedFrame(_ frame: NSRect) -> [String: Double] {
        [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
        ]
    }
}
