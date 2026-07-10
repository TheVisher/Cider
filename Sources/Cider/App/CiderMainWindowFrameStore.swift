import AppKit

struct CiderMainWindowFrameSnapshot: Codable, Equatable {
    let frame: StoredRect
    let screenVisibleFrame: StoredRect
    let screenKey: String?

    struct StoredRect: Codable, Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat

        init(_ rect: NSRect) {
            x = rect.origin.x
            y = rect.origin.y
            width = rect.size.width
            height = rect.size.height
        }

        var rect: NSRect {
            NSRect(x: x, y: y, width: width, height: height)
        }
    }
}

final class CiderMainWindowFrameStore: @unchecked Sendable {
    static let shared = CiderMainWindowFrameStore()

    private let defaults: UserDefaults
    private let storageKey = "cider.mainWindow.frameSnapshot"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func snapshot() -> CiderMainWindowFrameSnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(CiderMainWindowFrameSnapshot.self, from: data)
    }

    func save(frame: NSRect, screen: NSScreen?) {
        let visibleFrame = screen?.visibleFrame ?? frame
        let snapshot = CiderMainWindowFrameSnapshot(
            frame: .init(frame),
            screenVisibleFrame: .init(visibleFrame),
            screenKey: screen.map(Self.screenKey)
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: storageKey)
        }
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    static func screenKey(for screen: NSScreen) -> String {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[screenNumberKey] as? NSNumber,
           let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
           let uuidString = CFUUIDCreateString(nil, uuid) as String? {
            return "display-uuid-\(uuidString.lowercased())"
        }

        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        return "size-\(Int(size.width * scale))x\(Int(size.height * scale))"
    }

    static func screen(_ screen: NSScreen, matches key: String) -> Bool {
        if screenKey(for: screen) == key {
            return true
        }

        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[screenNumberKey] as? NSNumber {
            return key == "display-\(number.uint32Value)"
        }
        return false
    }
}
